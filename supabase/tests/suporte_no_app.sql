-- Testes do chat com o suporte dentro dos apps (migração 20261121004900).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.servico() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
end $$;

create function pg_temp.admin() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.falha(sql text, nome text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    raise notice 'ok - %', nome;
    return;
  end;
  raise exception 'FALHOU: % (não deu erro)', nome;
end $$;

create function pg_temp.conv(uid uuid) returns bigint language sql security definer as $$
  select id from public.suporte_conversas where usuario_id = uid and canal = 'app' order by id desc limit 1
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---------------------------------------------------------------- dados
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'dono@teste.com', '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'marina@cliente.com', '{"nome":"Marina Alves","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'paulo@cliente.com', '{"nome":"Paulo Reis","app":"cliente"}');
update public.perfis set email_verificado = true where not email_verificado;
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000ad';
insert into public.equipe (email, nome, papel, usuario_id, convidado_em, entrou_em) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000ad', now() - interval '3 days', now());

-- ---------------------------------------------------------------- online
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((public.suporte_app_estado()->>'online')::boolean = false, 'sem painel aberto: equipe offline');
select pg_temp.ok(public.suporte_app_estado()->>'email' = 'suporte@iservice.app.br', 'estado traz o e-mail do suporte');
select pg_temp.ok(public.suporte_app_estado()->'conversa' = 'null'::jsonb, 'sem conversa ainda');
select public.admin_suporte_presenca();
select pg_temp.ok((public.suporte_app_estado()->>'online')::boolean = false, 'cliente não se marca como equipe online');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_suporte_presenca();
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((public.suporte_app_estado()->>'online')::boolean, 'painel aberto: equipe online');
select pg_temp.admin();
update public.equipe set online_em = now() - interval '5 minutes';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((public.suporte_app_estado()->>'online')::boolean = false, 'painel fechado há 5 min: offline');
select pg_temp.falha($$select public.suporte_equipe_online()$$, 'app não chama a função interna de presença');

-- ---------------------------------------------------------------- cliente escreve
select pg_temp.falha($$select public.suporte_app_enviar('   ')$$, 'mensagem vazia é recusada');
select pg_temp.ok(jsonb_array_length(public.suporte_app_enviar('Oi, preciso de ajuda com um pedido')->'conversa'->'mensagens') = 1, 'primeira mensagem abre a conversa');
select pg_temp.ok(jsonb_array_length(public.suporte_app_enviar('Ligo para 61 99999-8888')->'conversa'->'mensagens') = 2, 'segunda entra na mesma conversa');
select pg_temp.ok((public.suporte_app_estado()->'conversa'->'mensagens'->0->>'minha')::boolean, 'mensagem da pessoa aparece como dela');
select pg_temp.admin();
select pg_temp.ok((select canal = 'app' and contato_email = 'marina@cliente.com' and contato_nome = 'Marina Alves' and responsavel = 'dono@teste.com'
  and assunto = 'Chat do app Cliente' and mensagens = 2 and nao_lida from public.suporte_conversas where usuario_id = '00000000-0000-0000-0000-0000000000c1'),
  'conversa do app entra na caixa com e-mail, nome e rodízio');
select pg_temp.falha($$insert into public.suporte_conversas (canal, contato_email) values ('fax', 'a@b.c')$$, 'canal desconhecido é recusado');

-- outra pessoa não vê a conversa
select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select pg_temp.ok(public.suporte_app_estado()->'conversa' = 'null'::jsonb, 'outra pessoa não vê a conversa da Marina');
select pg_temp.falha($$select public.admin_suporte_responder_app(pg_temp.conv('00000000-0000-0000-0000-0000000000c1'), 'oi')$$, 'cliente não responde pelo painel');
select pg_temp.falha($$select * from public.suporte_mensagens$$, 'cliente não lê a tabela direto');
set local role anon;
select pg_temp.falha($$select public.suporte_app_enviar('oi')$$, 'sem login não escreve');

-- ---------------------------------------------------------------- painel responde
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) from public.admin_suporte_conversas('todos', 'todos', null, 50, 0, 'app')) = 1, 'filtro App na lista');
select pg_temp.falha($$select public.admin_suporte_responder_app(pg_temp.conv('00000000-0000-0000-0000-0000000000c1'), '  ')$$, 'resposta vazia é recusada');
select pg_temp.ok((public.admin_suporte_responder_app(pg_temp.conv('00000000-0000-0000-0000-0000000000c1'), 'Olá, Marina! Já vejo isso.')->>'enviado')::boolean, 'equipe responde pelo app');
select pg_temp.falha($$select public.admin_suporte_preparar_envio(pg_temp.conv('00000000-0000-0000-0000-0000000000c1'), 'por e-mail')$$, 'conversa do app não responde por e-mail');
select pg_temp.ok(public.admin_suporte_conversa(pg_temp.conv('00000000-0000-0000-0000-0000000000c1')) ? 'contato_viu_em', 'painel mostra quando a pessoa viu');
select pg_temp.admin();
select pg_temp.ok((select status = 'em_atendimento' from public.suporte_conversas where usuario_id = '00000000-0000-0000-0000-0000000000c1'), 'responder leva para Em atendimento');
select pg_temp.ok((select count(*) = 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000c1' and tipo = 'suporte' and dados->>'tela' = 'suporte'),
  'pessoa recebe aviso da resposta');
-- (na transação o relógio não anda: a pessoa viu a conversa antes da resposta)
update public.suporte_conversas set contato_viu_em = now() - interval '1 minute' where usuario_id = '00000000-0000-0000-0000-0000000000c1';

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((public.suporte_app_estado(false)->>'nao_lidas')::int = 1, 'resposta nova conta como não lida');
select pg_temp.ok((public.suporte_app_estado()->'conversa'->'mensagens'->2->>'autor') = 'Dono', 'resposta mostra o primeiro nome de quem atendeu');
select pg_temp.ok((public.suporte_app_estado(false)->>'nao_lidas')::int = 0, 'abrir a conversa marca como lida');
select pg_temp.admin();
insert into public.suporte_mensagens (conversa_id, direcao, texto) values (pg_temp.conv('00000000-0000-0000-0000-0000000000c1'), 'nota', 'Nota secreta');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(not (public.suporte_app_estado()::text like '%Nota secreta%'), 'nota interna não aparece no app');

-- ---------------------------------------------------------------- encerrar e voltar
select pg_temp.admin();
update public.suporte_conversas set status = 'encerrado', encerrada_em = now() where usuario_id = '00000000-0000-0000-0000-0000000000c1';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(public.suporte_app_estado()->'conversa'->>'status' = 'encerrado', 'conversa encerrada ainda aparece');
select public.suporte_app_enviar('Voltei');
select pg_temp.admin();
select pg_temp.ok((select count(*) = 1 and bool_and(status = 'aberto') from public.suporte_conversas where usuario_id = '00000000-0000-0000-0000-0000000000c1'), 'escreveu logo depois: reabre a mesma');
update public.suporte_conversas set status = 'encerrado', encerrada_em = now() - interval '5 days' where usuario_id = '00000000-0000-0000-0000-0000000000c1';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(public.suporte_app_estado()->'conversa' = 'null'::jsonb, 'encerrada há dias some da tela');
select public.suporte_app_enviar('Outro assunto');
select pg_temp.admin();
select pg_temp.ok((select count(*) = 2 from public.suporte_conversas where usuario_id = '00000000-0000-0000-0000-0000000000c1'), 'escreveu dias depois: conversa nova');

-- ---------------------------------------------------------------- limite
select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select public.suporte_app_enviar('msg ' || g) from generate_series(1, 20) g;
select pg_temp.falha($$select public.suporte_app_enviar('mais uma')$$, 'muitas mensagens seguidas são barradas');

rollback;
