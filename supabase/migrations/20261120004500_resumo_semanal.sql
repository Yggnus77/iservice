-- Indicadores do piloto e resumo semanal por e-mail (Plano Diretor, tópico 9, aprovado em 20/11/2026).
-- Toda segunda às 8h (Brasília) o dono e quem tem o cargo Gerente geral recebem os 8 indicadores
-- da semana que acabou (segunda a domingo), com a semana anterior ao lado e a meta de cada um.
-- As metas ficam em app_config.metas_piloto (editável em Configurações).

insert into public.app_config (chave, valor, descricao) values
  ('metas_piloto', '{
    "aprovados": [{"ate": "2026-12-20", "meta": 150}, {"ate": "2027-01-31", "meta": 300}],
    "profissoes_cobertas": {"profissoes": 8, "minimo": 10},
    "buscas_sem_resultado_max": 10,
    "concluidos_semana": [{"desde": "2027-01-04", "meta": 30}, {"desde": "2027-03-01", "meta": 100}],
    "aceite_min": 80,
    "resposta_max_min": 15,
    "nota_min": 4.7,
    "suporte_no_prazo_min": 90
  }'::jsonb,
  'Metas do piloto usadas no resumo semanal por e-mail (segunda, 8h). Pedidos concluídos: a meta vale a partir da data "desde".')
on conflict (chave) do nothing;

-- Os números de uma semana [p_ini, p_ini + 7 dias).
create or replace function public.indicadores_semana(p_ini date)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_ini timestamptz := p_ini::timestamptz;
  v_fim timestamptz := (p_ini + 7)::timestamptz;
  v_metas jsonb := coalesce(public.cfg('metas_piloto'), '{}'::jsonb);
  v_top integer := coalesce((v_metas #>> '{profissoes_cobertas,profissoes}')::int, 8);
  v_min integer := coalesce((v_metas #>> '{profissoes_cobertas,minimo}')::int, 10);
begin
  return (
    with buscas_semana as (
      select count(*) total, count(*) filter (where resultados = 0) vazias
      from public.buscas where criada_em >= v_ini and criada_em < v_fim
    ), pedidos_semana as (
      select
        count(*) filter (where status = 'concluido' and concluido_em >= v_ini and concluido_em < v_fim) concluidos,
        count(*) filter (where criado_em >= v_ini and criado_em < v_fim and aceito_em is not null) aceitos,
        count(*) filter (where criado_em >= v_ini and criado_em < v_fim and (status <> 'solicitado' or aceito_em is not null)) decididos,
        percentile_cont(0.5) within group (order by extract(epoch from (coalesce(respondido_em, aceito_em) - criado_em)) / 60.0)
          filter (where criado_em >= v_ini and criado_em < v_fim and coalesce(respondido_em, aceito_em) is not null) resposta
      from public.pedidos
      where (criado_em >= v_ini and criado_em < v_fim) or (concluido_em >= v_ini and concluido_em < v_fim)
    ), mais_buscadas as (
      -- As profissões mais buscadas até o fim da semana; sem buscas ainda, as de meta maior na Captação.
      select p.id
      from public.profissoes p
      left join public.captacao_metas m on m.profissao_id = p.id
      where p.ativa
      order by (select count(*) from public.buscas b where b.profissao_id = p.id and b.criada_em < v_fim) desc,
        coalesce(m.meta, 0) desc, p.ordem, p.id
      limit v_top
    ), cobertura as (
      select count(*) filter (where n >= v_min) cobertas
      from (select mb.id, (select count(*) from public.profissional_profissoes pp
              join public.profissionais pr on pr.id = pp.profissional_id
              where pp.profissao_id = mb.id and pr.status = 'aprovado' and pr.aprovado_em < v_fim) n
            from mais_buscadas mb) x
    ), suporte as (
      select count(*) total,
        count(*) filter (where coalesce(resp, now()) <= public.prazo_resposta(gravidade, desde)) no_prazo
      from (
        select c.gravidade, c.criada_em desde, c.primeira_resposta_em resp from public.suporte_conversas c where c.criada_em >= v_ini and c.criada_em < v_fim
        union all
        select r.gravidade, r.criada_em, r.primeira_resposta_em from public.reclamacoes r where r.criada_em >= v_ini and r.criada_em < v_fim
        union all
        select d.gravidade, d.criada_em, d.primeira_resposta_em from public.denuncias d where d.criada_em >= v_ini and d.criada_em < v_fim
        union all
        select 1::smallint, e.criada_em, coalesce(e.contato_em, e.atendida_em) from public.emergencias e where e.criada_em >= v_ini and e.criada_em < v_fim
      ) b
    )
    select jsonb_build_object(
      'inicio', p_ini,
      'aprovados', (select count(*) from public.profissionais where status = 'aprovado' and aprovado_em < v_fim),
      'aprovados_semana', (select count(*) from public.profissionais where aprovado_em >= v_ini and aprovado_em < v_fim),
      'profissoes_cobertas', (select cobertas from cobertura),
      'profissoes_total', v_top,
      'buscas', (select total from buscas_semana),
      'buscas_sem_resultado_pct', (select round(100.0 * vazias / nullif(total, 0)) from buscas_semana),
      'concluidos', (select concluidos from pedidos_semana),
      'aceite_pct', (select round(100.0 * aceitos / nullif(decididos, 0)) from pedidos_semana),
      'resposta_min', (select round(resposta::numeric) from pedidos_semana),
      'nota', (select round(avg(a.nota), 1) from public.avaliacoes a where a.criada_em >= v_ini and a.criada_em < v_fim and not a.oculta),
      'avaliacoes', (select count(*) from public.avaliacoes a where a.criada_em >= v_ini and a.criada_em < v_fim),
      'suporte_no_prazo_pct', (select round(100.0 * no_prazo / nullif(total, 0)) from suporte),
      'suporte_total', (select total from suporte),
      'sem_resultado_profissoes', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'buscas', n) order by n desc, nome)
        from (select p.nome, count(*) n from public.buscas b join public.profissoes p on p.id = b.profissao_id
              where b.criada_em >= v_ini and b.criada_em < v_fim and b.resultados = 0
              group by p.nome order by count(*) desc, p.nome limit 3) t), '[]'::jsonb)
    )
  );
