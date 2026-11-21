-- WhatsApp do atendimento dentro do painel (API oficial da Meta, WhatsApp Cloud API).
--
-- As mensagens de WhatsApp entram na mesma caixa do suporte dos e-mails: mesmo rodízio,
-- mesmos prazos, mesmas permissões dos cargos, notas internas e transferência.
-- Ligações continuam no celular (a API não atende ligações).
--
-- Fica PRONTO e DESLIGADO: app_config 'whatsapp_ativo' = false e sem os segredos
-- WHATSAPP_* na função "whatsapp". Ligar só depois do CNPJ e da verificação da empresa
-- na Meta (passo a passo em /mnt/project-files/whatsapp/ATIVAR-whatsapp.md).
--
-- Regra da Meta: a equipe só pode escrever texto livre até 24 horas depois da última
-- mensagem do cliente ("janela de atendimento"). Fora dela, só modelo aprovado pela Meta.

-- ---------------------------------------------------------------------------
-- 1. Configuração
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao) values
  ('whatsapp_ativo', 'false', 'WhatsApp do atendimento no painel (API oficial da Meta). Ligar só depois do CNPJ e da verificação na Meta.'),
  ('whatsapp_numero', '""', 'Número do WhatsApp Business do atendimento, só dígitos com 55 e DDD (ex.: 5561999998888).'),
  ('whatsapp_modelo_retomar', '""', 'Nome do modelo aprovado na Meta para voltar a falar com o cliente depois de 24 horas (opcional).')
