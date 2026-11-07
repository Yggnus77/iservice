-- Resposta mais rápida dos profissionais (07/11/2026).
-- 1. Prazo para responder um pedido "agora" ou "hoje" cai de 10 para 5 minutos
--    (continua ajustável no painel, em Configurações > prazo_resposta_min).
-- 2. Cada pedido guarda quando o profissional respondeu (aceitou, recusou,
--    sugeriu outro horário ou deixou expirar). A mediana das últimas respostas
--    vira o "costuma responder em X min" do perfil.
-- 3. Quem responde rápido ganha um peso leve no ranking: até +0,15 estrela na
--    ordenação (ajustável em peso_resposta_rapida). A nota continua mandando.
-- O pedido continua direcionado: só o profissional escolhido recebe.

update public.app_config set valor = '5'::jsonb, atualizado_em = now() where chave = 'prazo_resposta_min';
insert into public.app_config (chave, valor, descricao) values
  ('peso_resposta_rapida', '0.15'::jsonb, 'Quanto a resposta rápida soma à nota na ordem da busca (em estrelas). 0 desliga.'),
  ('min_respostas_tempo', '3'::jsonb, 'Respostas necessárias para mostrar "costuma responder em X min" e usar no ranking.'),
  ('respostas_tempo_amostra', '20'::jsonb, 'Quantas respostas recentes entram na conta do tempo de resposta.')
on conflict (chave) do nothing;

alter table public.pedidos add column if not exists respondido_em timestamptz;
alter table public.profissionais
  add column if not exists tempo_resposta_seg integer,
  add column if not exists respostas_medidas integer not null default 0;

-- Marca a primeira resposta do profissional. Cancelamento pelo cliente não conta.
-- Expirar conta como o prazo inteiro. Um prazo novo e mais longo enquanto o
-- pedido segue "solicitado" é o profissional sugerindo outro horário.
create or replace function public.marcar_resposta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'solicitado' and old.respondido_em is null and new.respondido_em is null then
    if new.status = 'expirado' then
      new.respondido_em := least(old.responder_ate, now());
    elsif new.status in ('aceito', 'recusado') then
      new.respondido_em := now();
    elsif new.status = 'solicitado' and new.responder_ate > old.responder_ate then
      new.respondido_em := now();
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists marcar_resposta on public.pedidos;
create trigger marcar_resposta before update on public.pedidos for each row execute function public.marcar_resposta();