end;
$$;
revoke all on function public.indicadores_semana(date) from public, anon, authenticated;

-- A semana que acabou, a anterior e as metas que valem para ela.
create or replace function public.resumo_semanal(p_hoje date default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_hoje date := coalesce(p_hoje, (now() at time zone 'America/Sao_Paulo')::date);
  v_ini date := date_trunc('week', v_hoje)::date - 7;  -- segunda da semana que acabou
  v_metas jsonb := coalesce(public.cfg('metas_piloto'), '{}'::jsonb);
  v_meta_aprov jsonb;
  v_meta_concl integer;
begin
  select x into v_meta_aprov from jsonb_array_elements(coalesce(v_metas -> 'aprovados', '[]')) x
  where (x ->> 'ate')::date >= v_ini + 6 order by (x ->> 'ate')::date limit 1;
  select (x ->> 'meta')::int into v_meta_concl from jsonb_array_elements(coalesce(v_metas -> 'concluidos_semana', '[]')) x
  where (x ->> 'desde')::date <= v_ini + 6 order by (x ->> 'desde')::date desc limit 1;
  return jsonb_build_object(
    'inicio', v_ini, 'fim', v_ini + 6,
    'atual', public.indicadores_semana(v_ini),
    'anterior', public.indicadores_semana(v_ini - 7),
    'metas', jsonb_build_object(
      'aprovados', v_meta_aprov -> 'meta', 'aprovados_ate', v_meta_aprov -> 'ate',
      'profissoes_minimo', v_metas #> '{profissoes_cobertas,minimo}',
      'buscas_sem_resultado_max', v_metas -> 'buscas_sem_resultado_max',
      'concluidos', v_meta_concl,
      'aceite_min', v_metas -> 'aceite_min',
      'resposta_max_min', v_metas -> 'resposta_max_min',
      'nota_min', v_metas -> 'nota_min',
      'suporte_no_prazo_min', v_metas -> 'suporte_no_prazo_min'));
end;
$$;
revoke all on function public.resumo_semanal(date) from public, anon, authenticated;

-- Para o painel (prévia do e-mail): quem tem Relatórios.
create or replace function public.admin_resumo_semanal()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('relatorios');
  return public.resumo_semanal();
end;
$$;
revoke all on function public.admin_resumo_semanal() from public, anon;
grant execute on function public.admin_resumo_semanal() to authenticated;

-- Manda o resumo (notificação + e-mail) para o dono e os gerentes gerais.
create or replace function public.enviar_resumo_semanal()
returns integer
language plpgsql security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_dados jsonb := public.resumo_semanal();
  v_a jsonb := v_dados -> 'atual';
  v_n integer := 0;
  m record;
begin
  for m in
    select distinct e.usuario_id from public.equipe e
    where e.papel in ('dono', 'gerente') and e.usuario_id is not null
  loop
    perform public.notificar(m.usuario_id, 'resumo_semanal', 'Resumo da semana no iService',
      format('%s profissionais aprovados, %s pedidos concluídos na semana.',
        coalesce(v_a ->> 'aprovados', '0'), coalesce(v_a ->> 'concluidos', '0')),
      v_dados);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke all on function public.enviar_resumo_semanal() from public, anon, authenticated;

-- O resumo também vai por e-mail.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.tipo_tem_email(text)'::regprocedure) into v_def;
  if position('resumo_semanal' in v_def) = 0 then
    if position('''emergencia_equipe''' in v_def) = 0 then
      raise exception 'tipo_tem_email mudou: confira antes de aplicar';
    end if;
    execute replace(v_def, '''emergencia_equipe''', '''emergencia_equipe'', ''resumo_semanal''');
  end if;
end $$;

-- Segunda, 11h UTC = 8h em Brasília.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'iservice-resumo-semanal';
    perform cron.schedule('iservice-resumo-semanal', '0 11 * * 1', 'select public.enviar_resumo_semanal()');
  end if;
end;
$$;