on conflict (chave) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Tabelas: canal e telefone na conversa; entregue e lida na mensagem
-- ---------------------------------------------------------------------------
alter table public.suporte_conversas add column if not exists canal text not null default 'email';
alter table public.suporte_conversas add column if not exists contato_telefone text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'suporte_conversas_canal_check') then
    alter table public.suporte_conversas add constraint suporte_conversas_canal_check check (canal in ('email', 'whatsapp'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'suporte_conversas_contato_check') then
    alter table public.suporte_conversas add constraint suporte_conversas_contato_check check (
      (canal = 'email' and contato_email is not null)
      or (canal = 'whatsapp' and contato_telefone ~ '^\d{10,15}$'));
  end if;
end;
$$;
-- Conversa de WhatsApp não tem e-mail.
alter table public.suporte_conversas alter column contato_email drop not null;
create index if not exists suporte_conversas_telefone on public.suporte_conversas (contato_telefone) where contato_telefone is not null;

alter table public.suporte_mensagens add column if not exists entregue_em timestamptz;
alter table public.suporte_mensagens add column if not exists lida_em timestamptz;
create index if not exists suporte_mensagens_enviada_externo on public.suporte_mensagens (id_externo) where direcao = 'enviada' and id_externo is not null;

-- ---------------------------------------------------------------------------
-- 3. Utilidades
-- ---------------------------------------------------------------------------
-- Formas do mesmo celular brasileiro: com e sem 55, com e sem o 9 da frente.
-- O WhatsApp às vezes manda o número antigo, sem o 9 (556199998888).
create or replace function public.suporte_formas_telefone(p_tel text)
returns text[]
language plpgsql immutable
set search_path = public
as $$
declare
  t text := regexp_replace(coalesce(p_tel, ''), '\D', '', 'g');
  nacional text;
  formas text[] := '{}';
begin
  if t = '' then return formas; end if;
  nacional := case when t like '55%' and length(t) in (12, 13) then substr(t, 3) else t end;
  formas := array[t, nacional, '55' || nacional];
  if length(nacional) = 10 and substr(nacional, 3, 1) in ('6', '7', '8', '9') then
    formas := formas || array[substr(nacional, 1, 2) || '9' || substr(nacional, 3), '55' || substr(nacional, 1, 2) || '9' || substr(nacional, 3)];
  elsif length(nacional) = 11 and substr(nacional, 3, 1) = '9' then
    formas := formas || array[substr(nacional, 1, 2) || substr(nacional, 4), '55' || substr(nacional, 1, 2) || substr(nacional, 4)];
  end if;
  return formas;
end;
$$;

-- Até quando a equipe pode responder com texto livre (24 h depois da última mensagem do cliente).
create or replace function public.suporte_janela_whatsapp(p_conversa bigint)
returns timestamptz
language sql stable security definer
set search_path = public
as $$
  select max(criada_em) + interval '24 hours' from public.suporte_mensagens
  where conversa_id = p_conversa and direcao = 'recebida'
$$;

-- ---------------------------------------------------------------------------
-- 4. Entrada de WhatsApp (só a função "whatsapp", com a chave de serviço)
-- ---------------------------------------------------------------------------
-- p: { id_externo (wamid), telefone (wa_id), nome, texto, tipo, anexos[] }
create or replace function public.suporte_receber_whatsapp(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_tel text := regexp_replace(coalesce(p->>'telefone', ''), '\D', '', 'g');
  v_nome text := nullif(btrim(p->>'nome'), '');
  v_conversa public.suporte_conversas;
  v_existente bigint;
  v_nova boolean := false;
  v_resp text;
  v_usuario uuid;
begin
  if v_tel !~ '^\d{10,15}$' then
    return jsonb_build_object('ignorado', 'telefone inválido');
  end if;

  -- A Meta reenvia o mesmo aviso quando não recebe resposta rápida.
  select conversa_id into v_existente from public.suporte_mensagens
  where direcao = 'recebida' and id_externo = p->>'id_externo';
  if v_existente is not null then
    return jsonb_build_object('conversa_id', v_existente, 'repetido', true);
  end if;

  -- Mesma conversa enquanto não for encerrada; encerrada há menos de 3 dias é reaberta.
  select * into v_conversa from public.suporte_conversas
  where canal = 'whatsapp' and contato_telefone = v_tel
    and (status <> 'encerrado' or encerrada_em > now() - interval '3 days')
  order by (status <> 'encerrado') desc, ultima_mensagem_em desc
  limit 1 for update;

  if v_conversa.id is null then
    select id into v_usuario from public.perfis
    where telefone = any (public.suporte_formas_telefone(v_tel)) limit 1;
    v_resp := public.suporte_proximo_responsavel();
    insert into public.suporte_conversas (canal, assunto, contato_email, contato_telefone, contato_nome, usuario_id, responsavel, atribuida_em)
    values ('whatsapp', 'WhatsApp', null, v_tel, v_nome, v_usuario, v_resp, case when v_resp is not null then now() end)
    returning * into v_conversa;
    v_nova := true;
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

  insert into public.suporte_mensagens (conversa_id, direcao, de_nome, para, texto, id_externo, anexos)
  values (v_conversa.id, 'recebida', v_nome, '{}', left(coalesce(p->>'texto', ''), 20000), p->>'id_externo',
    coalesce(p->'anexos', '[]'))
  on conflict do nothing;

  update public.suporte_conversas
     set nao_lida = true, mensagens = mensagens + 1, ultima_mensagem_em = now(),
         contato_nome = coalesce(contato_nome, v_nome)
   where id = v_conversa.id;

  return jsonb_build_object('conversa_id', v_conversa.id, 'nova', v_nova,
    'protocolo', public.suporte_protocolo(v_conversa.id),
    'responsavel', (select responsavel from public.suporte_conversas where id = v_conversa.id));
end;
$$;

-- Resposta automática de fora do horário, pelo WhatsApp: uma vez por conversa nova.
create or replace function public.suporte_resposta_automatica_whatsapp(p_conversa bigint)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c public.suporte_conversas;
begin
  select * into c from public.suporte_conversas where id = p_conversa and canal = 'whatsapp';
  if c.id is null or c.mensagens > 1 or public.em_horario_atendimento() then
    return jsonb_build_object('enviar', false);
  end if;
  if exists (select 1 from public.suporte_mensagens where conversa_id = c.id and direcao = 'evento' and texto like 'Resposta automática%') then
    return jsonb_build_object('enviar', false);
  end if;
  insert into public.suporte_mensagens (conversa_id, direcao, texto)
  values (c.id, 'evento', 'Resposta automática de fora do horário enviada.');
  return jsonb_build_object('enviar', true, 'para', c.contato_telefone, 'nome', c.contato_nome,
    'protocolo', public.suporte_protocolo(c.id), 'horario', public.horario_atendimento());
end;
$$;

-- Entregue, lida ou falhou (avisos da Meta pelo webhook).
create or replace function public.suporte_whatsapp_status(p_id_externo text, p_status text, p_erro text default null)
returns void
language sql security definer
set search_path = public
as $$
  update public.suporte_mensagens set
    envio = case when p_status = 'failed' then 'erro' else 'enviado' end,
    erro = case when p_status = 'failed' then left(coalesce(p_erro, 'O WhatsApp não entregou a mensagem.'), 500) else erro end,
    entregue_em = case when p_status in ('delivered', 'read') then coalesce(entregue_em, now()) else entregue_em end,
    lida_em = case when p_status = 'read' then coalesce(lida_em, now()) else lida_em end
  where direcao = 'enviada' and id_externo = p_id_externo
$$;

-- ---------------------------------------------------------------------------
-- 5. Painel: preparar o envio de uma resposta de WhatsApp
-- ---------------------------------------------------------------------------
-- Chamada pela função "whatsapp" com o login de quem escreveu (mesmas regras dos e-mails).
-- p_reenviar: id de uma resposta que falhou, para tentar de novo.
create or replace function public.admin_suporte_preparar_whatsapp(p_id bigint, p_texto text default null, p_reenviar bigint default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  m public.suporte_mensagens;
  v_eu text := public.suporte_meu_email();
  v_nome text;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_janela timestamptz;
  v_msg bigint;
begin
  perform public.exigir_permissao('emails');
  if p_reenviar is not null then
    select * into m from public.suporte_mensagens where id = p_reenviar and direcao = 'enviada' for update;
    if m.id is null then perform public.erro('nao_encontrado', 'Mensagem não encontrada.'); end if;
    if m.envio is distinct from 'erro' then perform public.erro('ja_enviada', 'Esta mensagem já foi enviada.'); end if;
    p_id := m.conversa_id;
    v_texto := m.texto;
  end if;
  perform public.suporte_exigir_conversa(p_id);
  if not public.cfg_bool('whatsapp_ativo', false) then
    perform public.erro('whatsapp_desligado', 'O WhatsApp do atendimento ainda não foi ligado.');
  end if;
  if v_eu is null then perform public.erro('sem_equipe', 'Sua conta não está na lista da equipe.'); end if;
  if length(v_texto) = 0 then perform public.erro('texto_vazio', 'Escreva a mensagem.'); end if;
  if length(v_texto) > 4000 then perform public.erro('texto_longo', 'O WhatsApp aceita até 4.000 caracteres por mensagem.'); end if;

  select * into v from public.suporte_conversas where id = p_id for update;
  if v.canal is distinct from 'whatsapp' then perform public.erro('canal_errado', 'Esta conversa é de e-mail.'); end if;
  v_janela := public.suporte_janela_whatsapp(v.id);
  if v_janela is null or v_janela < now() then
    perform public.erro('janela_fechada', 'Passaram 24 horas desde a última mensagem do cliente. Pela regra do WhatsApp, só dá para voltar a falar com um modelo aprovado, ou espere o cliente escrever de novo.');
  end if;
  v_nome := public.suporte_nome_equipe(v_eu);

  if m.id is not null then
    update public.suporte_mensagens set envio = 'enviando', erro = null where id = m.id;
    v_msg := m.id;
  else
    update public.suporte_conversas set
      status = case when status = 'aberto' then 'em_atendimento' else status end,
      responsavel = coalesce(responsavel, v_eu),
      atribuida_em = case when responsavel is null then now() else atribuida_em end,
      nao_lida = false
    where id = v.id;
    if v.status = 'aberto' then perform public.suporte_evento(v.id, 'Em atendimento'); end if;
    insert into public.suporte_mensagens (conversa_id, direcao, de_nome, para, texto, autor_id, autor_nome, envio)
    values (v.id, 'enviada', v_nome, array[v.contato_telefone], v_texto, auth.uid(), v_nome, 'enviando')
    returning id into v_msg;
    update public.suporte_conversas set mensagens = mensagens + 1, ultima_mensagem_em = now() where id = v.id;
  end if;

  return jsonb_build_object('mensagem_id', v_msg, 'conversa_id', v.id, 'protocolo', public.suporte_protocolo(v.id),
    'para', v.contato_telefone, 'texto', v_texto, 'autor_nome', v_nome);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Painel: lista e conversa mostram o canal; e-mail não vai para conversa de WhatsApp
-- ---------------------------------------------------------------------------
-- A lista ganha canal e telefone (muda o formato do resultado, por isso é recriada).
drop function if exists public.admin_suporte_conversas(text, text, text, integer, integer);
create or replace function public.admin_suporte_conversas(
  p_status text default 'aberto', p_quem text default 'meus', p_busca text default null,
  p_limite integer default 50, p_deslocamento integer default 0, p_canal text default null)
returns table (
  id bigint, protocolo text, assunto text, contato_email text, contato_nome text, usuario_id uuid, foto_url text,
  e_profissional boolean, status text, responsavel text, responsavel_nome text, nao_lida boolean, mensagens integer,
  criada_em timestamptz, ultima_mensagem_em timestamptz, previa text, ultima_direcao text, total bigint,
  canal text, contato_telefone text)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_eu text := public.suporte_meu_email();
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_digitos text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform public.exigir_permissao('emails');
  if not public.pode('emails_todos') and coalesce(p_quem, 'todos') not in ('meus', 'sem_responsavel') then
    p_quem := 'meus_e_livres';
  end if;
  return query
  with base as (
    select c.* from public.suporte_conversas c
    where (p_status is null or p_status = 'todos' or c.status = p_status)
      and (p_canal is null or p_canal = 'todos' or c.canal = p_canal)
      and (coalesce(p_quem, 'todos') = 'todos'
        or (p_quem = 'meus' and c.responsavel = v_eu)
        or (p_quem = 'sem_responsavel' and c.responsavel is null)
        or (p_quem = 'meus_e_livres' and (c.responsavel = v_eu or c.responsavel is null))
        or (p_quem not in ('meus', 'sem_responsavel', 'meus_e_livres') and c.responsavel = lower(p_quem)))
      and (v_busca is null
        or c.contato_email ilike '%' || v_busca || '%'
        or (v_digitos is not null and length(v_digitos) >= 4 and c.contato_telefone like '%' || v_digitos || '%')
        or c.contato_nome ilike '%' || v_busca || '%'
        or c.assunto ilike '%' || v_busca || '%'
        or public.suporte_protocolo(c.id) ilike '%' || v_busca || '%'
        or exists (select 1 from public.suporte_mensagens m where m.conversa_id = c.id and m.direcao in ('recebida', 'enviada') and m.texto ilike '%' || v_busca || '%'))
  )
  select b.id, public.suporte_protocolo(b.id), b.assunto, b.contato_email,
    coalesce(nullif(btrim(pf.nome), ''), b.contato_nome), b.usuario_id, pf.foto_url, coalesce(pf.e_profissional, false),
    b.status, b.responsavel, public.suporte_nome_equipe(b.responsavel), b.nao_lida, b.mensagens, b.criada_em, b.ultima_mensagem_em,
    left(regexp_replace(coalesce(u.texto, ''), '\s+', ' ', 'g'), 160), u.direcao,
    count(*) over (), b.canal, b.contato_telefone
  from base b
  left join public.perfis pf on pf.id = b.usuario_id
  left join lateral (
    select m.texto, m.direcao from public.suporte_mensagens m
    where m.conversa_id = b.id and m.direcao in ('recebida', 'enviada')
    order by m.criada_em desc limit 1
  ) u on true
  order by case when b.status = 'encerrado' then b.ultima_mensagem_em end desc nulls last,
           b.nao_lida desc, b.ultima_mensagem_em asc
  limit greatest(1, least(coalesce(p_limite, 50), 200)) offset greatest(0, coalesce(p_deslocamento, 0));
end;
$$;
revoke all on function public.admin_suporte_conversas(text, text, text, integer, integer, text) from public, anon;
grant execute on function public.admin_suporte_conversas(text, text, text, integer, integer, text) to authenticated;

create or replace function public.admin_suporte_conversa(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  v_eu text := public.suporte_meu_email();
begin
  perform public.suporte_exigir_conversa(p_id);
  select * into v from public.suporte_conversas where id = p_id;
  if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  -- Abrir a conversa marca como lida para quem é o responsável.
  if v.nao_lida and v.responsavel = v_eu then
    update public.suporte_conversas set nao_lida = false where id = p_id;
    v.nao_lida := false;
  end if;
  return jsonb_build_object(
    'id', v.id, 'protocolo', public.suporte_protocolo(v.id), 'assunto', v.assunto,
    'canal', v.canal, 'contato_telefone', v.contato_telefone,
    'janela_ate', case when v.canal = 'whatsapp' then public.suporte_janela_whatsapp(v.id) end,
    'whatsapp_ativo', public.cfg_bool('whatsapp_ativo', false),
    'contato_email', v.contato_email, 'contato_nome', v.contato_nome, 'status', v.status,
    'responsavel', v.responsavel, 'responsavel_nome', public.suporte_nome_equipe(v.responsavel),
    'nao_lida', v.nao_lida, 'criada_em', v.criada_em, 'ultima_mensagem_em', v.ultima_mensagem_em,
    'encerrada_em', v.encerrada_em, 'eu', v_eu,
    'pessoa', (select jsonb_build_object('id', pf.id, 'nome', pf.nome, 'foto_url', pf.foto_url, 'e_profissional', pf.e_profissional,
                 'telefone', pf.telefone, 'pedidos', (select count(*) from public.pedidos pd where pd.cliente_id = pf.id or pd.profissional_id = pf.id))
               from public.perfis pf where pf.id = v.usuario_id),
    'outras', (select count(*) from public.suporte_conversas o where o.id <> v.id
                 and ((v.contato_email is not null and o.contato_email = v.contato_email)
                   or (v.contato_telefone is not null and o.contato_telefone = v.contato_telefone)
                   or (v.usuario_id is not null and o.usuario_id = v.usuario_id))),
    'mensagens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'direcao', m.direcao, 'de_email', m.de_email, 'de_nome', m.de_nome, 'para', m.para, 'cc', m.cc,
        'assunto', m.assunto, 'texto', m.texto, 'tem_html', m.html is not null, 'autor_nome', m.autor_nome,
        'envio', m.envio, 'erro', m.erro, 'anexos', m.anexos, 'criada_em', m.criada_em,
        'entregue_em', m.entregue_em, 'lida_em', m.lida_em) order by m.criada_em, m.id)
      from public.suporte_mensagens m where m.conversa_id = v.id), '[]'));
