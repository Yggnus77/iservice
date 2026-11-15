-- Testes da caixa de e-mail do suporte (aba E-mails do painel). Rodam numa transação desfeita no fim.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/caixa_suporte.sql
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

-- Um e-mail chegando pelo Resend.
create function pg_temp.chega(id text, de text, assunto text, refs text[] default '{}', mid text default null) returns jsonb language plpgsql as $$
begin
  return public.suporte_receber(jsonb_build_object('id_externo', id, 'message_id', coalesce(mid, id || '@mail.exemplo.com'),
    'referencias', to_jsonb(refs), 'de_email', de, 'de_nome', initcap(split_part(de, '@', 1)),
    'para', '["suporte@iservice.app.br"]'::jsonb, 'assunto', assunto, 'texto', 'Olá, preciso de ajuda.', 'html', '<p>Olá</p>'));
end $$;

grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---------------------------------------------------------------- dados
-- ad = dono, s1 e s2 = suporte, c1 = cliente do app
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'dono@teste.com', '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'ana@teste.com', '{"nome":"Ana Souza","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'bruno@teste.com', '{"nome":"Bruno Lima","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'marina@cliente.com', '{"nome":"Marina Alves","app":"cliente"}');
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000ad';
insert into public.equipe (email, nome, papel, usuario_id, convidado_em, entrou_em) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000ad', now() - interval '3 days', now()),
  ('ana@teste.com', 'Ana Souza', 'suporte', null, now() - interval '2 days', null),
  ('bruno@teste.com', 'Bruno Lima', 'suporte', null, now() - interval '1 day', null);
-- Ana e Bruno confirmam o e-mail: o gatilho da equipe libera o acesso.
update auth.users set email_confirmed_at = now() where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok((select count(*) = 3 from public.perfis where e_admin), 'três pessoas da equipe com acesso');

-- ---------------------------------------------------------------- chegada e rodízio
select pg_temp.servico();
select pg_temp.ok((pg_temp.chega('r1', 'marina@cliente.com', 'Dúvida no pedido')->>'responsavel') = 'dono@teste.com', 'primeiro e-mail vai para o primeiro da fila');
select pg_temp.ok((pg_temp.chega('r2', 'joao@gmail.com', 'Quero ser profissional')->>'responsavel') = 'ana@teste.com', 'segundo e-mail vai para a Ana');
select pg_temp.ok((pg_temp.chega('r3', 'lucia@gmail.com', 'Pagamento')->>'responsavel') = 'bruno@teste.com', 'terceiro e-mail vai para o Bruno');
select pg_temp.ok((pg_temp.chega('r4', 'pedro@gmail.com', 'Outra dúvida')->>'responsavel') = 'dono@teste.com', 'quarto e-mail volta para o começo do rodízio');
select pg_temp.ok((pg_temp.chega('r1', 'marina@cliente.com', 'Dúvida no pedido')->>'repetido')::boolean, 'o mesmo e-mail duas vezes não duplica');
select pg_temp.ok((pg_temp.chega('r5', 'nao-responda@iservice.app.br', 'Cópia')->>'ignorado') is not null, 'e-mail do próprio domínio é ignorado');
select pg_temp.admin();
select pg_temp.ok((select count(*) = 4 from public.suporte_conversas), 'quatro conversas abertas');
select pg_temp.ok((select usuario_id = '00000000-0000-0000-0000-0000000000c1' from public.suporte_conversas where contato_email = 'marina@cliente.com'), 'e-mail de quem tem conta é ligado ao cadastro');
select pg_temp.ok((select status = 'aberto' and nao_lida from public.suporte_conversas where contato_email = 'joao@gmail.com'), 'conversa nova começa Em aberto e não lida');
select public.suporte_receber(jsonb_build_object('id_externo', 'r6', 'de_email', 'x@y.com', 'assunto', 'RE: Fwd: Preço'));
select pg_temp.ok(exists (select 1 from public.suporte_conversas where contato_email = 'x@y.com' and assunto = 'Preço'), 'tira Re:/Fwd: do assunto da conversa');

-- ---------------------------------------------------------------- segurança
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.falha($$select public.admin_suporte_conversas('aberto', 'todos')$$, 'cliente não lê a caixa de suporte');
select pg_temp.falha($$select * from public.suporte_conversas$$, 'cliente não lê a tabela direto');
select pg_temp.falha($$select public.suporte_receber('{"id_externo":"rx","de_email":"a@b.com"}')$$, 'só a função do servidor registra e-mail recebido');
select pg_temp.falha($$select public.suporte_resultado_envio(1, true)$$, 'só a função do servidor marca envio');

