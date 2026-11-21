-- Testes do WhatsApp do atendimento na caixa do suporte (migração 20261121004800).
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

-- Uma mensagem chegando pela Meta.
create function pg_temp.zap(id text, tel text, texto text default 'Oi, preciso de ajuda', nome text default 'Cliente Zap') returns jsonb language plpgsql as $$
begin
  return public.suporte_receber_whatsapp(jsonb_build_object('id_externo', id, 'telefone', tel, 'nome', nome, 'texto', texto, 'tipo', 'text'));
end $$;

-- Id da conversa pelo telefone (a equipe não lê a tabela direto).
create function pg_temp.conv(tel text) returns bigint language sql security definer as $$
  select id from public.suporte_conversas where contato_telefone = tel order by id desc limit 1
$$;
create function pg_temp.msg(ext text) returns bigint language sql security definer as $$
  select id from public.suporte_mensagens where id_externo = ext and direcao = 'enviada'
$$;

grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---------------------------------------------------------------- dados
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'dono@teste.com', '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'bruno@teste.com', '{"nome":"Bruno Lima","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'marina@cliente.com', '{"nome":"Marina Alves","app":"cliente"}');
update public.perfis set email_verificado = true where not email_verificado;
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set telefone = '61998765432' where id = '00000000-0000-0000-0000-0000000000c1';
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000ad';
insert into public.equipe (email, nome, papel, usuario_id, convidado_em, entrou_em) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000ad', now() - interval '3 days', now()),
  ('bruno@teste.com', 'Bruno Lima', 'suporte', null, now() - interval '1 day', null);
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000a2';

-- ---------------------------------------------------------------- utilidades
select pg_temp.ok('61998765432' = any (public.suporte_formas_telefone('556198765432')), 'número antigo sem o 9 acha o celular com 9');
select pg_temp.ok('5561998765432' = any (public.suporte_formas_telefone('61998765432')), 'celular sem 55 acha o número do WhatsApp');
select pg_temp.ok(public.cfg_bool('whatsapp_ativo', true) = false, 'WhatsApp começa desligado');

-- ---------------------------------------------------------------- chegada
select pg_temp.servico();
select pg_temp.ok((pg_temp.zap('wamid.1', '5561998765432')->>'nova')::boolean, 'primeira mensagem abre conversa');
select pg_temp.ok((pg_temp.zap('wamid.1', '5561998765432')->>'repetido')::boolean, 'a mesma mensagem duas vezes não duplica');
select pg_temp.ok(not (pg_temp.zap('wamid.2', '5561998765432', 'Mais uma coisa')->>'nova')::boolean, 'segunda mensagem entra na mesma conversa');
select pg_temp.ok((pg_temp.zap('wamid.3', '5561988887777', 'Oi', 'João')->>'responsavel') = 'bruno@teste.com', 'outro número vai para o próximo do rodízio');
select pg_temp.ok(pg_temp.zap('wamid.4', 'abc')->>'ignorado' is not null, 'telefone inválido é ignorado');
select pg_temp.admin();
select pg_temp.ok((select canal = 'whatsapp' and contato_email is null and contato_telefone = '5561998765432' and mensagens = 2
  from public.suporte_conversas where contato_telefone = '5561998765432'), 'conversa de WhatsApp sem e-mail, com o telefone');
select pg_temp.ok((select usuario_id = '00000000-0000-0000-0000-0000000000c1' from public.suporte_conversas where contato_telefone = '5561998765432'),
  'número de quem tem conta é ligado ao cadastro');
select pg_temp.falha($$insert into public.suporte_conversas (canal, contato_email) values ('email', null)$$, 'conversa de e-mail continua exigindo e-mail');
select pg_temp.falha($$insert into public.suporte_conversas (canal, contato_telefone) values ('whatsapp', '12')$$, 'conversa de WhatsApp exige telefone');

-- ---------------------------------------------------------------- permissões
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.falha($$select public.suporte_receber_whatsapp('{"telefone":"5561999999999","id_externo":"x"}')$$, 'só a função do servidor registra WhatsApp recebido');
select pg_temp.falha($$select public.suporte_whatsapp_status('x', 'read')$$, 'só a função do servidor marca entregue e lida');
select pg_temp.falha($$select public.admin_suporte_preparar_whatsapp(1, 'oi')$$, 'cliente não responde pelo painel');

-- ---------------------------------------------------------------- painel
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) from public.admin_suporte_conversas('todos', 'todos', null, 50, 0, 'whatsapp')) = 2, 'filtro WhatsApp na lista');
select pg_temp.ok((select count(*) from public.admin_suporte_conversas('todos', 'todos', null, 50, 0, 'email')) = 0, 'filtro E-mail na lista');
select pg_temp.ok((select canal from public.admin_suporte_conversas('todos', 'todos', '98765-432', 50, 0)) = 'whatsapp', 'busca pelo número');
select pg_temp.ok((public.admin_suporte_conversa(pg_temp.conv('5561998765432'))->>'janela_ate')::timestamptz > now() + interval '23 hours',
  'conversa mostra a janela de 24 horas');
