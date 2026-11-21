-- Testes das permissões por cargo e por pessoa (migração 20261121005000).
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

-- d = dono, g = gerente, h = outro gerente, r = responsável, s = suporte, m = marketing
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000ad1', 'dono-perm@teste.com', now(), '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-000000000aa1', 'gerente-perm@teste.com', now(), '{"nome":"Gerente","app":"cliente"}'),
  ('00000000-0000-0000-0000-000000000aa2', 'gerente2-perm@teste.com', now(), '{"nome":"Gerente Dois","app":"cliente"}'),
  ('00000000-0000-0000-0000-000000000ab1', 'resp-perm@teste.com', now(), '{"nome":"Responsável","app":"cliente"}'),
  ('00000000-0000-0000-0000-000000000ae1', 'sup-perm@teste.com', now(), '{"nome":"Suporte","app":"cliente"}'),
  ('00000000-0000-0000-0000-000000000af1', 'mkt-perm@teste.com', now(), '{"nome":"Marketing","app":"cliente"}');
update public.perfis p set email = u.email, email_verificado = true, e_admin = true
from auth.users u where u.id = p.id and u.email like '%-perm@teste.com';
delete from public.equipe where papel = 'dono';
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono-perm@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-000000000ad1'),
  ('gerente-perm@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-000000000aa1'),
  ('gerente2-perm@teste.com', 'Gerente Dois', 'gerente', '00000000-0000-0000-0000-000000000aa2'),
  ('resp-perm@teste.com', 'Responsável', 'responsavel', '00000000-0000-0000-0000-000000000ab1'),
  ('sup-perm@teste.com', 'Suporte', 'suporte', '00000000-0000-0000-0000-000000000ae1'),
  ('mkt-perm@teste.com', 'Marketing', 'marketing', '00000000-0000-0000-0000-000000000af1');

-- ---------------------------------------------------------------- gerente = dono
select pg_temp.como('00000000-0000-0000-0000-000000000aa1');
select pg_temp.ok((select array_length(public.minhas_permissoes(), 1)) = (select count(*) from public.permissoes_catalogo()),
  'gerente geral tem todas as permissões, como o dono');
select pg_temp.passa($$select public.admin_cargos()$$, 'gerente abre a tela Cargos');
select pg_temp.ok((select (c ->> 'pode_editar')::boolean from jsonb_array_elements(public.admin_cargos() -> 'cargos') c where c ->> 'cargo' = 'dono') is false,
  'cargo Dono aparece travado');
select pg_temp.falha($$select public.admin_salvar_cargo('dono', array['inicio'])$$, 'ninguém mexe no cargo Dono');
select pg_temp.falha($$select public.admin_salvar_permissoes_membro('dono-perm@teste.com', array['inicio'])$$, 'gerente não mexe nas permissões do dono');
select pg_temp.falha($$select public.admin_remover_equipe('dono-perm@teste.com')$$, 'gerente não remove o dono');
select pg_temp.falha($$select public.admin_mudar_cargo('dono-perm@teste.com', 'gerente')$$, 'gerente não rebaixa o dono');
select pg_temp.falha($$select public.admin_suspender('00000000-0000-0000-0000-000000000ad1', true, 'x')$$, 'gerente não suspende o dono');
select pg_temp.falha($$select public.admin_transferir_dono('gerente-perm@teste.com')$$, 'gerente não pega a posição de dono');
select pg_temp.ok((select pode_permissoes from public.admin_equipe() where email = 'gerente2-perm@teste.com'), 'gerente mexe nas permissões de outro gerente');
select pg_temp.ok((select not pode_permissoes from public.admin_equipe() where email = 'gerente-perm@teste.com'), 'ninguém vê o botão Permissões em si mesmo');
select pg_temp.falha($$select public.admin_salvar_permissoes_membro('gerente-perm@teste.com', array['inicio'])$$, 'ninguém muda as próprias permissões');

-- ---------------------------------------------------------------- tela Cargos
select pg_temp.passa($$select public.admin_salvar_cargo('suporte', array['inicio', 'emails', 'pedidos', 'relatorios'])$$, 'gerente muda o cargo Suporte');
select pg_temp.como('00000000-0000-0000-0000-000000000ae1');
select pg_temp.ok(public.pode('relatorios') and not public.pode('cadastros') and not public.pode('emergencias'),
  'a mudança vale para todos do cargo Suporte');
select pg_temp.passa($$select public.admin_relatorio(current_date - 7, current_date)$$, 'suporte abre Relatórios depois da mudança');
select pg_temp.falha($$select * from public.admin_emergencias()$$, 'suporte perde Emergências no banco');
select pg_temp.falha($$select public.admin_cargos()$$, 'suporte não abre a tela Cargos');
select pg_temp.falha($$select public.admin_salvar_cargo('suporte', array['inicio', 'configuracoes'])$$, 'suporte não muda o próprio cargo');
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.admin_acoes where acao = 'editar_cargo' and alvo = 'suporte'
  and dados -> 'ligou' ? 'relatorios' and dados -> 'desligou' ? 'emergencias') = 1, 'mudança do cargo vai para o Registro com o que ligou e desligou');

