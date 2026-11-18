-- Testes dos cargos da equipe (migração 20261116003100).
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
  ('Do suporte', 'a@x.com', 'aberto', 'suporte@teste.com'),
  ('Do outro', 'b@x.com', 'aberto', 'suporte2@teste.com'),
  ('Sem ninguém', 'c@x.com', 'aberto', null);
select set_config('t.meu', (select id::text from public.suporte_conversas where assunto = 'Do suporte'), true);
select set_config('t.outro', (select id::text from public.suporte_conversas where assunto = 'Do outro'), true);
select set_config('t.livre', (select id::text from public.suporte_conversas where assunto = 'Sem ninguém'), true);

-- ---------------------------------------------------------------- o que cada um recebe
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok((public.admin_meu_acesso()->>'cargo') = 'dono', 'dono entra como Dono');
select pg_temp.ok(public.pode('configuracoes'), 'só o dono tem Configurações');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((public.admin_meu_acesso()->>'cargo_nome') = 'Gerente geral', 'gerente entra como Gerente geral');
select pg_temp.ok(not public.pode('configuracoes') and public.pode('precos') and public.pode('catalogo'), 'gerente tem Preços e Catálogo, sem Configurações');
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok((select jsonb_array_length(public.admin_meu_acesso()->'permissoes')) = 7, 'suporte recebe só as 7 permissões dele');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.falha($$select public.admin_meu_acesso()$$, 'cliente não tem acesso nenhum');

