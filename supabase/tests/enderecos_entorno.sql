-- Testes dos endereços do Entorno (migração 20261116003100). Transação desfeita no fim.
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

-- ------------------------------------------------------------ lista de regiões
select pg_temp.ok((select count(*) from public.regioes) = 49, 'lista tem 37 lugares do DF e 12 cidades do Entorno');
select pg_temp.ok((select count(*) from public.regioes where uf = 'GO') = 12, 'Entorno tem 12 cidades de Goiás');
select pg_temp.ok((select bool_and(faixa_preco = 5) from public.regioes where uf = 'GO'), 'cidades de Goiás ficam na faixa do Entorno');
select pg_temp.ok(not exists (select 1 from public.regioes where centro is null), 'toda região tem centro no mapa');
select pg_temp.ok((select array_agg(id order by ordem) from (select * from public.regioes order by ordem limit 3) x) = array['agua-quente', 'aguas-claras', 'arapoanga'],
  'lista começa em ordem alfabética pelo DF');
select pg_temp.ok((select uf from public.regioes order by ordem desc limit 1) = 'GO', 'cidades de Goiás vêm depois do DF');
select pg_temp.ok(public.regiao_proxima(-16.77, -47.61) = 'cristalina', 'ponto em Cristalina cai em Cristalina');
select pg_temp.ok(public.regiao_proxima(-15.80, -48.14) = 'sol-nascente', 'ponto no Sol Nascente cai no Sol Nascente');

-- ---------------------------------------------------------------- bairro
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'entorno@teste.com', '{"nome":"Morador do Entorno","app":"cliente"}');
-- Conta verificada (e-mail ou SMS) para poder pedir e receber pedidos.
update public.perfis set email_verificado = true where not email_verificado;
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');

do $$ begin
  perform public.salvar_endereco('Rua 10 Qd 5', -16.12, -47.98, 'luziania', 'Lt 3', null, null, null, '72800000', 'Luziânia', 'GO');
  raise exception 'FALHOU: aceitou endereço de Goiás sem bairro';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - endereço novo em Goiás pede o bairro';
end $$;

select public.salvar_endereco('Rua 10 Qd 5', -16.12, -47.98, 'luziania', 'Lt 3', null, null, 'Perto da feira', '72800-000',
  'Luziânia', 'GO', 'Casa', true, null, '  Jardim Ingá ');
select pg_temp.ok((public.meu_perfil() -> 'enderecos' -> 0 ->> 'bairro') = 'Jardim Ingá', 'bairro volta no perfil, sem espaços sobrando');
select pg_temp.ok((select cep = '72800000' and uf = 'GO' and cidade = 'Luziânia' from public.enderecos where usuario_id = auth.uid()),
  'CEP de Goiás aceito e cidade gravada');

-- Endereço antigo sem bairro continua podendo ser alterado (por exemplo, virar o principal).
reset role;
update public.enderecos set bairro = null where usuario_id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select public.salvar_endereco('Rua 10 Qd 5', -16.12, -47.98, 'luziania', 'Lt 3', null, null, null, null, 'Luziânia', 'GO', 'Casa', true,
  (select id from public.enderecos where usuario_id = auth.uid()));
select pg_temp.ok(true, 'endereço antigo sem bairro ainda pode ser salvo de novo');

select public.salvar_endereco('SQS 308', -15.815, -47.896, 'asa-sul', 'Bloco C', null, 'Apto 101', null, null, 'Brasília', 'DF', 'Trabalho', false);
select pg_temp.ok((select bairro is null from public.enderecos where usuario_id = auth.uid() and regiao_id = 'asa-sul'),
  'no DF o bairro é opcional (chamada antiga, sem bairro)');

reset role;
rollback;
