-- "Falar com o suporte" dentro dos apps Cliente e Profissional (pedido de 21/11/2026).
--
-- As conversas do app entram na mesma caixa do suporte do painel (canal 'app'): mesmo
-- rodízio, prazos, cargos, notas internas e transferência. A equipe responde pelo painel
-- e a pessoa recebe um aviso (push) e vê a resposta no app.
--
-- "Equipe online": o painel avisa a cada minuto que a pessoa está com ele aberto
-- (admin_suporte_presenca). Online = alguém do rodízio do suporte com o painel aberto
-- nos últimos 3 minutos. Sem ninguém online, o app sugere mandar e-mail.

-- ---------------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------------
alter table public.suporte_conversas add column if not exists contato_viu_em timestamptz;
alter table public.equipe add column if not exists online_em timestamptz;

alter table public.suporte_conversas drop constraint if exists suporte_conversas_canal_check;
alter table public.suporte_conversas add constraint suporte_conversas_canal_check check (canal in ('email', 'whatsapp', 'app'));
alter table public.suporte_conversas drop constraint if exists suporte_conversas_contato_check;
alter table public.suporte_conversas add constraint suporte_conversas_contato_check check (
  (canal = 'email' and contato_email is not null)
  or (canal = 'whatsapp' and contato_telefone ~ '^\d{10,15}$')
  or canal = 'app');
create index if not exists suporte_conversas_app on public.suporte_conversas (usuario_id, ultima_mensagem_em desc) where canal = 'app';

-- ---------------------------------------------------------------------------
-- 2. Presença da equipe
-- ---------------------------------------------------------------------------
create or replace function public.admin_suporte_presenca()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.pode('emails') then return; end if;
  update public.equipe set online_em = now() where usuario_id = auth.uid();
end;
$$;

create or replace function public.suporte_equipe_online()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.equipe e join public.perfis p on p.id = e.usuario_id
    where p.e_admin and e.recebe_emails and e.online_em > now() - interval '3 minutes')
$$;

-- ---------------------------------------------------------------------------
-- 3. App: a conversa da pessoa com o suporte
-- ---------------------------------------------------------------------------
-- A conversa atual: a que não foi encerrada ou foi encerrada há menos de 3 dias.
create or replace function public.suporte_app_conversa_atual(p_usuario uuid)
returns bigint
language sql stable security definer
set search_path = public
as $$
  select id from public.suporte_conversas
  where canal = 'app' and usuario_id = p_usuario
    and (status <> 'encerrado' or encerrada_em > now() - interval '3 days')
  order by (status <> 'encerrado') desc, ultima_mensagem_em desc
  limit 1
$$;

-- Estado da tela "Falar com o suporte". p_marcar_lida: a pessoa está vendo a conversa.
create or replace function public.suporte_app_estado(p_marcar_lida boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_eu uuid := auth.uid();
  v public.suporte_conversas;
begin
  if v_eu is null then perform public.erro('sem_login', 'Entre na sua conta.'); end if;
  select * into v from public.suporte_conversas where id = public.suporte_app_conversa_atual(v_eu);
  if v.id is not null and p_marcar_lida then
    update public.suporte_conversas set contato_viu_em = now() where id = v.id;
  end if;
  return jsonb_build_object(
    'online', public.suporte_equipe_online(),
    'em_horario', public.em_horario_atendimento(),
    'horario', public.horario_atendimento(),
    'email', 'suporte@iservice.app.br',
    'nao_lidas', case when v.id is null or p_marcar_lida then 0 else (
      select count(*) from public.suporte_mensagens m
      where m.conversa_id = v.id and m.direcao = 'enviada' and m.envio = 'enviado'
        and m.criada_em > coalesce(v.contato_viu_em, '-infinity')) end,
    'conversa', case when v.id is null then null else jsonb_build_object(
      'id', v.id, 'protocolo', public.suporte_protocolo(v.id), 'status', v.status,
      'mensagens', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', m.id, 'minha', m.direcao = 'recebida', 'texto', m.texto,
          'autor', case when m.direcao = 'enviada' then split_part(coalesce(m.autor_nome, ''), ' ', 1) end,
          'criada_em', m.criada_em) order by m.criada_em, m.id)
        from public.suporte_mensagens m
        where m.conversa_id = v.id
          and (m.direcao = 'recebida' or (m.direcao = 'enviada' and m.envio = 'enviado'))), '[]')) end);
end;
$$;

