-- Testes da verificação da conta por e-mail ou SMS (migração 20261118003500).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.admin() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

-- Roda o comando e confere que ele falha com uma mensagem que contém o trecho.
create function pg_temp.falha_com(cmd text, trecho text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise exception 'FALHOU: % (não deu erro)', nome;
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  if position(trecho in sqlerrm) = 0 then raise exception 'FALHOU: % (erro inesperado: %)', nome, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- n = conta nova pelo e-mail (sem verificar), s = conta que verifica pelo SMS,
-- g = conta do Google, d = dono do painel
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'dono@teste.com', null, '{"nome":"Dono","app":"cliente"}', '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'nova@teste.com', now(), '{"nome":"Ana Nova","app":"cliente"}', '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'sms@teste.com', now(), '{"nome":"Bruno SMS","app":"profissional"}', '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'google@teste.com', now(), '{"nome":"Carla Google","app":"cliente"}', '{"provider":"google","providers":["google"]}');

-- Sem "Confirm email", o Supabase já cria a conta com email_confirmed_at: isso não verifica nada.
select pg_temp.ok(not (select email_verificado from public.perfis where id = '00000000-0000-0000-0000-0000000000a1'),
  'conta nova pelo e-mail nasce sem verificar, mesmo com email_confirmed_at');
select pg_temp.ok(not public.conta_verificada('00000000-0000-0000-0000-0000000000a1'), 'conta nova não está verificada');
select pg_temp.ok((select email_verificado and verificado_em is not null from public.perfis where id = '00000000-0000-0000-0000-0000000000c1'),
  'conta do Google já nasce verificada');
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000c1' and tipo = 'boas_vindas'),
  'conta do Google recebe as boas-vindas');

-- Enquanto o "Confirm email" estiver ligado, o link do Supabase também verifica.
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000d1';
select pg_temp.ok((select email_verificado from public.perfis where id = '00000000-0000-0000-0000-0000000000d1'),
  'link de confirmação do Supabase verifica o e-mail');
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000d1';
insert into public.equipe (email, nome, papel, usuario_id) values ('dono@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000000d1')
on conflict (email) do update set papel = 'dono', usuario_id = excluded.usuario_id;

-- ---------------------------------------------------------------- sem verificar não usa
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.falha_com('update public.perfis set email_verificado = true where id = auth.uid()', 'permission denied',
  'a pessoa não marca o e-mail como verificado sozinha');
select pg_temp.admin();
-- A regra do pedido roda numa cópia da tabela (os outros gatilhos de pedidos têm regras próprias).
create temp table pedido_teste (cliente_id uuid);
create trigger exigir before insert on pedido_teste for each row execute function public.exigir_celular_pedido();
select pg_temp.falha_com($$insert into pedido_teste values ('00000000-0000-0000-0000-0000000000a1')$$,
  'Verifique sua conta', 'conta sem verificar não faz pedido');
select pg_temp.falha_com($$select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
  update public.profissionais set disponivel = true where id = '00000000-0000-0000-0000-0000000000b1'$$,
  'Verifique sua conta', 'profissional sem verificar não fica disponível');

-- ---------------------------------------------------------------- código por e-mail
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok(public.pedir_codigo_email() = 'nova@teste.com', 'pedir o código devolve o e-mail da conta');
select pg_temp.falha_com('select public.pedir_codigo_email()', 'Espere um minuto', 'não pede outro código antes de 1 minuto');
select pg_temp.falha_com('select * from public.codigos_email', 'permission denied', 'ninguém lê os códigos pelo app');
select pg_temp.admin();
select pg_temp.ok((select codigo_hash ~ '^[0-9a-f]{64}$' and expira_em > now() from public.codigos_email
  where usuario_id = '00000000-0000-0000-0000-0000000000a1'), 'só o resumo do código fica guardado, com validade');
-- O teste não vê o código enviado: troca por um conhecido.
update public.codigos_email set codigo_hash = public.resumo_codigo(usuario_id, '123456')
where usuario_id = '00000000-0000-0000-0000-0000000000a1';

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok(public.confirmar_codigo_email('654321') = false, 'código errado não confirma');
select pg_temp.ok(not public.conta_verificada('00000000-0000-0000-0000-0000000000a1'), 'depois do erro a conta segue sem verificar');
select pg_temp.ok(public.confirmar_codigo_email('123 456') = true, 'código certo confirma (aceita espaço no meio)');
select pg_temp.ok(public.conta_verificada('00000000-0000-0000-0000-0000000000a1'), 'conta verificada pelo e-mail');
select pg_temp.admin();
select pg_temp.ok((select verificado_em is not null from public.perfis where id = '00000000-0000-0000-0000-0000000000a1'),
  'guarda quando a conta foi verificada');
