-- Testes dos recebimentos do profissional e da página Pagamentos (migração 20261120004600).
-- Transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.falha(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise exception 'FALHOU: %', nome;
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  raise notice 'ok - %', nome;
end $$;
grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000007a1', 'recpro@teste.com', '{"nome":"Rita Pro","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000007a2', 'reccli@teste.com', '{"nome":"Carlos Cliente Silva","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000007a3', 'recdono@teste.com', '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000007a4', 'reccap@teste.com', '{"nome":"Captador","app":"cliente"}');
update public.perfis set email_verificado = true where id::text like '00000000-0000-0000-0000-0000000007a%';
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000007a3', '00000000-0000-0000-0000-0000000007a4');
delete from public.equipe where papel = 'dono';
insert into public.equipe (email, nome, papel, usuario_id) values
  ('recdono@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000007a3'),
  ('reccap@teste.com', 'Captador', 'captacao', '00000000-0000-0000-0000-0000000007a4');

-- Desligado: a tela mostra "em breve".
select pg_temp.como('00000000-0000-0000-0000-0000000007a1');
select pg_temp.ok((public.meus_recebimentos() ->> 'ativo')::boolean = false, 'pagamento desligado aparece como desligado');
select pg_temp.ok((public.meus_recebimentos() ->> 'taxa_servico_pct')::int = 10, 'taxa de serviço em %');
select pg_temp.ok(public.meus_recebimentos() -> 'conta' = 'null'::jsonb, 'sem conta ainda');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000007a2');
select pg_temp.falha('select public.meus_recebimentos()', 'cliente não abre recebimentos');
reset role;

-- Ligado, com um pedido pago e outro já repassado.
update public.app_config set valor = 'true' where chave in ('pagamento_ativo', 'taxa_servico_ativa');
create temp table t (n int, pedido uuid);
grant all on t to authenticated;
with a as (insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate, distancia_km, preco_informado)
  values ('00000000-0000-0000-0000-0000000007a2', '00000000-0000-0000-0000-0000000007a1', 'eletricista', 'agora', 'SQS 308',
          public.ponto(-15.81, -47.89), now() + interval '1 hour', 0, 100) returning id)
insert into t select 1, id from a;
with a as (insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate, distancia_km, preco_informado)
  values ('00000000-0000-0000-0000-0000000007a2', '00000000-0000-0000-0000-0000000007a1', 'eletricista', 'agora', 'SQS 308',
          public.ponto(-15.81, -47.89), now() + interval '1 hour', 0, 200) returning id)
insert into t select 2, id from a;
insert into public.pagamentos (pedido_id, valor, valor_profissional, valor_plataforma, status, pago_em)
values ((select pedido from t where n = 1), 132, 120, 12, 'pago', now());
insert into public.pagamentos (pedido_id, valor, valor_profissional, valor_plataforma, status, pago_em, liberado_em)
values ((select pedido from t where n = 2), 242, 220, 22, 'liberado', now(), now());
insert into public.contas_recebimento (profissional_id, status, situacao, link_documentos)
values ('00000000-0000-0000-0000-0000000007a1', 'ativa', 'aguardando_ativacao', 'https://exemplo.asaas.com/onboarding');

select pg_temp.como('00000000-0000-0000-0000-0000000007a1');
select pg_temp.ok((public.meus_recebimentos() ->> 'ativo')::boolean, 'pagamento ligado');
select pg_temp.ok((public.meus_recebimentos() ->> 'a_receber')::numeric = 120, 'a receber soma o que já foi pago e não repassado');
select pg_temp.ok((public.meus_recebimentos() ->> 'recebido_mes')::numeric = 220, 'recebido no mês soma os repasses');
select pg_temp.ok(jsonb_array_length(public.meus_recebimentos() -> 'itens') = 2, 'lista os dois repasses');
select pg_temp.ok((public.meus_recebimentos() #>> '{itens,0,cliente}') = 'Carlos', 'mostra só o primeiro nome do cliente');
select pg_temp.ok((public.meus_recebimentos() #>> '{conta,situacao}') = 'aguardando_ativacao'
  and (public.meus_recebimentos() #>> '{conta,link_documentos}') like 'https://%', 'conta mostra a situação e o link dos documentos');
select pg_temp.ok(not exists (select 1 from information_schema.column_privileges
  where table_name = 'contas_recebimento' and column_name = 'asaas_conta_id' and grantee = 'authenticated'), 'id da conta no Asaas não fica visível');
reset role;

-- Chave da subconta no Vault, só pelo service_role.
select public.guardar_chave_subconta('00000000-0000-0000-0000-0000000007a1', 'chave-1');
select public.guardar_chave_subconta('00000000-0000-0000-0000-0000000007a1', 'chave-2');
select pg_temp.ok(public.chave_subconta('00000000-0000-0000-0000-0000000007a1') = 'chave-2', 'guardar de novo troca a chave');
select pg_temp.ok((select count(*) from vault.secrets where name = 'asaas_subconta_00000000-0000-0000-0000-0000000007a1') = 1, 'uma chave por profissional');
select pg_temp.como('00000000-0000-0000-0000-0000000007a1');
select pg_temp.falha($$select public.chave_subconta('00000000-0000-0000-0000-0000000007a1')$$, 'profissional não lê a chave da subconta');
reset role;

-- Painel: quem tem Pedidos vê; Captação não.
select pg_temp.como('00000000-0000-0000-0000-0000000007a3');
select pg_temp.ok((public.admin_pagamentos() #>> '{resumo,guardado}')::numeric = 132, 'painel mostra o valor guardado até concluir');
select pg_temp.ok((public.admin_pagamentos() #>> '{resumo,taxa_mes}')::numeric = 22, 'painel mostra a taxa do mês');
select pg_temp.ok(jsonb_array_length(public.admin_pagamentos('liberado') -> 'itens') = 1, 'filtra por situação');
select pg_temp.ok(jsonb_array_length(public.admin_pagamentos(null, 'Rita') -> 'itens') = 2, 'busca pelo nome do profissional');
select pg_temp.ok((public.admin_pagamentos() #>> '{contas,pendentes}')::int = 1, 'conta pendente de ativação aparece');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000007a4');
select pg_temp.falha('select public.admin_pagamentos()', 'Captação não vê pagamentos');
reset role;

rollback;