-- Mensagem da pessoa para o suporte.
create or replace function public.suporte_app_enviar(p_texto text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_eu uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_perfil public.perfis;
  v_email text;
  v_tel text;
  v_conversa public.suporte_conversas;
  v_resp text;
begin
  if v_eu is null then perform public.erro('sem_login', 'Entre na sua conta.'); end if;
  if length(v_texto) = 0 then perform public.erro('texto_vazio', 'Escreva a mensagem.'); end if;
  if length(v_texto) > 2000 then perform public.erro('texto_longo', 'A mensagem pode ter até 2.000 caracteres.'); end if;
  if (select count(*) from public.suporte_mensagens m join public.suporte_conversas c on c.id = m.conversa_id
      where c.canal = 'app' and c.usuario_id = v_eu and m.direcao = 'recebida' and m.criada_em > now() - interval '10 minutes') >= 20 then
    perform public.erro('muitas_mensagens', 'Você mandou muitas mensagens seguidas. Espere alguns minutos.');
  end if;

  select * into v_perfil from public.perfis where id = v_eu;
  v_email := lower(coalesce(nullif(btrim(v_perfil.email), ''), (select email from auth.users where id = v_eu)));
  v_tel := nullif(regexp_replace(coalesce(v_perfil.telefone, ''), '\D', '', 'g'), '');
  if v_tel !~ '^\d{10,15}$' then v_tel := null; end if;

  select * into v_conversa from public.suporte_conversas where id = public.suporte_app_conversa_atual(v_eu) for update;

  if v_conversa.id is null then
    v_resp := public.suporte_proximo_responsavel();
    insert into public.suporte_conversas (canal, assunto, contato_email, contato_telefone, contato_nome, usuario_id, responsavel, atribuida_em)
    values ('app', case when coalesce(v_perfil.e_profissional, false) then 'Chat do app Profissional' else 'Chat do app Cliente' end,
      v_email, v_tel, nullif(btrim(v_perfil.nome), ''), v_eu, v_resp, case when v_resp is not null then now() end)
    returning * into v_conversa;
    if v_resp is not null then
      insert into public.suporte_mensagens (conversa_id, direcao, texto, criada_em)
      values (v_conversa.id, 'evento', 'Entregue para ' || coalesce(public.suporte_nome_equipe(v_resp), v_resp) || ' pelo rodízio', now() - interval '1 millisecond');
    end if;
  else
    if v_conversa.status = 'encerrado' then
      update public.suporte_conversas set status = 'aberto', encerrada_em = null, encerrada_por = null where id = v_conversa.id;
      insert into public.suporte_mensagens (conversa_id, direcao, texto)
      values (v_conversa.id, 'evento', 'Reaberta: o contato escreveu depois do encerramento');
    end if;
    if v_conversa.responsavel is null or not exists (
      select 1 from public.equipe e join public.perfis pf on pf.id = e.usuario_id
      where e.email = v_conversa.responsavel and pf.e_admin) then
      v_resp := public.suporte_proximo_responsavel();
      if v_resp is not null then
        update public.suporte_conversas set responsavel = v_resp, atribuida_em = now() where id = v_conversa.id;
        insert into public.suporte_mensagens (conversa_id, direcao, texto)
        values (v_conversa.id, 'evento', 'Entregue para ' || coalesce(public.suporte_nome_equipe(v_resp), v_resp) || ' pelo rodízio');
      end if;
    end if;
  end if;

  insert into public.suporte_mensagens (conversa_id, direcao, de_email, de_nome, para, texto, autor_id)
  values (v_conversa.id, 'recebida', v_email, nullif(btrim(v_perfil.nome), ''), '{}', v_texto, v_eu);

  update public.suporte_conversas
     set nao_lida = true, mensagens = mensagens + 1, ultima_mensagem_em = now(), contato_viu_em = now(),
         contato_nome = coalesce(nullif(btrim(v_perfil.nome), ''), contato_nome)
   where id = v_conversa.id;

  return public.suporte_app_estado(true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Painel: responder uma conversa do app
-- ---------------------------------------------------------------------------
create or replace function public.admin_suporte_responder_app(p_id bigint, p_texto text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  v_eu text := public.suporte_meu_email();
  v_nome text;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_msg bigint;
begin
  perform public.suporte_exigir_conversa(p_id);
  if v_eu is null then perform public.erro('sem_equipe', 'Sua conta não está na lista da equipe.'); end if;
  if length(v_texto) = 0 then perform public.erro('texto_vazio', 'Escreva a mensagem.'); end if;
  if length(v_texto) > 4000 then perform public.erro('texto_longo', 'A mensagem pode ter até 4.000 caracteres.'); end if;
  select * into v from public.suporte_conversas where id = p_id for update;
  if v.canal is distinct from 'app' then perform public.erro('canal_errado', 'Esta conversa não é do chat do app.'); end if;
  if v.usuario_id is null then perform public.erro('sem_conta', 'A conta desta pessoa foi excluída. Não dá para responder pelo app.'); end if;
  v_nome := public.suporte_nome_equipe(v_eu);

  update public.suporte_conversas set
    status = case when status = 'aberto' then 'em_atendimento' else status end,
    responsavel = coalesce(responsavel, v_eu),
    atribuida_em = case when responsavel is null then now() else atribuida_em end,
    nao_lida = false
  where id = v.id;
  if v.status = 'aberto' then perform public.suporte_evento(v.id, 'Em atendimento'); end if;
  insert into public.suporte_mensagens (conversa_id, direcao, de_nome, para, texto, autor_id, autor_nome, envio)
  values (v.id, 'enviada', v_nome, '{}', v_texto, auth.uid(), v_nome, 'enviado')
  returning id into v_msg;
  update public.suporte_conversas set mensagens = mensagens + 1, ultima_mensagem_em = now() where id = v.id;

  perform public.notificar(v.usuario_id, 'suporte', 'Resposta do suporte iService',
    left(regexp_replace(v_texto, '\s+', ' ', 'g'), 140), jsonb_build_object('tela', 'suporte'));

  return jsonb_build_object('enviado', true, 'conversa_id', v.id, 'mensagem_id', v_msg);
end;
$$;

-- E-mail não sai para conversa do app (nem de WhatsApp): a função responder-suporte recusa.
do $$
declare
  r record;
  v_def text;
begin
  for r in select * from (values
    ('admin_suporte_preparar_envio(bigint,text,text,text)'),
    ('admin_suporte_preparar_reenvio(bigint)')) as t(funcao)
  loop
    v_def := replace(pg_get_functiondef(('public.' || r.funcao)::regprocedure), E'\r\n', E'\n');
    if position('canal <> ''email'')' in v_def) > 0 then
      continue; -- já aplicado
    end if;
    if position('canal = ''whatsapp'')' in v_def) = 0 then
      raise exception 'A função % está diferente do esperado.', r.funcao;
    end if;
    v_def := replace(v_def, 'canal = ''whatsapp'')', 'canal <> ''email'')');
    v_def := replace(v_def, 'Esta conversa é de WhatsApp. Responda pelo WhatsApp.', 'Esta conversa não é de e-mail. Responda pelo canal dela.');
    v_def := replace(v_def, 'Esta conversa é de WhatsApp. Reenvie pelo WhatsApp.', 'Esta conversa não é de e-mail. Reenvie pelo canal dela.');
    execute v_def;
  end loop;
end;
$$;

-- A conversa no painel mostra quando a pessoa viu as respostas no app.
do $$
declare
  v_def text := replace(pg_get_functiondef('public.admin_suporte_conversa(bigint)'::regprocedure), E'\r\n', E'\n');
  v_antes text := '''canal'', v.canal, ';
begin
  if position('contato_viu_em' in v_def) = 0 then
    if position(v_antes in v_def) = 0 then
      raise exception 'A função admin_suporte_conversa está diferente do esperado.';
    end if;
    execute replace(v_def, v_antes, v_antes || '''contato_viu_em'', v.contato_viu_em, ''equipe_online'', public.suporte_equipe_online(), ');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Permissões
-- ---------------------------------------------------------------------------
revoke all on function public.suporte_equipe_online() from public, anon, authenticated;
revoke all on function public.suporte_app_conversa_atual(uuid) from public, anon, authenticated;
revoke all on function public.suporte_app_estado(boolean) from public, anon;
revoke all on function public.suporte_app_enviar(text) from public, anon;
revoke all on function public.admin_suporte_presenca() from public, anon;
revoke all on function public.admin_suporte_responder_app(bigint, text) from public, anon;
grant execute on function public.suporte_app_estado(boolean) to authenticated;
grant execute on function public.suporte_app_enviar(text) to authenticated;
grant execute on function public.admin_suporte_presenca() to authenticated;
grant execute on function public.admin_suporte_responder_app(bigint, text) to authenticated;
