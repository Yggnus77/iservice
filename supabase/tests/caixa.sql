-- Testes da aba Caixa (migração 20261121005100).
-- Rodam numa transação desfeita no fim.
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
create function pg_temp.passa(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise notice 'ok - %', nome;
end $$;
create function pg_temp.admin() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;
grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000008c1', 'cxpro@teste.com', '{"nome":"Rita Pro","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000008c2', 'cxcli@teste.com', '{"nome":"Carlos Cliente Silva","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008c3', 'cxdono@teste.com', '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008c4', 'cxcap@teste.com', '{"nome":"Captador","app":"cliente"}');
update public.perfis set email_verificado = true where id::text like '00000000-0000-0000-0000-0000000008c%';
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000008c3', '00000000-0000-0000-0000-0000000008c4');
delete from public.equipe where papel = 'dono';
insert into public.equipe (email, nome, papel, usuario_id) values
  ('cxdono@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000008c3'),
  ('cxcap@teste.com', 'Captador', 'captacao', '00000000-0000-0000-0000-0000000008c4');

insert into public.equipe (email, nome, papel, usuario_id) values ('cxger@teste.com', 'Gerente', 'gerente', null);

-- Um pedido com a taxa já recebida (serviço concluído) e outro pago esperando o fim do serviço.
create temp table t (n int, pedido uuid);
with a as (insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate, distancia_km, preco_informado)
  values ('00000000-0000-0000-0000-0000000008c2', '00000000-0000-0000-0000-0000000008c1', 'eletricista', 'agora', 'SQS 308',
          public.ponto(-15.81, -47.89), now() + interval '1 hour', 0, 100) returning id)
insert into t select 1, id from a;
with a as (insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate, distancia_km, preco_informado)
  values ('00000000-0000-0000-0000-0000000008c2', '00000000-0000-0000-0000-0000000008c1', 'eletricista', 'agora', 'SQS 309',
          public.ponto(-15.81, -47.89), now() + interval '1 hour', 0, 200) returning id)
insert into t select 2, id from a;
insert into public.pagamentos (pedido_id, status, valor, valor_profissional, valor_plataforma, pago_em, liberado_em)
select pedido, 'liberado', 110, 100, 10, now(), now() from t where n = 1;
insert into public.pagamentos (pedido_id, status, valor, valor_profissional, valor_plataforma, pago_em)
select pedido, 'a_liberar', 220, 200, 20, now() from t where n = 2;

-- Uma assinatura VIP com a mensalidade paga.
update public.perfis set e_cliente = true where id = '00000000-0000-0000-0000-0000000008c2';
insert into public.profissionais (id) values ('00000000-0000-0000-0000-0000000008c1') on conflict do nothing;
update public.profissionais set status = 'aprovado', aprovado_em = now() where id = '00000000-0000-0000-0000-0000000008c1';
with a as (insert into public.assinaturas (profissional_id, plano, valor_mensal) values ('00000000-0000-0000-0000-0000000008c1', 'vip', 49.90) returning id)
insert into public.assinatura_cobrancas (assinatura_id, referencia, status, valor, pago_em, tarifa_asaas)
select id, date_trunc('month', now())::date, 'paga', 49.90, now(), 0.99 from a;

