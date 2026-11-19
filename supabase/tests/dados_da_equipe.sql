-- Testes dos dados de acesso da equipe (migração 20261120004100).
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

create function pg_temp.falha(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise exception 'FALHOU: %', nome;
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  -- Falta de permissão na tabela não conta: o erro tem de vir da regra do cargo.
  if sqlerrm like 'permission denied%' then raise exception 'FALHOU: % (erro inesperado: %)', nome, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.passa(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- d = dono, g = gerente, r = responsável de setor, s = suporte, t = outro suporte, m = marketing, c = cliente
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'dono@teste.com', now(), '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'gerente@teste.com', now(), '{"nome":"Gerente","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'resp@teste.com', now(), '{"nome":"Responsável","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e1', 'suporte@teste.com', now(), '{"nome":"Suporte","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'suporte2@teste.com', now(), '{"nome":"Suporte Dois","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000f1', 'mkt@teste.com', now(), '{"nome":"Marketing","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'cliente@teste.com', now(), '{"nome":"Marina Alves","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'novo@teste.com', now(), '{"nome":"Novo","app":"cliente"}');
-- Conta verificada (e-mail ou SMS) para poder pedir e receber pedidos.
update public.perfis set email_verificado = true where not email_verificado;
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set cpf = '52998224725', nascimento = '1990-05-10' where id = '00000000-0000-0000-0000-0000000000c1';
update public.perfis set e_admin = true
where id in ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000f1');
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000000d1'),
  ('gerente@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-0000000000a1'),
  ('resp@teste.com', 'Responsável', 'responsavel', '00000000-0000-0000-0000-0000000000b1'),
  ('suporte@teste.com', 'Suporte', 'suporte', '00000000-0000-0000-0000-0000000000e1'),
  ('suporte2@teste.com', 'Suporte Dois', 'suporte', '00000000-0000-0000-0000-0000000000e2'),
  ('mkt@teste.com', 'Marketing', 'marketing', '00000000-0000-0000-0000-0000000000f1')
on conflict (email) do update set papel = excluded.papel, usuario_id = excluded.usuario_id;

insert into public.suporte_conversas (assunto, contato_email, status, responsavel) values
  ('Do suporte', 'a@x.com', 'aberto', 'suporte@teste.com');
insert into public.equipe (email, nome, papel) values ('convidada@teste.com', 'Convidada', 'suporte');


-- ---------------------------------------------------------------- ver os dados
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok((select count(*) from public.admin_equipe() where pode_editar) = 7, 'dono edita todos (inclusive a si mesmo)');
select pg_temp.ok((select email_login from public.admin_equipe() where email = 'suporte@teste.com') = 'suporte@teste.com', 'dono vê o e-mail de login');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((select pode_editar from public.admin_equipe() where email = 'dono@teste.com') is false, 'gerente não edita o dono');
select pg_temp.ok((select pode_editar from public.admin_equipe() where email = 'suporte@teste.com'), 'gerente edita o suporte');
select pg_temp.ok((select pode_editar from public.admin_equipe() where email = 'gerente@teste.com'), 'gerente edita os próprios dados');
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.falha($$select public.admin_equipe()$$, 'suporte não abre a lista da equipe');

-- ---------------------------------------------------------------- nome e e-mail
select pg_temp.falha($$select public.admin_editar_membro('suporte2@teste.com', 'Outro Nome', 'suporte2@teste.com')$$, 'suporte não muda dados do colega');
select pg_temp.passa($$select public.admin_editar_membro('suporte@teste.com', 'Suporte Um', 'suporte@teste.com')$$, 'suporte corrige o próprio nome');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.falha($$select public.admin_editar_membro('dono@teste.com', 'Outro Dono', 'dono@teste.com')$$, 'gerente não muda dados do dono');
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.falha($$select public.admin_editar_membro('suporte@teste.com', 'Suporte', 'suporte2@teste.com')$$, 'e-mail de outro da equipe é recusado');
select pg_temp.falha($$select public.admin_editar_membro('suporte@teste.com', 'Suporte', 'cliente@teste.com')$$, 'e-mail de outra conta é recusado');
select pg_temp.falha($$select public.admin_editar_membro('suporte@teste.com', 'S', 'suporte@teste.com')$$, 'nome curto é recusado');
select pg_temp.passa($$select public.admin_editar_membro('suporte@teste.com', 'Ana Suporte', 'ana@teste.com')$$, 'dono troca nome e e-mail do suporte');
select pg_temp.admin();
select pg_temp.ok((select email from auth.users where id = '00000000-0000-0000-0000-0000000000e1') = 'ana@teste.com', 'login passa a ser o e-mail novo');
select pg_temp.ok((select nome from public.perfis where id = '00000000-0000-0000-0000-0000000000e1') = 'Ana Suporte', 'nome do perfil acompanha');
select pg_temp.ok((select responsavel from public.suporte_conversas where assunto = 'Do suporte') = 'ana@teste.com', 'conversas do suporte vão junto com o e-mail');
select pg_temp.ok(exists (select 1 from public.admin_acoes where acao = 'editar_equipe'), 'troca fica no registro');
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.passa($$select public.admin_editar_membro('convidada@teste.com', 'Convidada Certa', 'convidada.certa@teste.com')$$, 'convite pendente: corrige o e-mail do convite');

-- ---------------------------------------------------------------- senha
select pg_temp.falha($$select public.admin_definir_senha_membro('ana@teste.com', 'curta1')$$, 'senha curta é recusada');
select pg_temp.falha($$select public.admin_definir_senha_membro('ana@teste.com', 'somenteletras')$$, 'senha sem número é recusada');
select pg_temp.falha($$select public.admin_definir_senha_membro('convidada.certa@teste.com', 'Senha2026ok')$$, 'convite sem conta: não tem senha para definir');
select pg_temp.passa($$select public.admin_definir_senha_membro('ana@teste.com', 'Senha2026ok')$$, 'dono define senha nova do suporte');
select pg_temp.admin();
select pg_temp.ok((select encrypted_password = extensions.crypt('Senha2026ok', encrypted_password) from auth.users where id = '00000000-0000-0000-0000-0000000000e1'), 'senha gravada criptografada (bcrypt)');
select pg_temp.ok(not exists (select 1 from public.admin_acoes where acao = 'senha_equipe' and dados::text like '%Senha2026ok%'), 'registro nunca guarda a senha');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.falha($$select public.admin_definir_senha_membro('dono@teste.com', 'Senha2026ok')$$, 'gerente não define a senha do dono');
select pg_temp.passa($$select public.admin_definir_senha_membro('gerente@teste.com', 'Minha2026senha')$$, 'gerente define a própria senha');
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.falha($$select public.admin_definir_senha_membro('ana@teste.com', 'Senha2026ok')$$, 'suporte não define senha de colega');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.falha($$select public.admin_equipe()$$, 'cliente não vê a equipe');

rollback;