-- ---------------------------------------------------------------- painel
select pg_temp.admin();
select set_config('t.joao', (select id::text from public.suporte_conversas where contato_email = 'joao@gmail.com'), true);
select set_config('t.prot', public.suporte_protocolo(current_setting('t.joao')::bigint), true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((select count(*) = 2 from public.admin_suporte_conversas('aberto', 'meus')), 'Ana vê as conversas dela em Meus');
select pg_temp.ok((select count(*) = 5 from public.admin_suporte_conversas('aberto', 'todos')), 'Ana vê todas em Todos');
select pg_temp.ok((public.admin_suporte_contagem()->>'meus_nao_lidos')::int = 2, 'contador de não lidos da Ana');
select pg_temp.ok((select count(*) = 1 from public.admin_suporte_conversas('todos', 'todos', 'profissional')), 'busca pelo assunto');
select pg_temp.ok((select count(*) = 1 from public.admin_suporte_conversas('todos', 'todos', current_setting('t.prot'))), 'busca pelo protocolo');

-- Ana abre e responde a conversa do João.
select pg_temp.ok(jsonb_array_length(public.admin_suporte_conversa(current_setting('t.joao')::bigint)->'mensagens') = 2, 'conversa mostra o aviso do rodízio e o e-mail');
select pg_temp.ok((public.admin_suporte_contagem()->>'meus_nao_lidos')::int = 1, 'abrir a conversa marca como lida');
select set_config('t.envio', public.admin_suporte_preparar_envio(current_setting('t.joao')::bigint, 'Oi João, é só baixar o app Profissional.')::text, true);
select pg_temp.ok((current_setting('t.envio')::jsonb->>'assunto') = 'Re: Quero ser profissional [' || current_setting('t.prot') || ']', 'resposta leva Re: e o protocolo no assunto');
select pg_temp.ok((current_setting('t.envio')::jsonb->>'in_reply_to') = 'r2@mail.exemplo.com', 'resposta aponta para o e-mail do cliente');
select pg_temp.ok((current_setting('t.envio')::jsonb->'citacao'->>'texto') = 'Olá, preciso de ajuda.', 'resposta cita a última mensagem do cliente');
select pg_temp.ok((select status = 'em_atendimento' from public.admin_suporte_conversas('todos', 'meus') where id = current_setting('t.joao')::bigint), 'responder leva para Em atendimento');
select pg_temp.falha($$select public.admin_suporte_preparar_envio(1, '   ')$$, 'não envia resposta vazia');

select pg_temp.servico();
select public.suporte_resultado_envio((current_setting('t.envio')::jsonb->>'mensagem_id')::bigint, true, 'resend-1', null, 'id-do-resend@iservice.app.br');
-- O João responde (Gmail manda In-Reply-To com o Message-ID do nosso e-mail).
select pg_temp.ok((pg_temp.chega('r7', 'joao@gmail.com', 'Re: Quero ser profissional [' || current_setting('t.prot') || ']', array['r2@mail.exemplo.com', 'id-do-resend@iservice.app.br'])->>'conversa_id')::bigint = current_setting('t.joao')::bigint,
  'resposta do cliente entra na mesma conversa');
-- Sem cabeçalhos, mas com o protocolo no assunto, do mesmo contato.
select pg_temp.ok((pg_temp.chega('r8', 'joao@gmail.com', 'Re: [' || current_setting('t.prot') || '] mais uma coisa')->>'conversa_id')::bigint = current_setting('t.joao')::bigint, 'protocolo no assunto agrupa a conversa');
-- Protocolo no assunto vindo de outra pessoa não entra na conversa do João.
select pg_temp.ok((pg_temp.chega('r9', 'estranho@gmail.com', 'Re: [' || current_setting('t.prot') || '] oi')->>'conversa_id')::bigint <> current_setting('t.joao')::bigint, 'outra pessoa não entra na conversa pelo protocolo');
select pg_temp.admin();
select pg_temp.ok((select nao_lida and status = 'em_atendimento' and responsavel = 'ana@teste.com' from public.suporte_conversas where id = current_setting('t.joao')::bigint), 'resposta do cliente fica não lida para a Ana');
select pg_temp.ok((select message_id = 'id-do-resend@iservice.app.br' and envio = 'enviado' from public.suporte_mensagens where id = (current_setting('t.envio')::jsonb->>'mensagem_id')::bigint), 'guarda o Message-ID do envio');

-- Encerrar e reabrir.
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select public.admin_suporte_status(current_setting('t.joao')::bigint, 'encerrado');
select pg_temp.ok((select count(*) = 1 from public.admin_suporte_conversas('encerrado', 'meus')), 'conversa encerrada aparece em Encerrado');
select pg_temp.servico();
select pg_temp.chega('r10', 'joao@gmail.com', 'Re: Quero ser profissional [' || current_setting('t.prot') || ']', array['id-do-resend@iservice.app.br']);
select pg_temp.admin();
select pg_temp.ok((select status = 'aberto' and responsavel = 'ana@teste.com' and encerrada_em is null from public.suporte_conversas where id = current_setting('t.joao')::bigint),
  'cliente respondeu depois de encerrada: volta para Em aberto com a mesma pessoa');

-- Nota interna, transferência e e-mail novo puxado pela equipe.
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select public.admin_suporte_nota(current_setting('t.joao')::bigint, 'Cliente já tem conta de cliente.');
select public.admin_suporte_transferir(current_setting('t.joao')::bigint, 'bruno@teste.com');
select pg_temp.ok((public.admin_suporte_conversa(current_setting('t.joao')::bigint)->>'responsavel') = 'bruno@teste.com', 'transferir troca o responsável');
select pg_temp.falha($$select public.admin_suporte_transferir(1, 'marina@cliente.com')$$, 'só transfere para quem é da equipe');
select set_config('t.novo', public.admin_suporte_preparar_envio(null, 'Olá Marina, tudo certo com o seu pedido?', 'Marina@Cliente.com', 'Seu pedido de ontem')::text, true);
select pg_temp.ok((select c->>'status' = 'em_atendimento' and c->>'responsavel' = 'ana@teste.com' and c->'pessoa' is not null and c->>'contato_email' = 'marina@cliente.com'
  from public.admin_suporte_conversa((current_setting('t.novo')::jsonb->>'conversa_id')::bigint) c),
  'e-mail novo abre conversa Em atendimento com quem escreveu');
select pg_temp.falha($$select public.admin_suporte_preparar_envio(null, 'oi', 'suporte@iservice.app.br', 'teste')$$, 'não escreve para o próprio domínio');

-- Reenvio depois de falha.
select pg_temp.servico();
select public.suporte_resultado_envio((current_setting('t.novo')::jsonb->>'mensagem_id')::bigint, false, null, '500 erro');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((public.admin_suporte_preparar_reenvio((current_setting('t.novo')::jsonb->>'mensagem_id')::bigint)->>'para') = 'marina@cliente.com', 'reenvio de mensagem que falhou');
select pg_temp.falha(format('select public.admin_suporte_preparar_reenvio(%s)', current_setting('t.novo')::jsonb->>'mensagem_id'), 'não reenvia o que já está enviando');

-- ---------------------------------------------------------------- rodízio: pausar e sair da equipe
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_suporte_rodizio('bruno@teste.com', false);
select pg_temp.servico();
select pg_temp.ok((pg_temp.chega('r11', 'a1@gmail.com', 'A')->>'responsavel') <> 'bruno@teste.com'
  and (pg_temp.chega('r12', 'a2@gmail.com', 'B')->>'responsavel') <> 'bruno@teste.com'
  and (pg_temp.chega('r13', 'a3@gmail.com', 'C')->>'responsavel') <> 'bruno@teste.com', 'quem pausou o rodízio não recebe');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) = 3 from public.admin_suporte_equipe()), 'lista da equipe no rodízio');
