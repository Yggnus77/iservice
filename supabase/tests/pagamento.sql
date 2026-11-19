-- Testes do deslocamento, da taxa de serviço e do pagamento pelo app
-- (migrações 20261120003800 e 20261120003900). Transação desfeita no fim.
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
grant execute on all functions in schema pg_temp to authenticated;

-- ------------------------------------------------------------ deslocamento
select pg_temp.ok(public.valor_deslocamento(20) = 50, 'deslocamento de 20 km = R$ 50');
select pg_temp.ok(public.valor_deslocamento(0) = 20, 'deslocamento mínimo = R$ 20');
select pg_temp.ok(public.valor_deslocamento(6.3) = 29, 'deslocamento arredonda a R$ 1');
select pg_temp.ok(public.valor_deslocamento(null) = 0, 'sem distância, sem deslocamento');
select pg_temp.ok(public.valor_taxa_servico(150) = 0, 'taxa de serviço desligada não cobra');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'pagpro@teste.com', '{"nome":"Paula Pro","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000d2', 'pagcli@teste.com', '{"nome":"Caio Cliente","app":"cliente"}');
update public.perfis set email_verificado = true where id in ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d2');

create temp table t (pedido uuid);
grant all on t to authenticated;
with x as (
  insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate, distancia_km, preco_informado)
  values ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000d1', 'eletricista', 'agora', 'SQS 308',
          public.ponto(-15.81, -47.89), now() + interval '1 hour', 20, 100)
  returning id)
insert into t select id from x;
select pg_temp.ok((select deslocamento = 50 and taxa_servico = 0 from public.pedidos where id = (select pedido from t)),
  'pedido grava R$ 50 de deslocamento para 20 km e nenhuma taxa de serviço com ela desligada');

update public.app_config set valor = 'true' where chave = 'taxa_servico_ativa';
select pg_temp.ok(public.valor_taxa_servico(150) = 15, 'taxa de serviço ligada: 10% de R$ 150 = R$ 15');
update public.pedidos set preco_informado = 120 where id = (select pedido from t);
select pg_temp.ok((select taxa_servico = round((120 + 50 + taxa_urgencia + taxa_fora_horario) * 0.1, 2) from public.pedidos where id = (select pedido from t)),
  'taxa de serviço é 10% do preço com deslocamento e acréscimos');

-- O profissional não vê a taxa de serviço na lista dele; o cliente vê.
select pg_temp.como('00000000-0000-0000-0000-0000000000d2');
select pg_temp.ok((select deslocamento = 50 and taxa_servico > 0 from public.meus_pedidos('cliente') limit 1), 'cliente vê deslocamento e taxa de serviço');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok((select taxa_servico = 0 from public.meus_pedidos('profissional') limit 1), 'profissional não recebe a taxa de serviço na lista');
reset role;

-- ------------------------------------------------------------ pagamento desligado
update public.pedidos set status = 'aceito' where id = (select pedido from t);
select pg_temp.ok(not exists (select 1 from public.pagamentos), 'com o pagamento desligado, aceitar não cria cobrança');
update public.pedidos set status = 'a_caminho' where id = (select pedido from t);
select pg_temp.ok(true, 'com o pagamento desligado, o profissional sai sem pagamento');

-- ------------------------------------------------------------ pagamento ligado
update public.app_config set valor = 'true' where chave = 'pagamento_ativo';
update public.pedidos set status = 'aceito' where id = (select pedido from t);
select pg_temp.ok((select g.status = 'criando' and g.tipo = 'principal' and g.valor = g.valor_profissional + g.valor_plataforma
    and g.valor_profissional = 120 + 50 + p.taxa_urgencia + p.taxa_fora_horario and g.valor_plataforma = p.taxa_servico
  from public.pagamentos g join public.pedidos p on p.id = g.pedido_id), 'aceite cria a cobrança: profissional recebe preço + deslocamento, iService fica com a taxa');
do $$ begin
  update public.pedidos set status = 'a_caminho' where id = (select pedido from t);
  raise exception 'FALHOU: saiu sem pagamento';
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  if sqlerrm not like '%ainda não pagou%' then raise exception 'FALHOU: mensagem errada: %', sqlerrm; end if;
  raise notice 'ok - sem pagamento confirmado o profissional não sai para o atendimento';
end $$;
update public.pagamentos set status = 'pago' where pedido_id = (select pedido from t);
update public.pedidos set status = 'a_caminho' where id = (select pedido from t);
select pg_temp.ok((select status = 'a_caminho' from public.pedidos where id = (select pedido from t)), 'com o pagamento confirmado, ele sai');

-- Quem vê a cobrança: só as partes do pedido.
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000d3', 'outro@teste.com', '{"nome":"Outro","app":"cliente"}');
select pg_temp.como('00000000-0000-0000-0000-0000000000d3');
select pg_temp.ok(not exists (select 1 from public.pagamentos), 'outra pessoa não vê a cobrança');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000d2');
select pg_temp.ok(exists (select 1 from public.pagamentos), 'o cliente vê a cobrança dele');
do $$ begin
  update public.pagamentos set status = 'pago';
  if exists (select 1 from public.pagamentos where status <> 'pago') then null; end if;
  raise exception 'FALHOU: cliente alterou a cobrança';
exception when insufficient_privilege then raise notice 'ok - cliente não altera a cobrança';
end $$;
reset role;

-- Contatos escondidos em todo texto (sempre ligado).
insert into public.mensagens (pedido_id, autor_id, texto) values
  ((select pedido from t), '00000000-0000-0000-0000-0000000000d2', 'me chama no zap 61 98123-4567 ou joao@gmail.com, pago no pix');
select pg_temp.ok((select texto not like '%98123%' and texto not like '%gmail%' and texto not ilike '%pix%' and texto not ilike '%zap%'
  from public.mensagens order by id desc limit 1), 'chat esconde telefone, e-mail, Pix e WhatsApp');
update public.profissionais set bio = 'Atendo rápido. Insta @paulapro, site paulapro.com.br, CPF 123.456.789-09' where id = '00000000-0000-0000-0000-0000000000d1';
select pg_temp.ok((select bio not like '%paulapro%' and bio not like '%123.456%' and bio like 'Atendo rápido.%' from public.profissionais
  where id = '00000000-0000-0000-0000-0000000000d1'), 'bio do profissional esconde @, site e números');
update public.pedidos set descricao = 'Liga no (61) 3333-4444 quando chegar' where id = (select pedido from t);
select pg_temp.ok((select descricao not like '%3333%' from public.pedidos where id = (select pedido from t)), 'descrição do pedido esconde telefone');
update public.perfis set nome = 'Caio 61981234567' where id = '00000000-0000-0000-0000-0000000000d2';
select pg_temp.ok((select nome not like '%9812%' from public.perfis where id = '00000000-0000-0000-0000-0000000000d2'), 'nome não carrega telefone');
select pg_temp.ok(public.ocultar_contatos('Chego às 14:30, fica R$ 1.500,00 no bloco C 308') = 'Chego às 14:30, fica R$ 1.500,00 no bloco C 308',
  'hora, preço e endereço continuam no chat');

-- O ciclo de 15 minutos cria as contas de recebimento que faltam.
update public.profissionais set status = 'aprovado' where id = '00000000-0000-0000-0000-0000000000d1';
select public.processar_pagamentos();
select pg_temp.ok(exists (select 1 from public.contas_recebimento where profissional_id = '00000000-0000-0000-0000-0000000000d1'),
  'profissional aprovado entra na fila da conta de recebimento');

rollback;