select pg_temp.falha($$select public.admin_suporte_preparar_whatsapp(pg_temp.conv('5561998765432'), 'Olá!')$$,
  'desligado: painel não envia');
select pg_temp.admin();
update public.app_config set valor = 'true' where chave = 'whatsapp_ativo';
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.falha($$select public.admin_suporte_preparar_whatsapp(pg_temp.conv('5561998765432'), '   ')$$,
  'não envia resposta vazia');
select pg_temp.ok((public.admin_suporte_preparar_whatsapp(pg_temp.conv('5561998765432'), 'Olá, Marina! Já vejo isso.')->>'para') = '5561998765432',
  'resposta vai para o número do cliente');
select pg_temp.falha($$select public.admin_suporte_preparar_envio(pg_temp.conv('5561998765432'), 'por e-mail')$$,
  'conversa de WhatsApp não responde por e-mail');
select pg_temp.admin();
select pg_temp.ok((select status = 'em_atendimento' and responsavel = 'dono@teste.com' from public.suporte_conversas where contato_telefone = '5561998765432'),
  'responder leva para Em atendimento');

-- ---------------------------------------------------------------- entregue, lida, falhou
select public.suporte_resultado_envio((select max(id) from public.suporte_mensagens where direcao = 'enviada'), true, 'wamid.env1');
select pg_temp.servico();
select public.suporte_whatsapp_status('wamid.env1', 'delivered');
select public.suporte_whatsapp_status('wamid.env1', 'read');
select pg_temp.admin();
select pg_temp.ok((select entregue_em is not null and lida_em is not null and envio = 'enviado' from public.suporte_mensagens where id_externo = 'wamid.env1'),
  'aviso da Meta marca entregue e lida');
select pg_temp.servico();
select public.suporte_whatsapp_status('wamid.env1', 'failed', 'O número não tem WhatsApp.');
select pg_temp.admin();
select pg_temp.ok((select envio = 'erro' from public.suporte_mensagens where id_externo = 'wamid.env1'), 'falha da Meta aparece como erro');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select public.admin_suporte_preparar_whatsapp(null, null, pg_temp.msg('wamid.env1'))->>'texto')
  = 'Olá, Marina! Já vejo isso.', 'reenviar a resposta que falhou');

-- ---------------------------------------------------------------- janela de 24 horas
select pg_temp.admin();
update public.suporte_mensagens set criada_em = now() - interval '25 hours'
where direcao = 'recebida' and conversa_id = pg_temp.conv('5561988887777');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.falha($$select public.admin_suporte_preparar_whatsapp(pg_temp.conv('5561988887777'), 'Oi João')$$,
  'depois de 24 horas não envia texto livre');

-- ---------------------------------------------------------------- encerrar e voltar
select pg_temp.admin();
update public.suporte_conversas set status = 'encerrado', encerrada_em = now() where contato_telefone = '5561998765432';
select pg_temp.servico();
select pg_temp.ok(not (pg_temp.zap('wamid.5', '5561998765432', 'Voltei')->>'nova')::boolean, 'escreveu logo depois de encerrar: reabre a mesma conversa');
select pg_temp.admin();
select pg_temp.ok((select status = 'aberto' from public.suporte_conversas where contato_telefone = '5561998765432'), 'conversa reaberta fica Em aberto');
update public.suporte_conversas set status = 'encerrado', encerrada_em = now() - interval '5 days' where contato_telefone = '5561998765432';
select pg_temp.servico();
select pg_temp.ok((pg_temp.zap('wamid.6', '5561998765432', 'Outro assunto')->>'nova')::boolean, 'escreveu dias depois: conversa nova');

-- ---------------------------------------------------------------- resposta automática
select pg_temp.admin();
select pg_temp.ok((select public.suporte_resposta_automatica(id)->>'enviar' from public.suporte_conversas where contato_telefone = '5561988887777') = 'false',
  'resposta automática por e-mail não vale para WhatsApp');

rollback;