select public.admin_remover_equipe('ana@teste.com');
select pg_temp.admin();
select pg_temp.ok((select count(*) = 0 from public.suporte_conversas where responsavel is null and status <> 'encerrado'), 'conversas de quem saiu foram redistribuídas');
select pg_temp.ok((select array_agg(contato_email order by contato_email) = array['estranho@gmail.com', 'joao@gmail.com', 'lucia@gmail.com'] from public.suporte_conversas where responsavel = 'bruno@teste.com'),
  'redistribuição respeita quem pausou o rodízio');

-- Equipe inteira fora do rodízio: e-mail fica sem responsável, e volta a ser entregue quando alguém entra.
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_suporte_rodizio('dono@teste.com', false);
select pg_temp.servico();
select pg_temp.ok((pg_temp.chega('r14', 'b1@gmail.com', 'Sem ninguém')->>'responsavel') is null, 'sem ninguém no rodízio, fica sem responsável');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((public.admin_suporte_contagem()->>'sem_responsavel')::int = 1, 'contador de sem responsável');
select public.admin_suporte_rodizio('bruno@teste.com', true);
select pg_temp.admin();
select pg_temp.ok((select responsavel = 'bruno@teste.com' from public.suporte_conversas where contato_email = 'b1@gmail.com'), 'quem volta ao rodízio pega o que estava sem responsável');

rollback;