-- Mediana das últimas respostas a pedidos para agora/hoje (agendados têm outro prazo).
create or replace function public.recalcular_tempo_resposta(p_profissional uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profissionais pr set
    tempo_resposta_seg = s.mediana,
    respostas_medidas = s.n
  from (
    select round(percentile_cont(0.5) within group (order by seg))::int as mediana, count(*)::int as n
    from (
      select greatest(0, extract(epoch from p.respondido_em - p.criado_em)) as seg
      from public.pedidos p
      where p.profissional_id = p_profissional and p.respondido_em is not null and p.quando <> 'combinado'
      order by p.respondido_em desc
      limit public.cfg_num('respostas_tempo_amostra', 20)::int
    ) u
  ) s
  where pr.id = p_profissional
$$;
revoke all on function public.recalcular_tempo_resposta(uuid) from public, anon, authenticated;

create or replace function public.atualizar_tempo_resposta()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.respondido_em is not null and old.respondido_em is null and new.quando <> 'combinado' then
    perform public.recalcular_tempo_resposta(new.profissional_id);
  end if;
  return null;
end;
$$;
drop trigger if exists atualizar_tempo_resposta on public.pedidos;
-- Sem "of respondido_em": a coluna é preenchida pelo gatilho acima, não pelo update.
create trigger atualizar_tempo_resposta after update on public.pedidos
  for each row when (new.respondido_em is not null and old.respondido_em is null)
  execute function public.atualizar_tempo_resposta();

-- Bônus na ordenação: o peso inteiro para resposta imediata, zero para quem
-- usa o prazo todo. Sem histórico suficiente fica no meio, para não punir quem
-- é novo nem premiar quem ainda não provou.
create or replace function public.bonus_resposta(p_seg integer, p_n integer)
returns numeric
language plpgsql stable
set search_path = public
as $$
declare
  v_peso numeric := public.cfg_num('peso_resposta_rapida', 0.15);
  v_prazo numeric := greatest(public.cfg_num('prazo_resposta_min', 5) * 60, 60);
begin
  if p_seg is null or coalesce(p_n, 0) < public.cfg_num('min_respostas_tempo', 3) then
    return round(v_peso / 2, 3);
  end if;
  return round(v_peso * greatest(0, 1 - p_seg / v_prazo), 3);
end;
$$;
revoke all on function public.bonus_resposta(integer, integer) from public, anon;
grant execute on function public.bonus_resposta(integer, integer) to authenticated;

-- Histórico: preenche as respostas que já existem e calcula o tempo de todos.
alter table public.pedidos disable trigger marcar_resposta;
alter table public.pedidos disable trigger atualizar_tempo_resposta;
update public.pedidos set respondido_em = case
    when aceito_em is not null then aceito_em
    when status = 'recusado' then encerrado_em
    when status = 'expirado' then least(responder_ate, coalesce(encerrado_em, responder_ate))
  end
where respondido_em is null and (aceito_em is not null or status in ('recusado', 'expirado'));
alter table public.pedidos enable trigger marcar_resposta;
alter table public.pedidos enable trigger atualizar_tempo_resposta;
do $$ begin perform public.recalcular_tempo_resposta(id) from public.profissionais; end $$;

-- Busca, Top da região e perfil passam a usar o tempo de resposta.
create or replace function public.buscar_profissionais_base(
  p_profissao text,
  p_lat double precision,
  p_lng double precision,
  p_especialidade bigint default null,
  p_ordem text default 'qualidade',
  p_rodizio integer default 0,
  p_limite integer default 50
)
returns table (
  profissional_id uuid,
  nome text,
  foto_url text,
  nota_media numeric,
  total_avaliacoes integer,
  servicos_concluidos integer,
  anos_experiencia smallint,
  verificado boolean,
  distancia_km numeric,
  novo boolean,
  preco_a_partir numeric,
  especialidades text[],
  favorito boolean,
  fase_lancamento boolean,
  posicao integer
)
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_local extensions.geography := public.ponto(p_lat, p_lng);
  v_min_aval int := public.cfg_num('min_avaliacoes_ranking', 5);
  v_min_top int := public.cfg_num('min_profissionais_ranking', 3);
  v_ntop int;
  v_lanc boolean;
begin
  create temporary table if not exists _cand (
    profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer,
    servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric,
    novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, sorteio text, bonus numeric
  ) on commit drop;
  truncate _cand;

  insert into _cand
  select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos, pr.anos_experiencia, pr.verificado,
    round((extensions.st_distance(public.centro_publico(pr.area_centro), v_local) / 1000)::numeric, 1),
    pr.total_avaliacoes < v_min_aval,
    (select min(x.preco) from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao and (p_especialidade is null or e.id = p_especialidade)),
    array(select e.nome from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao order by e.ordem, e.nome),
    exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    md5(pr.id::text || p_rodizio::text || current_date::text),
    public.bonus_resposta(pr.tempo_resposta_seg, pr.respostas_medidas)
  from public.profissionais pr
  join public.perfis pe on pe.id = pr.id
  join public.profissional_profissoes pp on pp.profissional_id = pr.id and pp.profissao_id = p_profissao
  where pr.status = 'aprovado'
    and pr.disponivel
    and pr.area_centro is not null
    and pr.id is distinct from auth.uid()
    and extensions.st_dwithin(public.centro_publico(pr.area_centro), v_local, public.alcance_km(pr.area_raio_km, pr.plano, pr.plano_valido_ate) * 1000)
    and (p_especialidade is null or exists (
      select 1 from public.profissional_especialidades x where x.profissional_id = pr.id and x.especialidade_id = p_especialidade))
    and not public.em_atendimento(pr.id);

  select count(*) filter (where not c.novo) into v_ntop from _cand c;
  v_lanc := v_ntop < v_min_top;

  return query
  with ordenado as (
    select c.*,
      -- posição de cada um dentro do seu grupo (com 5+ avaliações ou novo)
      row_number() over (partition by c.novo order by c.nota_media + c.bonus desc, c.total_avaliacoes desc, c.servicos_concluidos desc, c.distancia_km) - 1 as k_top,
      row_number() over (partition by c.novo order by c.sorteio) - 1 as k_rodizio,
      row_number() over (order by c.sorteio) as k_lanc
    from _cand c
  ),
  chave as (
    select o.*,
      case
        when p_ordem = 'distancia' then o.distancia_km * 1000
        when v_lanc then o.k_lanc
        -- dois bem avaliados, um novo, dois bem avaliados, um novo...
        when not o.novo then o.k_top + floor(o.k_top / 2.0)
        when o.k_rodizio < floor(v_ntop / 2.0) then o.k_rodizio * 3 + 2
        else 1000000 + o.k_rodizio
      end as ordem_final
    from ordenado o
  )
  select ch.profissional_id, ch.nome, ch.foto_url, ch.nota_media, ch.total_avaliacoes, ch.servicos_concluidos, ch.anos_experiencia,
    ch.verificado, ch.distancia_km, ch.novo, ch.preco_a_partir, ch.especialidades, ch.favorito, v_lanc,
    (row_number() over (order by ch.ordem_final, ch.distancia_km))::int
  from chave ch
  order by ch.ordem_final, ch.distancia_km
  limit p_limite;
end;
$$;

create or replace function public.top_regiao(
  p_lat double precision,
  p_lng double precision,
  p_profissao text default null,
  p_limite integer default 10,
  p_rodizio integer default 0
)
returns table (
  profissional_id uuid,
  nome text,
  foto_url text,
  profissao_id text,
  nota_media numeric,
  total_avaliacoes integer,
  servicos_concluidos integer,
  distancia_km numeric,
  fase_lancamento boolean,
  posicao integer
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_local extensions.geography := public.ponto(p_lat, p_lng);
  v_raio numeric := public.cfg_num('raio_top_regiao_km', 15);
  v_min_aval int := public.cfg_num('min_avaliacoes_ranking', 5);
  v_lanc boolean;
begin
  select count(*) < public.cfg_num('min_profissionais_ranking', 3) into v_lanc
  from public.profissionais pr
  where pr.status = 'aprovado' and pr.total_avaliacoes >= v_min_aval and pr.area_centro is not null
    and extensions.st_dwithin(public.centro_publico(pr.area_centro), v_local, v_raio * 1000)
    and (p_profissao is null or exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao));

  return query
  select t.id, t.nome, t.foto_url, t.profissao_id, t.nota_media, t.total_avaliacoes, t.servicos_concluidos, t.dist, v_lanc,
    (row_number() over (order by
      case when v_lanc then md5(t.id::text || p_rodizio::text || current_date::text) end,
      t.nota_media + t.bonus desc, t.servicos_concluidos desc, t.total_avaliacoes desc, t.dist))::int
  from (
    select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos,
      round((extensions.st_distance(public.centro_publico(pr.area_centro), v_local) / 1000)::numeric, 1) as dist,
      public.bonus_resposta(pr.tempo_resposta_seg, pr.respostas_medidas) as bonus,
      coalesce(
        (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao),
        (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id order by pp.principal desc, pp.profissao_id limit 1)
      ) as profissao_id
    from public.profissionais pr
    join public.perfis pe on pe.id = pr.id
    where pr.status = 'aprovado' and pr.disponivel and pr.area_centro is not null
      and extensions.st_dwithin(public.centro_publico(pr.area_centro), v_local, least(v_raio, public.alcance_km(pr.area_raio_km, pr.plano, pr.plano_valido_ate)) * 1000)
      and not public.em_atendimento(pr.id)
      and (v_lanc or pr.total_avaliacoes >= v_min_aval)
      and (p_profissao is null or exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao))
  ) t
  order by 10
  limit p_limite;