end;
$$;

-- Responder por e-mail numa conversa de WhatsApp não faz sentido: a função responder-suporte recusa.
do $$
declare
  r record;
  v_def text;
begin
  for r in select * from (values
    ('admin_suporte_preparar_envio(bigint,text,text,text)',
     'if p_id is not null then perform public.suporte_exigir_conversa(p_id); end if;',
     'if p_id is not null then perform public.suporte_exigir_conversa(p_id); end if;
  if exists (select 1 from public.suporte_conversas where id = p_id and canal = ''whatsapp'') then
    perform public.erro(''canal_errado'', ''Esta conversa é de WhatsApp. Responda pelo WhatsApp.'');
  end if;'),
    ('admin_suporte_preparar_reenvio(bigint)',
     'perform public.suporte_exigir_conversa((select conversa_id from public.suporte_mensagens where id = p_mensagem));',
     'perform public.suporte_exigir_conversa((select conversa_id from public.suporte_mensagens where id = p_mensagem));
  if exists (select 1 from public.suporte_mensagens sm join public.suporte_conversas sc on sc.id = sm.conversa_id
             where sm.id = p_mensagem and sc.canal = ''whatsapp'') then
    perform public.erro(''canal_errado'', ''Esta conversa é de WhatsApp. Reenvie pelo WhatsApp.'');
  end if;')
  ) as t(funcao, antes, depois)
  loop
    v_def := replace(pg_get_functiondef(('public.' || r.funcao)::regprocedure), E'\r\n', E'\n');
    if position('canal_errado' in v_def) > 0 then
      continue; -- já aplicado
    end if;
    if position(r.antes in v_def) = 0 then
      raise exception 'A função % está diferente do esperado.', r.funcao;
    end if;
    execute replace(v_def, r.antes, r.depois);
  end loop;
end;
$$;

-- A resposta automática por e-mail não vale para conversa de WhatsApp (não tem e-mail).
do $$
declare
  v_def text := replace(pg_get_functiondef('public.suporte_resposta_automatica(bigint)'::regprocedure), E'\r\n', E'\n');
  v_antes text := 'if c.id is null or c.mensagens > 1 or public.em_horario_atendimento() then';
begin
  if position('c.contato_email is null' in v_def) = 0 then
    if position(v_antes in v_def) = 0 then
      raise exception 'A função suporte_resposta_automatica está diferente do esperado.';
    end if;
    execute replace(v_def, v_antes, 'if c.id is null or c.contato_email is null or c.mensagens > 1 or public.em_horario_atendimento() then');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Permissões
-- ---------------------------------------------------------------------------
revoke all on function public.suporte_formas_telefone(text) from public, anon, authenticated;
revoke all on function public.suporte_janela_whatsapp(bigint) from public, anon, authenticated;
revoke all on function public.suporte_receber_whatsapp(jsonb) from public, anon, authenticated;
revoke all on function public.suporte_resposta_automatica_whatsapp(bigint) from public, anon, authenticated;
revoke all on function public.suporte_whatsapp_status(text, text, text) from public, anon, authenticated;
grant execute on function public.suporte_receber_whatsapp(jsonb) to service_role;
grant execute on function public.suporte_resposta_automatica_whatsapp(bigint) to service_role;
grant execute on function public.suporte_whatsapp_status(text, text, text) to service_role;
grant execute on function public.cfg_bool(text, boolean) to service_role;

revoke all on function public.admin_suporte_preparar_whatsapp(bigint, text, bigint) from public, anon;
grant execute on function public.admin_suporte_preparar_whatsapp(bigint, text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Celular nos "Dados de acesso" da equipe (pedido de 20/11/2026)
-- ---------------------------------------------------------------------------
-- Mesmas regras do nome e do e-mail: a própria pessoa ou quem tem cargo acima dela.
-- Fica no perfil (o mesmo celular do app). Trocar o número tira a verificação por SMS.
create or replace function public.admin_editar_celular_membro(p_email text, p_telefone text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
  v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_antes text;
begin
  perform public.exigir_admin();
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, ''))) for update;
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  if not public.pode_editar_membro(v) then
    perform public.erro('sem_permissao', 'Só a própria pessoa ou quem tem cargo acima dela muda estes dados.');
  end if;
  if v.usuario_id is null then
    perform public.erro('sem_conta', 'A pessoa ainda não criou a conta. O celular pode ser salvo depois do primeiro acesso.');
  end if;
  -- Aceita com ou sem o 55 do Brasil; guarda DDD + número, como o app.
  if v_tel ~ '^55\d{10,11}$' then v_tel := substr(v_tel, 3); end if;
  if v_tel = '' then
    v_tel := null;
  elsif v_tel !~ '^\d{10,11}$' then
    perform public.erro('telefone_invalido', 'Digite o celular com DDD, por exemplo (61) 99999-8888.');
  end if;
  select telefone into v_antes from public.perfis where id = v.usuario_id;
  if v_antes is not distinct from v_tel then return; end if;
  update public.perfis set telefone = v_tel where id = v.usuario_id;
  perform public.registrar_acao('editar_equipe', v.usuario_id::text,
    jsonb_build_object('celular_antes', v_antes, 'celular', v_tel));
end;
$$;
revoke all on function public.admin_editar_celular_membro(text, text) from public, anon;
grant execute on function public.admin_editar_celular_membro(text, text) to authenticated;