-- ---------------------------------------------------------------- suporte
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.passa($$select public.admin_resumo()$$, 'suporte abre o Início');
select pg_temp.passa($$select * from public.admin_pedidos()$$, 'suporte consulta pedidos');
select pg_temp.passa($$select * from public.admin_emergencias()$$, 'suporte vê emergências');
select pg_temp.passa($$select * from public.admin_reclamacoes()$$, 'suporte vê a Garantia');
select pg_temp.passa($$select * from public.admin_cadastros()$$, 'suporte vê a lista de cadastros');
select pg_temp.falha($$select public.admin_decidir_cadastro('00000000-0000-0000-0000-0000000000c1', true)$$, 'suporte não aprova cadastro');
select pg_temp.falha($$select * from public.admin_denuncias()$$, 'suporte não vê denúncias');
select pg_temp.falha($$select public.admin_suspender('00000000-0000-0000-0000-0000000000c1', true, 'x')$$, 'suporte não suspende');
select pg_temp.falha($$select * from public.admin_equipe()$$, 'suporte não vê a Equipe');
select pg_temp.falha($$select * from public.admin_registro()$$, 'suporte não vê o Registro');
select pg_temp.falha($$select * from public.admin_site()$$, 'suporte não vê Site e downloads');
select pg_temp.falha($$select * from public.admin_tabela_precos()$$, 'suporte não vê Preços');
select pg_temp.falha($$select public.admin_enviar_comunicado('Oi', 'Texto do comunicado', null, null, 'todos')$$, 'suporte não envia comunicado');
select pg_temp.ok((public.admin_usuario('00000000-0000-0000-0000-0000000000c1') #>> '{perfil,cpf}') = '***.982.247-**', 'suporte vê o CPF mascarado');
select pg_temp.ok((public.admin_usuario('00000000-0000-0000-0000-0000000000c1') #>> '{perfil,nascimento}') is null, 'suporte não vê a data de nascimento');
select pg_temp.ok((public.admin_usuario('00000000-0000-0000-0000-0000000000c1') -> 'perfil') ? 'telefone', 'suporte vê o telefone para atender');
select pg_temp.ok((select count(*) from public.documentos) = 0, 'suporte não lê documentos de identidade');
with x as (update public.app_config set valor = valor returning 1) select pg_temp.ok(count(*) = 0, 'suporte não muda Configurações') from x;
with x as (update public.profissoes set nome = nome returning 1) select pg_temp.ok(count(*) = 0, 'suporte não mexe nas Profissões') from x;
select pg_temp.ok((select count(*) from public.admin_acoes) = 0, 'suporte não lê o registro direto na tabela');

-- E-mails: os próprios e os sem responsável.
select pg_temp.ok((select count(*) = 2 from public.admin_suporte_conversas('aberto', 'todos')), 'suporte vê só os próprios e-mails e os sem responsável');
select pg_temp.ok((select count(*) = 1 from public.admin_suporte_conversas('aberto', 'meus')), 'Meus continua mostrando os dele');
select pg_temp.ok((select count(*) = 0 from public.admin_suporte_conversas('aberto', 'suporte2@teste.com') c where c.responsavel = 'suporte2@teste.com'),
  'suporte não lista os e-mails de um colega');
select pg_temp.falha($$select public.admin_suporte_conversa(current_setting('t.outro')::bigint)$$,
  'suporte não abre o e-mail de um colega');
select pg_temp.falha($$select public.admin_suporte_nota(current_setting('t.outro')::bigint, 'oi')$$,
  'suporte não escreve nota no e-mail de um colega');
select pg_temp.passa($$select public.admin_suporte_conversa(current_setting('t.livre')::bigint)$$,
  'suporte abre um e-mail sem responsável');
select pg_temp.passa($$select public.admin_suporte_transferir(current_setting('t.meu')::bigint, 'suporte2@teste.com')$$,
  'suporte passa o próprio e-mail para um colega');
select pg_temp.falha($$select public.admin_suporte_transferir(current_setting('t.outro')::bigint, 'suporte@teste.com')$$,
  'suporte não pega o e-mail de um colega');
select pg_temp.falha($$select public.admin_suporte_rodizio('suporte2@teste.com', false)$$, 'suporte não mexe no rodízio');

-- Garantia: registra e media, mas não fecha.
select pg_temp.falha($$select public.admin_mediar_reclamacao(-1, 'resolvida', 'Resolvido')$$, 'suporte não fecha reclamação da Garantia');

-- ---------------------------------------------------------------- marketing
select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
select pg_temp.passa($$select * from public.admin_site()$$, 'marketing vê Site e downloads');
select pg_temp.passa($$select * from public.admin_mapa_buscas()$$, 'marketing vê Buscas e mapa');
select pg_temp.passa($$select * from public.admin_ranking_avaliacoes()$$, 'marketing vê Avaliações');
select pg_temp.passa($$select * from public.admin_comunicados()$$, 'marketing vê Comunicados');
select pg_temp.falha($$select * from public.admin_usuarios()$$, 'marketing não vê Pessoas');
select pg_temp.falha($$select public.admin_usuario('00000000-0000-0000-0000-0000000000c1')$$, 'marketing não abre a ficha de ninguém');
select pg_temp.falha($$select * from public.admin_pedidos()$$, 'marketing não vê Pedidos');
select pg_temp.falha($$select * from public.admin_suporte_conversas()$$, 'marketing não vê E-mails');
select pg_temp.falha($$select public.admin_ocultar_avaliacao('00000000-0000-0000-0000-000000000000', true, 'x')$$, 'marketing não oculta avaliação');

-- ---------------------------------------------------------------- responsável de setor
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok((select count(*) = 3 from public.admin_suporte_conversas('aberto', 'todos')), 'responsável vê os e-mails de todos');
select pg_temp.ok((public.admin_usuario('00000000-0000-0000-0000-0000000000c1') #>> '{perfil,cpf}') = '52998224725', 'responsável vê o CPF completo');
select pg_temp.ok((select array_agg(papel order by papel) from public.admin_equipe()) = array['responsavel', 'suporte', 'suporte'],
  'responsável vê só o time de Atendimento na Equipe');
select pg_temp.passa($$select public.admin_suporte_rodizio('suporte2@teste.com', false)$$, 'responsável tira alguém do time do rodízio');
select pg_temp.falha($$select public.admin_suporte_rodizio('gerente@teste.com', false)$$, 'responsável não mexe no rodízio do gerente');
select pg_temp.falha($$select public.admin_convidar_equipe('novo@teste.com', 'Novo', 'suporte')$$, 'responsável não convida ninguém');
select pg_temp.falha($$select public.admin_suspender('00000000-0000-0000-0000-0000000000a1', true, 'x')$$, 'responsável não suspende o gerente');
select pg_temp.falha($$select * from public.admin_site()$$, 'responsável não vê Crescimento');
select pg_temp.falha($$select * from public.admin_tabela_precos()$$, 'responsável não vê Preços');
select pg_temp.passa($$select * from public.admin_registro()$$, 'responsável abre o Registro do time');
select pg_temp.ok(public.pode_trocar_foto_equipe('00000000-0000-0000-0000-0000000000e1'), 'responsável troca a foto de alguém do Suporte');
select pg_temp.ok(not public.pode_trocar_foto_equipe('00000000-0000-0000-0000-0000000000a1'), 'responsável não troca a foto do gerente');

-- ---------------------------------------------------------------- gerente
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((select count(*) = 6 from public.admin_equipe()), 'gerente vê a equipe toda');
select pg_temp.ok((select not pode_gerir from public.admin_equipe() where papel = 'dono'), 'gerente não pode gerir o dono');
select pg_temp.passa($$select public.admin_convidar_equipe('novo@teste.com', 'Novo', 'suporte')$$, 'gerente convida alguém do Suporte');
select pg_temp.ok((select papel = 'suporte' from public.admin_equipe() where email = 'novo@teste.com'), 'convite guarda o cargo');
select pg_temp.falha($$select public.admin_convidar_equipe('outro@teste.com', 'Outro', 'gerente')$$, 'gerente não convida outro gerente');
select pg_temp.passa($$select public.admin_mudar_cargo('novo@teste.com', 'responsavel')$$, 'gerente promove Suporte a Responsável');
select pg_temp.falha($$select public.admin_mudar_cargo('novo@teste.com', 'gerente')$$, 'gerente não promove ninguém a gerente');
select pg_temp.falha($$select public.admin_mudar_cargo('dono@teste.com', 'suporte')$$, 'gerente não mexe no cargo do dono');
select pg_temp.falha($$select public.admin_remover_equipe('dono@teste.com')$$, 'gerente não remove o dono');
select pg_temp.passa($$select public.admin_remover_equipe('novo@teste.com')$$, 'gerente remove alguém abaixo dele');
select pg_temp.falha($$select public.admin_transferir_dono('gerente@teste.com')$$, 'gerente não pega a posição de dono');
select pg_temp.ok((select count(*) from public.admin_acoes) > 0, 'gerente lê o registro completo');
select pg_temp.ok((select count(*) from public.admin_registro() where acao = 'convidar_equipe') > 0, 'gerente vê o convite no Registro');
with x as (update public.app_config set valor = valor returning 1) select pg_temp.ok(count(*) = 0, 'gerente não muda Configurações') from x;
with x as (update public.profissoes set nome = nome returning 1) select pg_temp.ok(count(*) > 0, 'gerente edita as Profissões') from x;

-- ---------------------------------------------------------------- dono
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
with x as (update public.app_config set valor = valor returning 1) select pg_temp.ok(count(*) > 0, 'dono muda Configurações') from x;
select pg_temp.passa($$select public.admin_convidar_equipe('outro@teste.com', 'Outro', 'gerente')$$, 'dono convida um gerente');
select pg_temp.falha($$select public.admin_convidar_equipe('x@teste.com', 'X', 'dono')$$, 'ninguém é convidado como dono');
select pg_temp.passa($$select public.admin_mudar_cargo('gerente@teste.com', 'responsavel')$$, 'dono muda o cargo do gerente');
select pg_temp.falha($$select public.admin_transferir_dono('outro@teste.com')$$, 'posição de dono só vai para quem já entrou no painel');
select pg_temp.passa($$select public.admin_transferir_dono('gerente@teste.com')$$, 'dono passa a posição de dono');
select pg_temp.admin();
select pg_temp.ok((select papel from public.equipe where email = 'gerente@teste.com') = 'dono'
  and (select papel from public.equipe where email = 'dono@teste.com') = 'gerente', 'antigo dono vira gerente e só existe um dono');
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok(not public.pode('configuracoes'), 'antigo dono perde Configurações');

rollback;