select pg_temp.como('00000000-0000-0000-0000-000000000ad1');
select pg_temp.passa($$select public.admin_salvar_cargo('suporte', null)$$, 'dono volta o Suporte ao padrão');
select pg_temp.ok(public.cargo_permissoes('suporte') = public.cargo_permissoes_padrao('suporte'), 'padrão restaurado');
select pg_temp.passa($$select public.admin_salvar_cargo('marketing', array['captacao'])$$, 'tirar tudo deixa o Início');
select pg_temp.ok(public.cargo_permissoes('marketing') = array['inicio', 'captacao'], 'Início fica sempre ligado');
select pg_temp.falha($$select public.admin_salvar_cargo('marketing', array['inicio', 'nao_existe'])$$, 'permissão desconhecida é recusada');
select pg_temp.passa($$select public.admin_salvar_cargo('gerente', array['inicio', 'pedidos', 'equipe', 'cargos'])$$, 'dono limita o cargo Gerente');
select pg_temp.como('00000000-0000-0000-0000-000000000aa1');
select pg_temp.ok(not public.pode('configuracoes') and public.pode('cargos'), 'o limite do dono vale para o gerente');
select pg_temp.falha($$select public.admin_salvar_cargo('gerente', array['inicio', 'pedidos', 'equipe', 'cargos', 'configuracoes'])$$,
  'gerente limitado não se dá Configurações de volta');
select pg_temp.falha($$select public.admin_salvar_cargo('gerente', array['inicio', 'pedidos', 'equipe'])$$, 'ninguém tira Cargos do próprio cargo');
select pg_temp.como('00000000-0000-0000-0000-000000000ad1');
select pg_temp.passa($$select public.admin_salvar_cargo('gerente', null)$$, 'dono devolve tudo ao gerente');
select pg_temp.passa($$select public.admin_salvar_cargo('marketing', null)$$, 'Marketing volta ao padrão');

-- ---------------------------------------------------------------- permissões por pessoa
select pg_temp.como('00000000-0000-0000-0000-000000000aa1');
select pg_temp.passa($$select public.admin_salvar_permissoes_membro('sup-perm@teste.com',
  (select array_agg(c) from unnest(public.cargo_permissoes('suporte') || array['dados_pessoais']) c where c <> 'emergencias'))$$,
  'gerente dá Dados pessoais e tira Emergências de uma pessoa do Suporte');
select pg_temp.ok((select permissoes_proprias = 2 from public.admin_equipe() where email = 'sup-perm@teste.com'), 'Equipe mostra 2 exceções');
select pg_temp.ok((select (public.admin_permissoes_membro('sup-perm@teste.com') -> 'excecoes') @> '[{"permissao":"dados_pessoais","ligada":true},{"permissao":"emergencias","ligada":false}]'),
  'exceções guardadas como ligada e desligada');
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.admin_acoes where acao = 'permissoes_equipe'
  and dados ->> 'email' = 'sup-perm@teste.com' and dados -> 'ligou' ? 'dados_pessoais') = 1, 'mudança da pessoa vai para o Registro');
select pg_temp.como('00000000-0000-0000-0000-000000000ae1');
select pg_temp.ok(public.pode('dados_pessoais') and not public.pode('emergencias'), 'a pessoa ganha e perde o acesso');
select pg_temp.ok((public.admin_meu_acesso() ->> 'personalizado')::boolean, 'painel sabe que o acesso é personalizado');
select pg_temp.falha($$select * from public.admin_emergencias()$$, 'sem Emergências, o banco recusa');
select pg_temp.admin();
select pg_temp.ok(not ('emergencias' = any (public.permissoes_do_membro('sup-perm@teste.com'))), 'plantão e aviso de emergência seguem a pessoa');

-- O Responsável de setor com "cargos" dado pelo dono: só abaixo dele, e só o que ele tem.
select pg_temp.como('00000000-0000-0000-0000-000000000ad1');
select pg_temp.passa($$select public.admin_salvar_permissoes_membro('resp-perm@teste.com', public.cargo_permissoes('responsavel') || array['cargos', 'equipe_gerir'])$$,
  'dono dá Cargos ao Responsável');
select pg_temp.como('00000000-0000-0000-0000-000000000ab1');
select pg_temp.falha($$select public.admin_salvar_permissoes_membro('sup-perm@teste.com', public.cargo_permissoes('suporte') || array['configuracoes'])$$,
  'ninguém dá um acesso que não tem');
select pg_temp.falha($$select public.admin_salvar_permissoes_membro('gerente2-perm@teste.com', array['inicio'])$$, 'Responsável não mexe no gerente');
select pg_temp.falha($$select public.admin_salvar_cargo('gerente', array['inicio'])$$, 'Responsável não mexe no cargo Gerente');
select pg_temp.passa($$select public.admin_salvar_permissoes_membro('sup-perm@teste.com', null)$$, 'Responsável volta o Suporte ao padrão do cargo');
select pg_temp.admin();
select pg_temp.ok(public.permissoes_do_membro('sup-perm@teste.com') = public.cargo_permissoes('suporte'), 'sem exceções, vale o cargo');

-- Mudou de cargo: as exceções somem.
select pg_temp.como('00000000-0000-0000-0000-000000000aa1');
select pg_temp.passa($$select public.admin_salvar_permissoes_membro('mkt-perm@teste.com', public.cargo_permissoes('marketing') || array['pedidos'])$$, 'exceção no Marketing');
select pg_temp.passa($$select public.admin_mudar_cargo('mkt-perm@teste.com', 'suporte')$$, 'gerente muda o cargo');
select pg_temp.admin();
select pg_temp.ok(not exists (select 1 from public.equipe_permissoes where email = 'mkt-perm@teste.com'), 'cargo novo começa sem exceções');

-- Ninguém lê nem escreve as tabelas direto.
select pg_temp.como('00000000-0000-0000-0000-000000000aa1');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.equipe_permissoes', 'select')
  and not has_table_privilege('authenticated', 'public.equipe_permissoes', 'insert'), 'tabela de exceções fechada');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.cargo_acessos', 'select')
  and not has_table_privilege('authenticated', 'public.cargo_acessos', 'insert'), 'tabela de cargos fechada');
select pg_temp.admin();

rollback;
