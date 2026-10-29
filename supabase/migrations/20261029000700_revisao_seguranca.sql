-- Revisão de segurança (29/10/2026).
--  1. A distância mostrada ao cliente não revela mais a casa do profissional.
--  2. Nome e foto de clientes só aparecem para quem tem pedido com eles.
--  3. Avaliações só são lidas direto por quem participou (o público vê pelo perfil_profissional).
--  4. Profissional aprovado não passa a atender como Babá sem certidão de antecedentes aprovada.
--  5. Foto de perfil só pode ser um arquivo enviado ao iService.
--  6. pendencias_profissional() volta a funcionar no app e não mostra pendências de outras pessoas.
--  7. Limite de tamanho e de tipo nos arquivos enviados.
--  8. Na exclusão de conta, os arquivos vão para uma fila apagada pela função limpar-arquivos
--     (o Supabase não deixa apagar arquivos por SQL).

-- ---------------------------------------------------------------------------
-- 1. Centro aproximado da área de atendimento
-- ---------------------------------------------------------------------------
-- O centro da área costuma ser o endereço de casa do profissional. Com a distância
-- exata, três buscas de pontos diferentes bastavam para achar a casa dele. Agora
-- busca, alcance e distância usam o centro arredondado para uma grade de ~1 km.
create or replace function public.centro_publico(p_centro extensions.geography)
returns extensions.geography
language sql immutable
set search_path = public, extensions
as $$ select extensions.st_snaptogrid(p_centro::extensions.geometry, 0.01)::extensions.geography $$;

revoke all on function public.centro_publico(extensions.geography) from public, anon;
grant execute on function public.centro_publico(extensions.geography) to authenticated;

create or replace function public.buscar_profissionais(
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
    novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, sorteio text
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
    md5(pr.id::text || p_rodizio::text || current_date::text)
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
      row_number() over (partition by c.novo order by c.nota_media desc, c.total_avaliacoes desc, c.servicos_concluidos desc, c.distancia_km) - 1 as k_top,
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
      t.nota_media desc, t.servicos_concluidos desc, t.total_avaliacoes desc, t.dist))::int
  from (
    select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos,
      round((extensions.st_distance(public.centro_publico(pr.area_centro), v_local) / 1000)::numeric, 1) as dist,
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

create or replace function public.criar_pedido(
  p_profissional uuid,
  p_profissao text,
  p_endereco_id bigint,
  p_quando public.quando_pedido,
  p_especialidade bigint default null,
  p_descricao text default '',
  p_janela text default null,
  p_combinado_para timestamptz default null,
  p_fotos text[] default '{}'
)
returns public.pedidos
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_end public.enderecos;
  v_pro public.profissionais;
  v_ped public.pedidos;
  v_nome_cliente text;
  v_preco numeric;
  v_dist numeric;
begin
  if v_uid is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if not coalesce((select e_cliente from public.perfis where id = v_uid), false) then
    perform public.erro('cadastro_incompleto', 'Complete seu cadastro, com foto, para fazer pedidos.');
  end if;
  if v_uid = p_profissional then perform public.erro('pedido_proprio', 'Você não pode contratar a si mesmo.'); end if;

  select * into v_end from public.enderecos where id = p_endereco_id and usuario_id = v_uid;
  if v_end.id is null then perform public.erro('endereco_invalido', 'Escolha um endereço válido.'); end if;

  select * into v_pro from public.profissionais where id = p_profissional;
  if v_pro.id is null or v_pro.status <> 'aprovado' then
    perform public.erro('profissional_indisponivel', 'Este profissional não está disponível.');
  end if;
  if not exists (select 1 from public.profissional_profissoes where profissional_id = p_profissional and profissao_id = p_profissao) then
    perform public.erro('profissao_invalida', 'Este profissional não atende essa profissão.');
  end if;
  if p_especialidade is not null then
    select x.preco into v_preco from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
    where x.profissional_id = p_profissional and x.especialidade_id = p_especialidade and e.profissao_id = p_profissao;
    if not found then perform public.erro('especialidade_invalida', 'Este profissional não oferece essa especialidade.'); end if;
  end if;

  v_dist := round((extensions.st_distance(public.centro_publico(v_pro.area_centro), v_end.localizacao) / 1000)::numeric, 2);
  if v_pro.area_centro is null or v_dist > public.alcance_km(v_pro.area_raio_km, v_pro.plano, v_pro.plano_valido_ate) then
    perform public.erro('fora_da_area', 'Este profissional não atende o seu endereço.');
  end if;

  if p_quando in ('agora', 'hoje') then
    if not v_pro.disponivel or public.em_atendimento(p_profissional) then
      perform public.erro('profissional_ocupado', 'Este profissional acabou de ficar indisponível. Escolha outro.');
    end if;
  else
    if p_combinado_para < now() + interval '30 minutes' or p_combinado_para > now() + make_interval(days => public.cfg_num('dias_max_combinado', 7)::int) then
      perform public.erro('horario_invalido', 'Escolha um horário entre daqui a 30 minutos e os próximos 7 dias.');
    end if;
  end if;

  if exists (select 1 from public.pedidos where cliente_id = v_uid and status = 'solicitado' and responder_ate > now()) then
    perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando resposta.');
  end if;

  insert into public.pedidos (
    cliente_id, profissional_id, profissao_id, especialidade_id, descricao, fotos, quando, janela, combinado_para,
    endereco_id, endereco_texto, regiao_id, localizacao, distancia_km, preco_informado, taxa_urgencia, responder_ate
  ) values (
    v_uid, p_profissional, p_profissao, p_especialidade, coalesce(p_descricao, ''), coalesce(p_fotos, '{}'), p_quando,
    case when p_quando = 'hoje' then coalesce(p_janela, 'Hoje') else p_janela end,
    case when p_quando = 'combinado' then p_combinado_para end,
    v_end.id,
    concat_ws(', ', v_end.logradouro, v_end.bloco, v_end.numero, v_end.complemento, v_end.cidade || '/' || v_end.uf),
    v_end.regiao_id, v_end.localizacao, v_dist, v_preco,
    case when p_quando = 'agora' then public.cfg_num('taxa_urgencia', 15) else 0 end,
    now() + make_interval(mins => public.cfg_num('prazo_resposta_min', 10)::int)
  ) returning * into v_ped;

  update public.profissionais set pedidos_recebidos = pedidos_recebidos + 1 where id = p_profissional;
  select split_part(nome, ' ', 1) into v_nome_cliente from public.perfis where id = v_uid;
  perform public.notificar(p_profissional, 'pedido_novo', 'Novo pedido de ' || v_nome_cliente,
    'Você tem ' || public.cfg_num('prazo_resposta_min', 10) || ' minutos para responder.', jsonb_build_object('pedido_id', v_ped.id));
  return v_ped;
end;
$$;

-- create or replace apaga o fuso definido antes; reaplica.
alter function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) set timezone = 'America/Sao_Paulo';
alter function public.top_regiao(double precision, double precision, text, integer, integer) set timezone = 'America/Sao_Paulo';

