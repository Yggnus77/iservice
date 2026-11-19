-- Captação de profissionais (Plano Diretor, tópico 3, 19/11/2026).
-- Metas por profissão e a página "Captação" do painel: funil, semanas,
-- profissões contra a meta e quem trouxe mais profissionais (código de indicação).

create table if not exists public.captacao_metas (
  profissao_id text primary key references public.profissoes (id) on delete cascade,
  meta integer not null check (meta between 0 and 1000),
  atualizada_em timestamptz not null default now()
);
alter table public.captacao_metas enable row level security;
revoke all on public.captacao_metas from anon, authenticated;

-- Metas até 20/12/2026 (critério do lançamento suave: 150 aprovados).
insert into public.captacao_metas (profissao_id, meta)
select p.id, m.meta
from (values
  ('faxineira', 12), ('eletricista', 12), ('encanador', 12), ('marido', 12), ('pintor', 12), ('pedreiro', 12), ('ar', 12), ('montador', 12),
  ('chaveiro', 6), ('jardinagem', 6), ('fretes', 6), ('dedetizador', 6), ('estofados', 6), ('maquiadora', 6), ('barbeiro', 6), ('baba', 6),
  ('chaveiro-auto', 3), ('borracheiro', 3), ('pets', 3), ('promotor', 3)
) as m (profissao_id, meta)
join public.profissoes p on p.id = m.profissao_id
on conflict (profissao_id) do nothing;

create or replace function public.admin_captacao()
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_inicio date := date '2026-11-23';  -- segunda-feira da 1ª semana do plano
begin
  perform public.exigir_permissao('crescimento');
  return jsonb_build_object(
    'meta_total', 150,
    'meta_data', date '2026-12-20',
    'funil', (select jsonb_build_object(
        'contas', count(*),
        'rascunho', count(*) filter (where status = 'rascunho'),
        'em_analise', count(*) filter (where status = 'em_analise'),
        'aprovado', count(*) filter (where status = 'aprovado'),
        'recusado', count(*) filter (where status = 'recusado'),
        'suspenso', count(*) filter (where status = 'suspenso'),
        'indicados', count(*) filter (where exists (select 1 from public.indicacoes i where i.indicado_id = pr.id)))
      from public.profissionais pr),
    'semanas', coalesce((select jsonb_agg(jsonb_build_object(
        'inicio', s::date,
        'cadastros', (select count(*) from public.profissionais where criado_em >= s and criado_em < s + interval '7 days'),
        'aprovados', (select count(*) from public.profissionais where aprovado_em >= s and aprovado_em < s + interval '7 days'),
        'acumulado', (select count(*) from public.profissionais where status = 'aprovado' and aprovado_em < s + interval '7 days')
      ) order by s) from generate_series(v_inicio::timestamptz, greatest(now(), v_inicio::timestamptz), interval '7 days') s), '[]'::jsonb),
    'profissoes', coalesce((select jsonb_agg(x order by (x ->> 'meta')::int desc, x ->> 'nome') from (
        select jsonb_build_object(
          'id', p.id, 'nome', p.nome,
          'meta', coalesce(m.meta, 0),
          'aprovados', count(pr.id) filter (where pr.status = 'aprovado'),
          'em_analise', count(pr.id) filter (where pr.status = 'em_analise'),
          'rascunho', count(pr.id) filter (where pr.status = 'rascunho')) x
        from public.profissoes p
        left join public.captacao_metas m on m.profissao_id = p.id
        left join public.profissional_profissoes pp on pp.profissao_id = p.id
        left join public.profissionais pr on pr.id = pp.profissional_id
        where p.ativa
        group by p.id, p.nome, m.meta) t), '[]'::jsonb),
    'indicadores', coalesce((select jsonb_agg(x order by (x ->> 'aprovados')::int desc, (x ->> 'indicados')::int desc) from (
        select jsonb_build_object(
          'id', ind.id, 'nome', ind.nome, 'codigo', ind.codigo_indicacao,
          'indicados', count(*),
          'aprovados', count(*) filter (where pr.status = 'aprovado')) x
        from public.indicacoes i
        join public.profissionais pr on pr.id = i.indicado_id
        join public.perfis ind on ind.id = i.indicador_id
        group by ind.id, ind.nome, ind.codigo_indicacao
        limit 50) t), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_captacao() from public;
grant execute on function public.admin_captacao() to authenticated;
