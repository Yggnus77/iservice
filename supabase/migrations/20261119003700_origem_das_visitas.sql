-- De onde vem cada visita do site (Plano Diretor, tópico 4, 19/11/2026).
-- O site manda a origem da 1ª visita do dia: o código de campanha do link
-- (?utm_source=instagram, panfleto, whatsapp...) ou o site que trouxe a pessoa
-- (google, instagram, facebook...). Continua sem cookies e sem dado pessoal.

alter table public.site_eventos add column if not exists origem text check (origem ~ '^[a-z0-9._-]{1,30}$');
alter table public.site_eventos add column if not exists meio text check (meio ~ '^[a-z0-9._-]{1,30}$');

-- Troca a função por uma com origem e meio (os parâmetros novos são opcionais,
-- então a versão antiga do site, ainda em cache, continua contando).
drop function if exists public.registrar_evento_site(text, text, text, text, text);

create or replace function public.limpar_codigo_site(p text)
returns text
language sql immutable
set search_path = public
as $$ select left(nullif(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9._-]', '', 'g'), ''), 30) $$;
revoke all on function public.limpar_codigo_site(text) from public, anon, authenticated;

create or replace function public.registrar_evento_site(
  p_tipo text, p_visitante text, p_app text default null, p_plataforma text default null, p_pagina text default null,
  p_origem text default null, p_meio text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_tipo not in ('visita', 'baixar') or p_visitante !~ '^[a-z0-9]{8,40}$' then return; end if;
  if p_tipo = 'baixar' and (p_app not in ('cliente', 'profissional') or p_plataforma not in ('android', 'navegador')) then return; end if;
  -- Freio contra robôs: no máximo 20 cliques por código por dia.
  if (select count(*) from public.site_eventos where dia = v_dia and visitante = p_visitante) >= 20 then return; end if;
  insert into public.site_eventos (dia, tipo, app, plataforma, pagina, visitante, origem, meio)
  values (v_dia, p_tipo,
          case when p_tipo = 'baixar' then p_app end,
          case when p_tipo = 'baixar' then p_plataforma end,
          left(nullif(regexp_replace(coalesce(p_pagina, ''), '[^a-z0-9/._-]', '', 'g'), ''), 60),
          p_visitante,
          case when p_tipo = 'visita' then public.limpar_codigo_site(p_origem) end,
          case when p_tipo = 'visita' then public.limpar_codigo_site(p_meio) end)
  on conflict do nothing;
end;
$$;
revoke all on function public.registrar_evento_site(text, text, text, text, text, text, text) from public;
grant execute on function public.registrar_evento_site(text, text, text, text, text, text, text) to anon, authenticated;

-- Painel: o mesmo de antes, mais "origens" (visitas e cliques em Baixar por origem).
create or replace function public.admin_site(p_dias integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_fim date := current_date;
  v_ini date := current_date - (greatest(1, least(coalesce(p_dias, 30), 366)) - 1);
begin
  perform public.exigir_permissao('crescimento');
  return jsonb_build_object(
    'inicio', v_ini,
    'fim', v_fim,
    'dias', coalesce((select jsonb_agg(jsonb_build_object(
        'dia', d::date,
        'visitas', (select count(*) from public.site_eventos where dia = d::date and tipo = 'visita'),
        'baixar_cliente', (select count(distinct visitante) from public.site_eventos where dia = d::date and tipo = 'baixar' and app = 'cliente'),
        'baixar_profissional', (select count(distinct visitante) from public.site_eventos where dia = d::date and tipo = 'baixar' and app = 'profissional'),
        'cadastros_clientes', (select count(*) from public.perfis p where p.criado_em::date = d::date
            and not exists (select 1 from public.profissionais pr where pr.id = p.id)),
        'cadastros_profissionais', (select count(*) from public.profissionais where criado_em::date = d::date)
      ) order by d) from generate_series(v_ini, v_fim, interval '1 day') d), '[]'::jsonb),
    'por_plataforma', coalesce((select jsonb_object_agg(app || '_' || plataforma, n) from (
        select app, plataforma, count(distinct (dia, visitante)) n from public.site_eventos
        where tipo = 'baixar' and dia between v_ini and v_fim group by app, plataforma) s), '{}'::jsonb),
    'paginas', coalesce((select jsonb_agg(jsonb_build_object('pagina', pagina, 'visitas', n) order by n desc) from (
        select coalesce(pagina, '/') pagina, count(*) n from public.site_eventos
        where tipo = 'visita' and dia between v_ini and v_fim group by 1 order by 2 desc limit 10) s), '[]'::jsonb),
    -- A visita guarda a origem; o clique em Baixar herda a origem da visita do mesmo dia.
    'origens', coalesce((select jsonb_agg(jsonb_build_object('origem', origem, 'meio', meio, 'visitas', visitas, 'baixar', baixar)
        order by visitas desc, baixar desc) from (
        select coalesce(v.origem, 'direto') origem, v.meio, count(*) visitas,
               count(*) filter (where exists (select 1 from public.site_eventos b
                 where b.tipo = 'baixar' and b.dia = v.dia and b.visitante = v.visitante)) baixar
        from public.site_eventos v
        where v.tipo = 'visita' and v.dia between v_ini and v_fim
        group by 1, 2 order by 3 desc limit 15) s), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_site(integer) from public, anon;
grant execute on function public.admin_site(integer) to authenticated;