select pg_temp.ok(not exists (select 1 from public.codigos_email where usuario_id = '00000000-0000-0000-0000-0000000000a1'),
  'código usado é apagado');
select pg_temp.ok((select count(*) from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000a1' and tipo = 'boas_vindas') = 1,
  'boas-vindas saem uma vez quando a conta é verificada');

-- Cinco erros invalidam o código.
update public.perfis set email_verificado = false where id = '00000000-0000-0000-0000-0000000000a1';
insert into public.codigos_email (usuario_id, codigo_hash, email, expira_em, enviado_em)
values ('00000000-0000-0000-0000-0000000000a1', public.resumo_codigo('00000000-0000-0000-0000-0000000000a1', '111111'),
  'nova@teste.com', now() + interval '15 minutes', now() - interval '2 minutes');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select public.confirmar_codigo_email('000000') from generate_series(1, 5);
select pg_temp.falha_com($$select public.confirmar_codigo_email('111111')$$, 'venceu', 'depois de 5 erros o código vence');
select pg_temp.admin();
update public.codigos_email set expira_em = now() - interval '1 second', tentativas = 0 where usuario_id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.falha_com($$select public.confirmar_codigo_email('111111')$$, 'venceu', 'código vencido não confirma');
select pg_temp.admin();
update public.perfis set email_verificado = true where id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select count(*) from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000a1' and tipo = 'boas_vindas') = 1,
  'verificar de novo não repete as boas-vindas');

-- ---------------------------------------------------------------- pelo SMS
select set_config('iservice.confirmando_celular', 'sim', true);
update public.perfis set telefone = '61999990000', telefone_verificado = true where id = '00000000-0000-0000-0000-0000000000b1';
select set_config('iservice.confirmando_celular', '', true);
select pg_temp.ok(public.conta_verificada('00000000-0000-0000-0000-0000000000b1'), 'conta verificada pelo SMS');
insert into pedido_teste values ('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok(true, 'conta verificada faz pedido');
select pg_temp.ok(not (select email_verificado from public.perfis where id = '00000000-0000-0000-0000-0000000000b1'),
  'verificar pelo SMS não marca o e-mail');

-- ---------------------------------------------------------------- equipe do painel
-- Convite para um e-mail que só foi verificado pelo SMS fica pendente.
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok(public.admin_convidar_equipe('sms@teste.com', 'Bruno', 'suporte') = 'convite_pendente',
  'convite para conta verificada só pelo SMS fica pendente');
select pg_temp.admin();
select pg_temp.ok(not (select e_admin from public.perfis where id = '00000000-0000-0000-0000-0000000000b1'),
  'quem não provou o e-mail não entra no painel');
-- Ao verificar o e-mail, entra.
update public.perfis set email_verificado = true where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok((select e_admin from public.perfis where id = '00000000-0000-0000-0000-0000000000b1')
  and (select usuario_id from public.equipe where email = 'sms@teste.com') = '00000000-0000-0000-0000-0000000000b1',
  'ao verificar o e-mail convidado, entra na equipe');

-- Cadastro novo com o e-mail de um convite não entra sem verificar.
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select public.admin_convidar_equipe('convidado@teste.com', 'Convidado', 'suporte');
select pg_temp.admin();
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'convidado@teste.com', now(), '{"nome":"Convidado","app":"cliente"}', '{"provider":"email"}');
select pg_temp.ok(not (select e_admin from public.perfis where id = '00000000-0000-0000-0000-0000000000e1'),
  'cadastro com e-mail convidado não entra no painel antes de verificar o e-mail');
update public.perfis set email_verificado = true where id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.ok((select e_admin from public.perfis where id = '00000000-0000-0000-0000-0000000000e1'),
  'depois de verificar o e-mail, entra no painel');
select pg_temp.ok(not exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000e1' and tipo = 'boas_vindas'),
  'pessoa da equipe não recebe as boas-vindas de cliente');

rollback;
