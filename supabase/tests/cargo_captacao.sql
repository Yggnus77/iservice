-- Testes do cargo Captação (migração 20261120004400).
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
  if sqlerrm like 'permission denied%' then raise exception 'FALHOU: % (erro inesperado: %)', nome, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.passa(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- d = dono, a = gerente, k = captador já cadastrado, j = captador convidado depois, m = marketing
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000008d1', 'dono-cap@teste.com', now(), '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008a1', 'gerente-cap@teste.com', now(), '{"nome":"Gerente","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008b1', 'captador@teste.com', now(), '{"nome":"Captador","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008b2', 'captador2@teste.com', now(), '{"nome":"Captador Dois","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000008f1', 'mkt-cap@teste.com', now(), '{"nome":"Marketing","app":"cliente"}');
update public.perfis p set email = u.email, email_verificado = true from auth.users u where u.id = p.id and u.email like '%cap%@teste.com';
update public.perfis set e_admin = true
where id in ('00000000-0000-0000-0000-0000000008d1', '00000000-0000-0000-0000-0000000008a1', '00000000-0000-0000-0000-0000000008f1');
delete from public.equipe where papel = 'dono';
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono-cap@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000008d1'),
  ('gerente-cap@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-0000000008a1'),
  ('mkt-cap@teste.com', 'Marketing', 'marketing', '00000000-0000-0000-0000-0000000008f1');

-- O gerente convida o captador com o cargo novo.
select pg_temp.como('00000000-0000-0000-0000-0000000008a1');
select pg_temp.ok(public.admin_convidar_equipe('captador@teste.com', 'Captador', 'captacao') = 'ativo', 'gerente convida alguém como Captação');
select pg_temp.admin();
select pg_temp.ok((select papel = 'captacao' and not recebe_emails from public.equipe where email = 'captador@teste.com'),
  'captador entra fora do rodízio de e-mails');
select pg_temp.ok((select e_admin from public.perfis where id = '00000000-0000-0000-0000-0000000008b1'), 'captador ganha acesso ao painel');
select pg_temp.ok(public.cargo_nome('captacao') = 'Captação', 'nome do cargo');

-- O que o captador vê.
select pg_temp.como('00000000-0000-0000-0000-0000000008b1');
select pg_temp.ok((public.admin_meu_acesso() ->> 'cargo') = 'captacao', 'painel recebe o cargo Captação');
select pg_temp.ok(public.pode('captacao') and public.pode('inicio'), 'captador abre Início e Captação');
select pg_temp.ok(not public.pode('crescimento') and not public.pode('comunicados') and not public.pode('pessoas')
  and not public.pode('dados_pessoais') and not public.pode('emails') and not public.pode('cadastros_decidir'),
  'captador não vê dados pessoais, e-mails, comunicados nem aprova cadastros');
select pg_temp.passa('select public.admin_captacao()', 'captador abre a página Captação');
select pg_temp.falha('select public.admin_atendimento()', 'captador não vê a lista de plantão');
select pg_temp.falha($$select public.admin_convidar_equipe('x@teste.com', 'X', 'suporte')$$, 'captador não convida ninguém');
select pg_temp.admin();

-- Marketing continua vendo Captação; o dono e o gerente também.
select pg_temp.como('00000000-0000-0000-0000-0000000008f1');
select pg_temp.passa('select public.admin_captacao()', 'Marketing continua abrindo Captação');
select pg_temp.falha('select public.admin_atendimento()', 'Marketing não vê a lista de plantão');
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000008d1');
select pg_temp.passa('select public.admin_captacao()', 'dono abre Captação');
select pg_temp.passa('select public.admin_atendimento()', 'dono abre Horário, plantão e prazos');

-- Mudar de cargo: o dono passa o Marketing para Captação e volta.
select pg_temp.passa($$select public.admin_mudar_cargo('mkt-cap@teste.com', 'captacao')$$, 'dono muda Marketing para Captação');
select pg_temp.admin();
select pg_temp.ok((select papel = 'captacao' and not recebe_emails from public.equipe where email = 'mkt-cap@teste.com'),
  'quem vira Captação fica fora do rodízio');
select pg_temp.como('00000000-0000-0000-0000-0000000008d1');
select pg_temp.falha($$select public.admin_suporte_rodizio('captador@teste.com', true)$$, 'captador não entra no rodízio de e-mails');
select pg_temp.ok(not exists (select 1 from public.admin_suporte_equipe() x where x.email in ('captador@teste.com', 'mkt-cap@teste.com')),
  'Captação não aparece para receber conversas');
-- Convite pendente (sem conta ainda) também funciona.
select pg_temp.ok(public.admin_convidar_equipe('captador-novo@teste.com', 'Captador Novo', 'captacao') = 'convite_pendente',
  'convite pendente como Captação');
select pg_temp.admin();
select pg_temp.falha($$insert into public.equipe (email, nome, papel) values ('y@teste.com', 'Y', 'vendedor')$$, 'cargo fora da lista é recusado');

rollback;
