-- Preço médio obrigatório em cada especialidade, com a forma de cobrança.
--
-- O profissional informa quanto cobra em média e se é por serviço, por hora
-- ou por diária. A faixa da região compara só preços da mesma forma de
-- cobrança e, quando há amostras, usa a própria região antes da faixa.

do $$
begin
  create type public.forma_cobranca as enum ('servico', 'hora', 'diaria');
exception when duplicate_object then null;
end;
$$;

-- Forma de cobrança mais comum de cada profissão; preco_base está nela.
alter table public.profissoes add column if not exists cobranca_padrao public.forma_cobranca not null default 'servico';
update public.profissoes set cobranca_padrao = 'diaria' where id in ('faxineira', 'pedreiro', 'pintor');

alter table public.profissional_especialidades add column if not exists cobranca public.forma_cobranca;
update public.profissional_especialidades x set cobranca = f.cobranca_padrao
from public.especialidades e join public.profissoes f on f.id = e.profissao_id
where e.id = x.especialidade_id and x.cobranca is null;
update public.profissional_especialidades set cobranca = 'servico' where cobranca is null;
alter table public.profissional_especialidades alter column cobranca set not null;
grant update (cobranca) on public.profissional_especialidades to authenticated;

-- Ao marcar uma especialidade, já vem com a cobrança comum da profissão.
create or replace function public.cobranca_padrao_especialidade()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cobranca is null then
    select f.cobranca_padrao into new.cobranca
    from public.especialidades e join public.profissoes f on f.id = e.profissao_id where e.id = new.especialidade_id;
    new.cobranca := coalesce(new.cobranca, 'servico');
  end if;
  return new;
end;
$$;
drop trigger if exists cobranca_padrao on public.profissional_especialidades;
create trigger cobranca_padrao before insert on public.profissional_especialidades
  for each row execute function public.cobranca_padrao_especialidade();

insert into public.app_config (chave, valor, descricao) values
  ('fator_cobranca', '{"servico": 1, "hora": 0.4, "diaria": 2.5}'::jsonb,
   'Conversão aproximada entre formas de cobrança, usada só na referência base (antes de haver preços reais).')
on conflict (chave) do nothing;

-- O ajuste da equipe passa a valer por forma de cobrança.
alter table public.precos_referencia add column if not exists cobranca public.forma_cobranca not null default 'servico';
alter table public.precos_referencia drop constraint if exists precos_referencia_pkey;
alter table public.precos_referencia add primary key (especialidade_id, faixa, cobranca);

-- ---------------------------------------------------------------------------
-- Pendência: toda especialidade marcada precisa de preço (antes bastava uma).
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
        where pe.profissional_id = p_id and e.profissao_id = pp.profissao_id)
    ) or exists (
      select 1 from public.profissional_especialidades pe where pe.profissional_id = p_id and pe.preco is null
    ) then 'especialidades_e_precos' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'documento_frente' and d.status <> 'recusado') then 'documento' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'selfie_documento' and d.status <> 'recusado') then 'selfie' end,
    case when exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = p_id and f.exige_antecedentes)
      and not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'antecedentes' and d.status <> 'recusado') then 'antecedentes' end
  ], null)
  from public.profissionais pr
  where pr.id = p_id and (p_id = auth.uid() or public.e_admin() or auth.uid() is null)
$$;

-- ---------------------------------------------------------------------------
-- Faixa de preço por forma de cobrança
-- ---------------------------------------------------------------------------
drop function if exists public.admin_tabela_precos(text);
drop function if exists public.admin_ajustar_preco(bigint, smallint, numeric, numeric);
drop function if exists public.faixa_preco(bigint, text);
drop function if exists public.faixa_preco_calculada(bigint, smallint);

-- Faixa calculada pelos preços dos profissionais aprovados (ou pela base), sem o ajuste da equipe.
-- p_regiao: quando informada e com amostras suficientes, usa só aquela região.
create or replace function public.faixa_preco_calculada(p_especialidade bigint, p_faixa smallint,
  p_cobranca public.forma_cobranca default 'servico', p_regiao text default null)
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_min int := public.cfg_num('min_amostras_preco', 5);
  v_n int;
  v_p25 numeric;
  v_p75 numeric;
  v_base numeric;
  v_fator numeric;
  v_conv numeric;
