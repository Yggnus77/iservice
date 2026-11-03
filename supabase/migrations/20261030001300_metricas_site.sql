-- Visitas ao site e cliques em "Baixar o app" (pedido do usuário em 30/10/2026).
-- Sem cookies e sem dado pessoal: o site manda um código aleatório que muda todo dia,
-- só para contar cada pessoa uma vez por dia. Nada de IP, nome ou aparelho.

create table if not exists public.site_eventos (
  id bigint generated always as identity primary key,
  dia date not null default (now() at time zone 'America/Sao_Paulo')::date,
  criado_em timestamptz not null default now(),
  tipo text not null check (tipo in ('visita', 'baixar')),
  app text check (app in ('cliente', 'profissional')),
  plataforma text check (plataforma in ('android', 'navegador')),
  pagina text check (char_length(pagina) <= 60),
  visitante text not null check (visitante ~ '^[a-z0-9]{8,40}$'),
  check (tipo = 'visita' or (app is not null and plataforma is not null))
);
create unique index if not exists site_eventos_uma_visita_por_dia on public.site_eventos (dia, visitante) where tipo = 'visita';
create index if not exists site_eventos_dia on public.site_eventos (dia);

-- Ninguém lê nem escreve direto: só pela função abaixo e pelo painel.
alter table public.site_eventos enable row level security;
revoke all on public.site_eventos from anon, authenticated;

create or replace function public.registrar_evento_site(
  p_tipo text, p_visitante text, p_app text default null, p_plataforma text default null, p_pagina text default null)
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
  insert into public.site_eventos (dia, tipo, app, plataforma, pagina, visitante)
  values (v_dia, p_tipo,
          case when p_tipo = 'baixar' then p_app end,
          case when p_tipo = 'baixar' then p_plataforma end,
          left(nullif(regexp_replace(coalesce(p_pagina, ''), '[^a-z0-9/._-]', '', 'g'), ''), 60),
          p_visitante)
  on conflict do nothing;
end;
$$;
revoke all on function public.registrar_evento_site(text, text, text, text, text) from public;
grant execute on function public.registrar_evento_site(text, text, text, text, text) to anon, authenticated;

-- Painel: visitas, cliques e cadastros por dia no período.
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
  perform public.exigir_admin();
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
        where tipo = 'visita' and dia between v_ini and v_fim group by 1 order by 2 desc limit 10) s), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_site(integer) from public;
grant execute on function public.admin_site(integer) to authenticated;