-- ---------------------------------------------------------------------------
-- 2. Perfis: cada um vê o próprio, os profissionais e quem já teve pedido com ele
-- ---------------------------------------------------------------------------
drop policy if exists "perfis: leitura" on public.perfis;
create policy "perfis: leitura" on public.perfis for select to authenticated using (
  id = auth.uid()
  or e_profissional
  or exists (select 1 from public.pedidos p
             where (p.cliente_id = perfis.id and p.profissional_id = auth.uid())
                or (p.profissional_id = perfis.id and p.cliente_id = auth.uid()))
  or public.e_admin()
);

-- ---------------------------------------------------------------------------
-- 3. Avaliações: leitura direta só para os envolvidos
-- ---------------------------------------------------------------------------
drop policy if exists "avaliacoes: leitura" on public.avaliacoes;
create policy "avaliacoes: leitura" on public.avaliacoes for select to authenticated
  using (auth.uid() in (cliente_id, profissional_id) or public.e_admin());

-- ---------------------------------------------------------------------------
-- 4. Profissão que exige antecedentes depois do envio do cadastro
-- ---------------------------------------------------------------------------
create or replace function public.exigir_antecedentes()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.profissoes where id = new.profissao_id and exige_antecedentes)
    and exists (select 1 from public.profissionais where id = new.profissional_id and status not in ('rascunho', 'recusado'))
    and not exists (select 1 from public.documentos where profissional_id = new.profissional_id and tipo = 'antecedentes' and status = 'aprovado')
  then
    perform public.erro('antecedentes_obrigatorio',
      'Para atender nessa profissão, envie a certidão de antecedentes criminais e aguarde a aprovação da equipe iService.');
  end if;
  return new;
end;
$$;
revoke all on function public.exigir_antecedentes() from public, anon, authenticated;
drop trigger if exists exigir_antecedentes on public.profissional_profissoes;
create trigger exigir_antecedentes before insert on public.profissional_profissoes
  for each row execute function public.exigir_antecedentes();

-- ---------------------------------------------------------------------------
-- 5. Foto de perfil: só arquivo da pasta do próprio usuário no bucket "fotos"
-- ---------------------------------------------------------------------------
-- Antes dava para gravar qualquer link da internet (fugindo da foto obrigatória
-- e permitindo rastrear quem abre o perfil).
alter table public.perfis drop constraint if exists perfis_foto_do_iservice;
alter table public.perfis add constraint perfis_foto_do_iservice check (
  foto_url is null
  or foto_url ~ ('^(https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/)?fotos/' || id::text || '/[^/?#]+$')
) not valid;