-- O dono vê o Caixa.
select pg_temp.como('00000000-0000-0000-0000-0000000008c3');
create temp table cx as select public.admin_caixa(date_trunc('month', now())::date, now()::date) j;
select pg_temp.ok((select (j #>> '{atual,taxas}')::numeric = 10 from cx), 'taxa recebida entra no caixa');
select pg_temp.ok((select (j #>> '{atual,assinaturas}')::numeric = 49.90 from cx), 'mensalidade entra no caixa');
select pg_temp.ok((select (j #>> '{atual,tarifas}')::numeric = 2.98 from cx), 'tarifa: estimada (1,99) no pedido e real (0,99) na assinatura');
select pg_temp.ok((select (j #>> '{atual,liquido}')::numeric = 56.92 from cx), 'líquido = bruto menos tarifas');
select pg_temp.ok((select (j ->> 'a_receber')::numeric = 20 from cx), 'taxa do pedido ainda não concluído fica em A receber');
select pg_temp.ok((select (j #>> '{cadastros,profissionais_vip}')::int = 1 and (j #>> '{cadastros,profissionais_gratis}')::int = 0 from cx),
  'profissional aprovado com VIP conta como pagante');
select pg_temp.ok((select (j #>> '{clientes,ja_pagaram}')::int = 1 from cx), 'cliente que pagou conta como pagante: ' || (select j ->> 'clientes' from cx));
select pg_temp.ok((select jsonb_array_length(j -> 'por_mes') = 12 from cx), '12 meses de indicadores');
select pg_temp.ok((select (j -> 'por_mes' -> 11 ->> 'pedidos_pagos')::int = 1 and (j -> 'por_mes' -> 11 ->> 'assinantes_novos')::int = 1
  and (j -> 'por_mes' -> 11 ->> 'profissionais_aprovados')::int >= 1 from cx), 'indicadores do mês: resultado e prospecção');
select pg_temp.ok((select jsonb_array_length(j -> 'lancamentos') = 2 from cx), 'lançamentos do período');
select pg_temp.ok((select count(*) = 2 from public.admin_caixa_planilha(date_trunc('month', now())::date, now()::date)), 'planilha do período');
select pg_temp.passa($$select public.admin_caixa_ajustes(5000, 0.99, 0)$$, 'dono muda a meta e a tarifa');
select pg_temp.ok((select (public.admin_caixa(now()::date, now()::date) #>> '{atual,tarifas}')::numeric = 1.98), 'tarifa nova vale na hora');
select pg_temp.falha($$select public.admin_caixa_ajustes(-1, 1, 0)$$, 'meta negativa é recusada');
select pg_temp.falha($$select public.admin_caixa(now()::date, (now() - interval '3 days')::date)$$, 'período invertido é recusado');
select pg_temp.admin();
select pg_temp.ok((select count(*) = 1 from public.admin_acoes where acao = 'caixa_ajustes'), 'ajuste vai para o Registro');

-- O captador não vê; o gerente tem o Caixa por ter tudo.
select pg_temp.como('00000000-0000-0000-0000-0000000008c4');
select pg_temp.falha($$select public.admin_caixa(null, null)$$, 'captador não abre o Caixa');
select pg_temp.ok((select count(*) = 0 from public.assinaturas), 'captador não lê as assinaturas');
select pg_temp.admin();
select pg_temp.ok('caixa' = any (public.cargo_permissoes('gerente')) and not ('caixa' = any (public.cargo_permissoes('responsavel'))), 'Caixa: dono e gerente por padrão');

-- O profissional vê só a própria assinatura.
select pg_temp.como('00000000-0000-0000-0000-0000000008c1');
select pg_temp.ok((select count(*) = 1 from public.assinaturas), 'profissional vê a própria assinatura');
select pg_temp.como('00000000-0000-0000-0000-0000000008c2');
select pg_temp.ok((select count(*) = 0 from public.assinaturas), 'cliente não vê assinaturas');
select pg_temp.admin();

-- Página Comercial: o VIP não aparece; um aprovado sem assinatura aparece com contato e argumento.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000008c5', 'cxpro2@teste.com', '{"nome":"Paulo Sem Plano","app":"profissional"}');
insert into public.profissionais (id) values ('00000000-0000-0000-0000-0000000008c5') on conflict do nothing;
update public.profissionais set status = 'aprovado', aprovado_em = now(), regiao_id = (select id from public.regioes limit 1), disponivel = true
where id = '00000000-0000-0000-0000-0000000008c5';
insert into public.profissional_profissoes (profissional_id, profissao_id, principal) values ('00000000-0000-0000-0000-0000000008c5', 'eletricista', true);
update public.perfis set telefone = '61999990000' where id = '00000000-0000-0000-0000-0000000008c5';
select pg_temp.como('00000000-0000-0000-0000-0000000008c3');
create temp table cm as select public.admin_comercial() j;
select pg_temp.ok((select (j #>> '{resumo,assinantes}')::int = 1 and (j #>> '{resumo,nao_assinantes}')::int = 1 from cm), 'resumo: 1 assinante e 1 não assinante');
select pg_temp.ok((select jsonb_array_length(j -> 'oportunidades') = 1 and j -> 'oportunidades' -> 0 ->> 'nome' = 'Paulo Sem Plano' from cm), 'só quem não assina vira oportunidade');
select pg_temp.ok((select j -> 'oportunidades' -> 0 ->> 'telefone' = '61999990000' and j -> 'oportunidades' -> 0 ->> 'profissoes' = 'Eletricista'
  and j -> 'oportunidades' -> 0 ->> 'prioridade' in ('quente', 'morno', 'frio') and j -> 'oportunidades' -> 0 ->> 'plano_sugerido' in ('vip', 'premium') from cm),
  'oportunidade traz contato, profissão, prioridade e plano sugerido');
select pg_temp.ok((select exists (select 1 from jsonb_array_elements(j -> 'por_profissao') x where x ->> 'id' = 'eletricista' and (x ->> 'nao_assinantes')::int >= 1) from cm),
  'por profissão');
select pg_temp.passa($$select public.admin_comercial_registrar('baixar_lista')$$, 'baixar a lista fica no Registro');
select pg_temp.como('00000000-0000-0000-0000-0000000008c4');
select pg_temp.falha($$select public.admin_comercial()$$, 'captador não abre o Comercial');
select pg_temp.admin();

rollback;