begin
  if p_regiao is not null then
    select count(*), percentile_cont(0.25) within group (order by x.preco), percentile_cont(0.75) within group (order by x.preco)
    into v_n, v_p25, v_p75
    from public.profissional_especialidades x
    join public.profissionais pr on pr.id = x.profissional_id and pr.status = 'aprovado' and pr.regiao_id = p_regiao
    where x.especialidade_id = p_especialidade and x.cobranca = p_cobranca and x.preco is not null;
    if v_n >= v_min then
      return query select round(v_p25 / 5) * 5, round(v_p75 / 5) * 5, v_n, false;
      return;
    end if;
  end if;

  select count(*), percentile_cont(0.25) within group (order by x.preco), percentile_cont(0.75) within group (order by x.preco)
  into v_n, v_p25, v_p75
  from public.profissional_especialidades x
  join public.profissionais pr on pr.id = x.profissional_id and pr.status = 'aprovado'
  join public.regioes r on r.id = pr.regiao_id and r.faixa_preco = p_faixa
  where x.especialidade_id = p_especialidade and x.cobranca = p_cobranca and x.preco is not null;

  if v_n >= v_min then
    return query select round(v_p25 / 5) * 5, round(v_p75 / 5) * 5, v_n, false;
    return;
  end if;

  select f.preco_base + greatest(e.ordem, 0) * 20,
    coalesce((public.cfg('fator_cobranca') ->> p_cobranca::text)::numeric, 1)
      / coalesce(nullif((public.cfg('fator_cobranca') ->> f.cobranca_padrao::text)::numeric, 0), 1)
  into v_base, v_conv
  from public.especialidades e join public.profissoes f on f.id = e.profissao_id where e.id = p_especialidade;
  v_fator := coalesce((public.cfg('fator_faixa_preco') ->> p_faixa::text)::numeric, 1);
  return query select round(v_base * v_conv * v_fator * 0.9 / 5) * 5, round(v_base * v_conv * v_fator * 1.8 / 5) * 5, coalesce(v_n, 0), true;
end;
$$;
revoke all on function public.faixa_preco_calculada(bigint, smallint, public.forma_cobranca, text) from public, anon, authenticated;

-- O que os apps mostram: o ajuste da equipe, quando existe; senão, a faixa calculada.
create or replace function public.faixa_preco(p_especialidade bigint, p_regiao text, p_cobranca public.forma_cobranca default 'servico')
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_faixa smallint := coalesce((select faixa_preco from public.regioes where id = p_regiao), 2);
  v_aj public.precos_referencia;
  v_calc record;
begin
  select * into v_calc from public.faixa_preco_calculada(p_especialidade, v_faixa, p_cobranca, p_regiao);
  select * into v_aj from public.precos_referencia
  where especialidade_id = p_especialidade and faixa = v_faixa and cobranca = p_cobranca;
  if v_aj.especialidade_id is not null then
    return query select v_aj.minimo, v_aj.maximo, v_calc.amostras, false;
    return;
  end if;
  return query select v_calc.minimo, v_calc.maximo, v_calc.amostras, v_calc.estimada;
end;
$$;
revoke all on function public.faixa_preco(bigint, text, public.forma_cobranca) from public;
grant execute on function public.faixa_preco(bigint, text, public.forma_cobranca) to anon, authenticated;

create or replace function public.admin_tabela_precos(p_profissao text, p_cobranca public.forma_cobranca default 'servico')
returns table (especialidade_id bigint, especialidade text, faixa smallint, minimo numeric, maximo numeric, amostras integer,
  estimada boolean, ajuste_minimo numeric, ajuste_maximo numeric, ajustado_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select e.id, e.nome, fx.f::smallint, c.minimo, c.maximo, c.amostras, c.estimada, aj.minimo, aj.maximo, aj.atualizado_em
  from public.especialidades e
  cross join generate_series(1, 5) fx(f)
  cross join lateral public.faixa_preco_calculada(e.id, fx.f::smallint, p_cobranca) c
  left join public.precos_referencia aj on aj.especialidade_id = e.id and aj.faixa = fx.f and aj.cobranca = p_cobranca
  where e.profissao_id = p_profissao and e.aprovada
  order by e.ordem, e.nome, fx.f;
end;
$$;

create or replace function public.admin_ajustar_preco(p_especialidade bigint, p_faixa smallint, p_minimo numeric default null,
  p_maximo numeric default null, p_cobranca public.forma_cobranca default 'servico')
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if p_minimo is null and p_maximo is null then
    delete from public.precos_referencia where especialidade_id = p_especialidade and faixa = p_faixa and cobranca = p_cobranca;
  else
    if p_minimo is null or p_maximo is null or p_minimo <= 0 or p_maximo < p_minimo then
      perform public.erro('faixa_invalida', 'Informe um valor mínimo e um máximo, com o máximo maior ou igual ao mínimo.');
    end if;
    insert into public.precos_referencia (especialidade_id, faixa, cobranca, minimo, maximo, atualizado_por)
    values (p_especialidade, p_faixa, p_cobranca, p_minimo, p_maximo, auth.uid())
    on conflict (especialidade_id, faixa, cobranca) do update set minimo = excluded.minimo, maximo = excluded.maximo,
      atualizado_por = excluded.atualizado_por, atualizado_em = now();
  end if;
  perform public.registrar_acao('ajustar_preco', p_especialidade::text,
    jsonb_build_object('faixa', p_faixa, 'cobranca', p_cobranca, 'minimo', p_minimo, 'maximo', p_maximo));
end;
$$;
revoke all on function public.admin_tabela_precos(text, public.forma_cobranca) from public, anon;
grant execute on function public.admin_tabela_precos(text, public.forma_cobranca) to authenticated;
revoke all on function public.admin_ajustar_preco(bigint, smallint, numeric, numeric, public.forma_cobranca) from public, anon;
grant execute on function public.admin_ajustar_preco(bigint, smallint, numeric, numeric, public.forma_cobranca) to authenticated;

-- ---------------------------------------------------------------------------
-- Perfil público: cada especialidade leva também a forma de cobrança.
-- ---------------------------------------------------------------------------
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