-- ---------------------------------------------------------------------------
-- 6. Pendências: só as próprias (ou admin). Antes falhava por falta de permissão.
-- ---------------------------------------------------------------------------
create or replace function public.pendencias_profissional(p_id uuid)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.pendencias_basicas(p_id), '{}') || array_remove(array[
    case when pr.area_centro is null then 'area_atendimento' end,
    case when not exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = p_id) then 'profissao' end,
    case when exists (
      select 1 from public.profissional_profissoes pp
      where pp.profissional_id = p_id and not exists (
        select 1 from public.profissional_especialidades pe join public.especialidades e on e.id = pe.especialidade_id
        where pe.profissional_id = p_id and e.profissao_id = pp.profissao_id and pe.preco is not null)
    ) then 'especialidades_e_precos' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'documento_frente' and d.status <> 'recusado') then 'documento' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'selfie_documento' and d.status <> 'recusado') then 'selfie' end,
    case when exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = p_id and f.exige_antecedentes)
      and not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'antecedentes' and d.status <> 'recusado') then 'antecedentes' end
  ], null)
  from public.profissionais pr
  where pr.id = p_id and (p_id = auth.uid() or public.e_admin() or auth.uid() is null)
$$;
revoke all on function public.pendencias_profissional(uuid) from public, anon;
grant execute on function public.pendencias_profissional(uuid) to authenticated;
revoke all on function public.pendencias_basicas(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Arquivos: tamanho e tipo
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'storage' and table_name = 'buckets' and column_name = 'allowed_mime_types') then
    update storage.buckets set file_size_limit = 5 * 1024 * 1024,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
    where id in ('fotos', 'portfolio', 'avaliacoes', 'pedidos');
    update storage.buckets set file_size_limit = 10 * 1024 * 1024,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf']
    where id = 'documentos';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Exclusão de conta: arquivos numa fila para a função limpar-arquivos
-- ---------------------------------------------------------------------------
create table if not exists public.arquivos_a_apagar (
  usuario_id uuid primary key,
  pedido_em timestamptz not null default now()
);
alter table public.arquivos_a_apagar enable row level security;
revoke all on public.arquivos_a_apagar from anon, authenticated;

create or replace function public.excluir_contas_vencidas()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id from public.perfis
    where exclusao_solicitada_em is not null and excluido_em is null
      and exclusao_solicitada_em <= now() - make_interval(days => public.cfg_num('dias_exclusao_conta', 30)::int)
  loop
    n := n + 1;
    -- Foto, documentos, selfie, portfólio e fotos de avaliação: o Storage só apaga
    -- pela API, então a pasta do usuário entra na fila da função limpar-arquivos.
    insert into public.arquivos_a_apagar (usuario_id) values (r.id) on conflict do nothing;
    begin
      delete from auth.users where id = r.id;
    exception when foreign_key_violation then
      delete from public.enderecos where usuario_id = r.id;
      delete from public.favoritos where cliente_id = r.id or profissional_id = r.id;
      delete from public.notificacoes where usuario_id = r.id;
      delete from public.dispositivos where usuario_id = r.id;
      delete from public.pontos where usuario_id = r.id;
      delete from public.indicacoes where indicado_id = r.id or indicador_id = r.id;
      delete from public.documentos where profissional_id = r.id;
      delete from public.certificacoes where profissional_id = r.id;
      delete from public.portfolio where profissional_id = r.id;
      delete from public.profissional_especialidades where profissional_id = r.id;
      delete from public.profissional_profissoes where profissional_id = r.id;
      update public.profissionais set status = 'suspenso', disponivel = false, bio = null, area_centro = null,
        motivo_status = 'Conta excluída' where id = r.id;
      update public.perfis set nome = 'Conta excluída', email = null, telefone = null, cpf = null, nascimento = null,
        foto_url = null, e_cliente = false, e_profissional = false, excluido_em = now() where id = r.id;
      update public.mensagens set texto = 'Mensagem apagada' where autor_id = r.id;
      update public.avaliacoes set fotos = '{}' where cliente_id = r.id;
      -- Login desativado para sempre.
      update auth.users set email = null, encrypted_password = '', raw_user_meta_data = '{}'::jsonb where id = r.id;
      begin
        execute 'update auth.users set phone = null, banned_until = ''infinity'' where id = $1' using r.id;
      exception when undefined_column then null;
      end;
      begin
        execute 'delete from auth.identities where user_id = $1' using r.id;
        execute 'delete from auth.sessions where user_id = $1' using r.id;
      exception when undefined_table then null;
      end;
    end;
  end loop;
  return n;
end;
$$;
revoke all on function public.excluir_contas_vencidas() from public, anon, authenticated;
