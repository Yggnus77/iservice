-- Testes do resumo semanal (migração 20261120004500).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- Equipe: dono e gerente recebem; suporte não.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000009d1', 'dono-res@teste.com', now(), '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000009a1', 'gerente-res@teste.com', now(), '{"nome":"Gerente","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000009e1', 'suporte-res@teste.com', now(), '{"nome":"Suporte","app":"cliente"}');
delete from public.equipe;
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono-res@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000009d1'),
  ('gerente-res@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-0000000009a1'),
  ('suporte-res@teste.com', 'Suporte', 'suporte', '00000000-0000-0000-0000-0000000009e1');

-- Buscas na semana de 09/11 a 15/11/2026: 4 buscas, 1 sem resultado.
insert into public.buscas (profissao_id, resultados, criada_em, lat, lng)
select 'eletricista', r, '2026-11-10 15:00-03'::timestamptz, -15.8, -47.9 from unnest(array[3, 2, 5, 0]) r;

select pg_temp.ok(public.tipo_tem_email('resumo_semanal'), 'resumo semanal tem e-mail');
select pg_temp.ok(public.cfg('metas_piloto') ? 'aceite_min', 'metas do piloto em app_config');

-- Segunda, 16/11/2026: o resumo é da semana de 09/11 a 15/11.
select pg_temp.ok((public.resumo_semanal('2026-11-16') ->> 'inicio') = '2026-11-09', 'semana começa na segunda anterior');
select pg_temp.ok((public.resumo_semanal('2026-11-16') ->> 'fim') = '2026-11-15', 'semana termina no domingo');
select pg_temp.ok((public.resumo_semanal('2026-11-18') ->> 'inicio') = '2026-11-09', 'no meio da semana, continua a semana que acabou');
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{atual,buscas}')::int = 4, 'conta as buscas da semana');
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{atual,buscas_sem_resultado_pct}')::int = 25, 'buscas sem resultado em %');
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{atual,sem_resultado_profissoes,0,nome}') = 'Eletricista', 'lista a profissão sem resultado');
select pg_temp.ok((public.resumo_semanal('2026-11-23') #>> '{atual,buscas}')::int = 0 and (public.resumo_semanal('2026-11-23') #>> '{anterior,buscas}')::int = 4,
  'semana anterior fica ao lado');
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{atual,profissoes_total}')::int = 8, 'oito profissões mais buscadas');

-- Metas por data.
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{metas,aprovados}')::int = 150, 'meta de aprovados até 20/12');
select pg_temp.ok((public.resumo_semanal('2027-01-05') #>> '{metas,aprovados}')::int = 300, 'meta de aprovados até 31/01');
select pg_temp.ok((public.resumo_semanal('2026-11-16') #>> '{metas,concluidos}') is null, 'sem meta de pedidos antes de janeiro');
select pg_temp.ok((public.resumo_semanal('2027-01-11') #>> '{metas,concluidos}')::int = 30, 'meta de 30 pedidos em janeiro');
select pg_temp.ok((public.resumo_semanal('2027-03-08') #>> '{metas,concluidos}')::int = 100, 'meta de 100 pedidos em março');

-- Envio: só dono e gerente.
delete from public.notificacoes where tipo = 'resumo_semanal';
select pg_temp.ok(public.enviar_resumo_semanal() = 2, 'resumo vai para 2 pessoas');
select pg_temp.ok((select count(*) from public.notificacoes where tipo = 'resumo_semanal'
  and usuario_id in ('00000000-0000-0000-0000-0000000009d1', '00000000-0000-0000-0000-0000000009a1')) = 2, 'dono e gerente recebem');
select pg_temp.ok(not exists (select 1 from public.notificacoes where tipo = 'resumo_semanal' and usuario_id = '00000000-0000-0000-0000-0000000009e1'),
  'suporte não recebe');

-- Painel: só quem tem Relatórios.
do $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000009e1', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000009e1', true);
end $$;
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009d1');
set local role authenticated;
do $$ begin
  perform public.admin_resumo_semanal();
  raise exception 'FALHOU: suporte não abre a prévia do resumo';
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  raise notice 'ok - suporte não abre a prévia do resumo';
end $$;
reset role;
do $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000009d1', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000009d1', true);
end $$;
set local role authenticated;
select pg_temp.ok(public.admin_resumo_semanal() ? 'atual', 'dono abre a prévia do resumo');
reset role;

rollback;