end;
$$;

create or replace function public.perfil_profissional(p_id uuid)
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'id', pr.id,
    'nome', pe.nome,
    'foto_url', pe.foto_url,
    'bio', pr.bio,
    'anos_experiencia', pr.anos_experiencia,
    'verificado', pr.verificado,
    'disponivel', pr.disponivel and not public.em_atendimento(pr.id),
    'nota_media', pr.nota_media,
    'total_avaliacoes', pr.total_avaliacoes,
    'servicos_concluidos', pr.servicos_concluidos,
    -- "Costuma responder em X min": só com respostas suficientes para ser justo.
    'tempo_resposta_seg', case when pr.respostas_medidas >= public.cfg_num('min_respostas_tempo', 3) then pr.tempo_resposta_seg end,
    'novo', pr.total_avaliacoes < public.cfg_num('min_avaliacoes_ranking', 5),
    'regiao', (select r.nome from public.regioes r where r.id = pr.regiao_id),
    'membro_desde', pr.aprovado_em,
    'favorito', exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    'profissoes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'nome', f.nome, 'icone', f.icone,
        'especialidades', coalesce((
          select jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'preco', x.preco, 'cobranca', x.cobranca) order by e.ordem, e.nome)
          from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
          where x.profissional_id = pr.id and e.profissao_id = f.id), '[]'::jsonb)
      ) order by pp.principal desc, f.ordem)
      from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
      where pp.profissional_id = pr.id), '[]'::jsonb),
    'certificacoes', coalesce((
      select jsonb_agg(jsonb_build_object('nome', c.nome, 'instituicao', c.instituicao, 'profissao_id', c.profissao_id))
      from public.certificacoes c where c.profissional_id = pr.id and c.status = 'aprovado'), '[]'::jsonb),
    'portfolio', coalesce((
      select jsonb_agg(jsonb_build_object('id', po.id, 'descricao', po.descricao, 'antes_path', po.antes_path, 'depois_path', po.depois_path) order by po.ordem, po.id)
      from public.portfolio po where po.profissional_id = pr.id), '[]'::jsonb),
    'avaliacoes_recentes', coalesce((
      select jsonb_agg(a) from (
        select jsonb_build_object('pedido_id', av.pedido_id, 'nota', av.nota, 'comentario', av.comentario, 'fotos', av.fotos, 'resposta', av.resposta,
          'criada_em', av.criada_em, 'cliente_nome', split_part(c.nome, ' ', 1), 'cliente_foto', c.foto_url) as a
        from public.avaliacoes av join public.perfis c on c.id = av.cliente_id
        where av.profissional_id = pr.id and not av.oculta order by av.criada_em desc limit 10) s), '[]'::jsonb),
    'distribuicao_notas', (
      select jsonb_build_object('5', count(*) filter (where nota = 5), '4', count(*) filter (where nota = 4),
        '3', count(*) filter (where nota = 3), '2', count(*) filter (where nota = 2), '1', count(*) filter (where nota = 1))
      from public.avaliacoes where profissional_id = pr.id and not oculta)
  )
  from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where pr.id = p_id and (pr.status = 'aprovado' or pr.id = auth.uid() or public.e_admin())
$$;
