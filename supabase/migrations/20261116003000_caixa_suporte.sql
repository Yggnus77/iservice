-- Caixa de e-mail do suporte dentro do painel (16/11/2026).
--
-- Como funciona:
--  1. Todo e-mail que chega em qualquer endereço @iservice.app.br (suporte@, nao-responda@ e
--     as respostas aos e-mails automáticos) passa pelo Resend, que avisa a função receber-email.
--  2. A função guarda a mensagem aqui (suporte_receber). Se for resposta de uma conversa que já
--     existe, entra nela; se não, abre uma conversa nova e entrega, em rodízio, para a próxima
--     pessoa da equipe que recebe e-mails (quem recebeu há mais tempo vai primeiro).
--  3. A equipe acompanha em três situações: Em aberto, Em atendimento e Encerrado.
--     Responder pelo painel (função responder-suporte) leva a conversa para Em atendimento.
--     Se o cliente responde uma conversa encerrada, ela volta para Em aberto com a mesma pessoa.
--  4. Quem sai da equipe tem as conversas não encerradas redistribuídas no rodízio.

-- ---------------------------------------------------------------------------
-- 1. Rodízio na equipe
-- ---------------------------------------------------------------------------
alter table public.equipe add column if not exists recebe_emails boolean not null default true;
alter table public.equipe add column if not exists ultima_atribuicao timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Tabelas
-- ---------------------------------------------------------------------------
create table if not exists public.suporte_conversas (
  id bigint generated always as identity primary key,
  assunto text not null default '(sem assunto)',
  contato_email text not null check (contato_email = lower(btrim(contato_email))),
  contato_nome text,
  usuario_id uuid references public.perfis (id) on delete set null,
  status text not null default 'aberto' check (status in ('aberto', 'em_atendimento', 'encerrado')),
  responsavel text references public.equipe (email) on delete set null,
  atribuida_em timestamptz,
  nao_lida boolean not null default true,
  mensagens integer not null default 0,
  criada_em timestamptz not null default now(),
  ultima_mensagem_em timestamptz not null default now(),
  encerrada_em timestamptz,
  encerrada_por uuid references public.perfis (id) on delete set null
);
create index if not exists suporte_conversas_status on public.suporte_conversas (status, ultima_mensagem_em desc);
create index if not exists suporte_conversas_responsavel on public.suporte_conversas (responsavel, status);
create index if not exists suporte_conversas_contato on public.suporte_conversas (contato_email);

-- direcao: recebida (do cliente), enviada (pela equipe), nota (interna, o cliente não vê),
-- evento (registro automático: quem assumiu, transferiu, encerrou).
create table if not exists public.suporte_mensagens (
  id bigint generated always as identity primary key,
  conversa_id bigint not null references public.suporte_conversas (id) on delete cascade,
  direcao text not null check (direcao in ('recebida', 'enviada', 'nota', 'evento')),
  de_email text,
  de_nome text,
  para text[] not null default '{}',
  cc text[] not null default '{}',
  assunto text,
  texto text,
  html text,
  message_id text,
  referencias text[] not null default '{}',
  id_externo text,
  autor_id uuid references public.perfis (id) on delete set null,
  autor_nome text,
  envio text check (envio in ('enviando', 'enviado', 'erro')),
  erro text,
  anexos jsonb not null default '[]',
  criada_em timestamptz not null default now()
);
create index if not exists suporte_mensagens_conversa on public.suporte_mensagens (conversa_id, criada_em);
create unique index if not exists suporte_mensagens_message_id on public.suporte_mensagens (message_id) where message_id is not null;
create unique index if not exists suporte_mensagens_recebida on public.suporte_mensagens (id_externo) where direcao = 'recebida' and id_externo is not null;

alter table public.suporte_conversas enable row level security;
alter table public.suporte_mensagens enable row level security;
revoke all on public.suporte_conversas, public.suporte_mensagens from anon, authenticated;
-- Leitura e escrita só pelas funções abaixo.

-- Anexos recebidos: privados, só a equipe abre (link temporário no painel).
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('suporte', 'suporte', false, 15 * 1024 * 1024)
    on conflict (id) do nothing;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'suporte: equipe lê') then
      execute $p$create policy "suporte: equipe lê" on storage.objects for select to authenticated
        using (bucket_id = 'suporte' and public.e_admin())$p$;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Utilidades
-- ---------------------------------------------------------------------------
create or replace function public.suporte_protocolo(p_id bigint)
returns text
language sql immutable
as $$ select 'S-' || lpad(p_id::text, 5, '0') $$;

-- Próxima pessoa do rodízio: com acesso, que recebe e-mails, e que recebeu há mais tempo.
-- Trava a linha para dois e-mails ao mesmo tempo não irem para a mesma pessoa.
create or replace function public.suporte_proximo_responsavel()
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select e.email into v_email
  from public.equipe e
  join public.perfis p on p.id = e.usuario_id
  where e.recebe_emails and p.e_admin
  order by e.ultima_atribuicao nulls first, e.convidado_em, e.email
  limit 1
  for update of e;
  if v_email is not null then
    update public.equipe set ultima_atribuicao = clock_timestamp() where email = v_email;
  end if;
  return v_email;
end;
$$;

create or replace function public.suporte_evento(p_conversa bigint, p_texto text)
returns void
language sql security definer
set search_path = public
as $$
  insert into public.suporte_mensagens (conversa_id, direcao, texto, autor_id, autor_nome)
  values (p_conversa, 'evento', p_texto, auth.uid(),
    (select coalesce(nullif(btrim(p.nome), ''), e.nome) from public.equipe e left join public.perfis p on p.id = e.usuario_id
      where e.usuario_id = auth.uid() limit 1))
$$;

create or replace function public.suporte_nome_equipe(p_email text)
returns text
language sql stable security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(p.nome), ''), e.nome) from public.equipe e
  left join public.perfis p on p.id = e.usuario_id where e.email = p_email
$$;

-- Entrega para o rodízio as conversas não encerradas que estão sem responsável.
create or replace function public.suporte_distribuir_pendentes()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v record;
  v_resp text;
  n integer := 0;
begin
  for v in select id from public.suporte_conversas where responsavel is null and status <> 'encerrado' order by criada_em for update loop
    v_resp := public.suporte_proximo_responsavel();
    exit when v_resp is null;
    update public.suporte_conversas set responsavel = v_resp, atribuida_em = now(), nao_lida = true where id = v.id;
    insert into public.suporte_mensagens (conversa_id, direcao, texto)
    values (v.id, 'evento', 'Entregue para ' || coalesce(public.suporte_nome_equipe(v_resp), v_resp) || ' pelo rodízio');
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Quem sai da equipe: as conversas não encerradas dele voltam para o rodízio.
-- (A chave estrangeira já deixou o responsável vazio antes deste gatilho.)
create or replace function public.suporte_saiu_da_equipe()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.suporte_distribuir_pendentes();
  return null;
exception when others then
  return null;
end;
$$;

drop trigger if exists suporte_saiu_da_equipe on public.equipe;
create trigger suporte_saiu_da_equipe after delete on public.equipe
  for each row execute function public.suporte_saiu_da_equipe();

-- Quem entra na equipe (confirmou o e-mail) já pega o que estiver sem responsável.
create or replace function public.suporte_entrou_na_equipe()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.e_admin and not coalesce(old.e_admin, false) then
    perform public.suporte_distribuir_pendentes();
  end if;
  return null;
exception when others then
  return null;
end;
$$;

drop trigger if exists suporte_entrou_na_equipe on public.perfis;
create trigger suporte_entrou_na_equipe after update of e_admin on public.perfis
  for each row execute function public.suporte_entrou_na_equipe();

-- ---------------------------------------------------------------------------
-- 4. Entrada de e-mail (só a função receber-email, com a chave de serviço)
-- ---------------------------------------------------------------------------
-- p: { id_externo, message_id, referencias[], de_email, de_nome, para[], cc[], assunto, texto, html, anexos[] }
create or replace function public.suporte_receber(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_de text := lower(btrim(coalesce(p->>'de_email', '')));
  v_assunto text := left(coalesce(nullif(btrim(p->>'assunto'), ''), '(sem assunto)'), 300);
  v_refs text[] := coalesce(array(select jsonb_array_elements_text(coalesce(p->'referencias', '[]'))), '{}');
  v_conversa public.suporte_conversas;
  v_existente bigint;
  v_nova boolean := false;
  v_resp text;
  v_protocolo bigint;
  v_usuario uuid;
begin
  if v_de !~ '^[^@\s]+@[^@\s]+$' then
    return jsonb_build_object('ignorado', 'remetente inválido');
  end if;
  -- Nossos próprios envios (cópias, avisos de entrega) não viram conversa.
  if v_de like '%@iservice.app.br' then
    return jsonb_build_object('ignorado', 'remetente interno');
  end if;

  -- O mesmo e-mail chegando duas vezes (o Resend reenvia quando não recebe resposta).
  select conversa_id into v_existente from public.suporte_mensagens
  where direcao = 'recebida' and id_externo = p->>'id_externo';
  if v_existente is not null then
    return jsonb_build_object('conversa_id', v_existente, 'repetido', true);
  end if;

  -- 1º: resposta a uma mensagem nossa (cabeçalhos In-Reply-To / References).
  if array_length(v_refs, 1) > 0 then
    select c.* into v_conversa from public.suporte_mensagens m
    join public.suporte_conversas c on c.id = m.conversa_id
    where m.message_id = any (v_refs)
    order by m.criada_em desc limit 1
    for update of c;
  end if;
  -- 2º: o protocolo no assunto ("[S-00012]"), desde que venha do mesmo contato.
  if v_conversa.id is null then
    v_protocolo := nullif(substring(v_assunto from '\[S-0*(\d+)\]'), '')::bigint;
    if v_protocolo is not null then
      select * into v_conversa from public.suporte_conversas
      where id = v_protocolo and contato_email = v_de for update;
    end if;
  end if;

  if v_conversa.id is null then
    select id into v_usuario from public.perfis where lower(email) = v_de limit 1;
    v_resp := public.suporte_proximo_responsavel();
    insert into public.suporte_conversas (assunto, contato_email, contato_nome, usuario_id, responsavel, atribuida_em)
    values (regexp_replace(v_assunto, '^\s*((re|res|fw|fwd|enc|rv)\s*:\s*)+', '', 'i'), v_de,
      nullif(btrim(p->>'de_nome'), ''), v_usuario, v_resp, case when v_resp is not null then now() end)
    returning * into v_conversa;
    v_nova := true;
    if v_resp is not null then
      insert into public.suporte_mensagens (conversa_id, direcao, texto, criada_em)
      values (v_conversa.id, 'evento', 'Entregue para ' || coalesce(public.suporte_nome_equipe(v_resp), v_resp) || ' pelo rodízio', now() - interval '1 millisecond');
    end if;
  else
    -- Conversa encerrada que recebe resposta volta para Em aberto, com a mesma pessoa se ela ainda recebe e-mails.
    if v_conversa.status = 'encerrado' then
      update public.suporte_conversas set status = 'aberto', encerrada_em = null, encerrada_por = null where id = v_conversa.id;
      insert into public.suporte_mensagens (conversa_id, direcao, texto)
      values (v_conversa.id, 'evento', 'Reaberta: o contato respondeu depois do encerramento');
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

  insert into public.suporte_mensagens (conversa_id, direcao, de_email, de_nome, para, cc, assunto, texto, html,
    message_id, referencias, id_externo, anexos)
  values (v_conversa.id, 'recebida', v_de, nullif(btrim(p->>'de_nome'), ''),
    coalesce(array(select lower(jsonb_array_elements_text(coalesce(p->'para', '[]')))), '{}'),
    coalesce(array(select lower(jsonb_array_elements_text(coalesce(p->'cc', '[]')))), '{}'),
    v_assunto, left(p->>'texto', 100000), left(p->>'html', 400000),
    nullif(p->>'message_id', ''), v_refs, p->>'id_externo', coalesce(p->'anexos', '[]'))
  on conflict do nothing;

  update public.suporte_conversas
     set nao_lida = true, mensagens = mensagens + 1, ultima_mensagem_em = now(),
         contato_nome = coalesce(contato_nome, nullif(btrim(p->>'de_nome'), ''))
   where id = v_conversa.id;

  return jsonb_build_object('conversa_id', v_conversa.id, 'nova', v_nova,
    'responsavel', (select responsavel from public.suporte_conversas where id = v_conversa.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Painel: listas e leitura
-- ---------------------------------------------------------------------------
create or replace function public.suporte_meu_email()
returns text
language sql stable security definer
set search_path = public
as $$ select email from public.equipe where usuario_id = auth.uid() limit 1 $$;

create or replace function public.admin_suporte_contagem()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_eu text := public.suporte_meu_email();
begin
  perform public.exigir_admin();
  return (
    select jsonb_build_object(
      'aberto', count(*) filter (where status = 'aberto'),
      'em_atendimento', count(*) filter (where status = 'em_atendimento'),
      'encerrado', count(*) filter (where status = 'encerrado'),
      'meus_aberto', count(*) filter (where status = 'aberto' and responsavel = v_eu),
      'meus_em_atendimento', count(*) filter (where status = 'em_atendimento' and responsavel = v_eu),
      'meus_nao_lidos', count(*) filter (where status <> 'encerrado' and responsavel = v_eu and nao_lida),
      -- O número do menu: conversas minhas que pedem ação (novas ou com resposta do cliente).
      'meus_pendentes', count(*) filter (where responsavel = v_eu and (status = 'aberto' or (status = 'em_atendimento' and nao_lida))),
      'sem_responsavel', count(*) filter (where status <> 'encerrado' and responsavel is null),
      'eu', v_eu)
    from public.suporte_conversas
  );
end;
$$;

-- p_quem: 'meus' | 'todos' | e-mail de alguém da equipe | 'sem_responsavel'
create or replace function public.admin_suporte_conversas(
  p_status text default 'aberto', p_quem text default 'meus', p_busca text default null,
  p_limite integer default 50, p_deslocamento integer default 0)
returns table (
  id bigint, protocolo text, assunto text, contato_email text, contato_nome text, usuario_id uuid, foto_url text,
  e_profissional boolean, status text, responsavel text, responsavel_nome text, nao_lida boolean, mensagens integer,
  criada_em timestamptz, ultima_mensagem_em timestamptz, previa text, ultima_direcao text, total bigint)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_eu text := public.suporte_meu_email();
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  perform public.exigir_admin();
  return query
  with base as (
    select c.* from public.suporte_conversas c
    where (p_status is null or p_status = 'todos' or c.status = p_status)
      and (coalesce(p_quem, 'todos') = 'todos'
        or (p_quem = 'meus' and c.responsavel = v_eu)
        or (p_quem = 'sem_responsavel' and c.responsavel is null)
        or c.responsavel = lower(p_quem))
      and (v_busca is null
        or c.contato_email ilike '%' || v_busca || '%'
        or c.contato_nome ilike '%' || v_busca || '%'
        or c.assunto ilike '%' || v_busca || '%'
        or public.suporte_protocolo(c.id) ilike '%' || v_busca || '%'
        or exists (select 1 from public.suporte_mensagens m where m.conversa_id = c.id and m.direcao in ('recebida', 'enviada') and m.texto ilike '%' || v_busca || '%'))
  )
  select b.id, public.suporte_protocolo(b.id), b.assunto, b.contato_email,
    coalesce(nullif(btrim(pf.nome), ''), b.contato_nome), b.usuario_id, pf.foto_url, coalesce(pf.e_profissional, false),
    b.status, b.responsavel, public.suporte_nome_equipe(b.responsavel), b.nao_lida, b.mensagens, b.criada_em, b.ultima_mensagem_em,
    left(regexp_replace(coalesce(u.texto, ''), '\s+', ' ', 'g'), 160), u.direcao,
    count(*) over ()
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

create or replace function public.admin_suporte_conversa(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  v_eu text := public.suporte_meu_email();
begin
  perform public.exigir_admin();
  select * into v from public.suporte_conversas where id = p_id;
  if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  -- Abrir a conversa marca como lida para quem é o responsável.
  if v.nao_lida and v.responsavel = v_eu then
    update public.suporte_conversas set nao_lida = false where id = p_id;
    v.nao_lida := false;
  end if;
  return jsonb_build_object(
    'id', v.id, 'protocolo', public.suporte_protocolo(v.id), 'assunto', v.assunto,
    'contato_email', v.contato_email, 'contato_nome', v.contato_nome, 'status', v.status,
    'responsavel', v.responsavel, 'responsavel_nome', public.suporte_nome_equipe(v.responsavel),
    'nao_lida', v.nao_lida, 'criada_em', v.criada_em, 'ultima_mensagem_em', v.ultima_mensagem_em,
    'encerrada_em', v.encerrada_em, 'eu', v_eu,
    'pessoa', (select jsonb_build_object('id', pf.id, 'nome', pf.nome, 'foto_url', pf.foto_url, 'e_profissional', pf.e_profissional,
                 'telefone', pf.telefone, 'pedidos', (select count(*) from public.pedidos pd where pd.cliente_id = pf.id or pd.profissional_id = pf.id))
               from public.perfis pf where pf.id = v.usuario_id),
    'outras', (select count(*) from public.suporte_conversas o where o.contato_email = v.contato_email and o.id <> v.id),
    'mensagens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'direcao', m.direcao, 'de_email', m.de_email, 'de_nome', m.de_nome, 'para', m.para, 'cc', m.cc,
        'assunto', m.assunto, 'texto', m.texto, 'tem_html', m.html is not null, 'autor_nome', m.autor_nome,
        'envio', m.envio, 'erro', m.erro, 'anexos', m.anexos, 'criada_em', m.criada_em) order by m.criada_em, m.id)
      from public.suporte_mensagens m where m.conversa_id = v.id), '[]'));
end;
$$;

-- O HTML original de um e-mail recebido (o painel mostra numa moldura isolada, sem scripts).
create or replace function public.admin_suporte_html(p_mensagem bigint)
returns text
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return (select html from public.suporte_mensagens where id = p_mensagem);
end;
$$;

-- Equipe no rodízio, com quantas conversas cada um tem agora.
create or replace function public.admin_suporte_equipe()
returns table (email text, nome text, foto_url text, ativo boolean, recebe_emails boolean, ultima_atribuicao timestamptz,
  aberto bigint, em_atendimento bigint, encerrado_7d bigint, voce boolean)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select e.email, coalesce(nullif(btrim(p.nome), ''), e.nome), p.foto_url, coalesce(p.e_admin, false), e.recebe_emails, e.ultima_atribuicao,
    (select count(*) from public.suporte_conversas c where c.responsavel = e.email and c.status = 'aberto'),
    (select count(*) from public.suporte_conversas c where c.responsavel = e.email and c.status = 'em_atendimento'),
    (select count(*) from public.suporte_conversas c where c.responsavel = e.email and c.status = 'encerrado' and c.encerrada_em > now() - interval '7 days'),
    e.usuario_id = auth.uid()
  from public.equipe e
  left join public.perfis p on p.id = e.usuario_id
  order by coalesce(p.e_admin, false) desc, (e.papel = 'dono') desc, e.convidado_em;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Painel: ações
-- ---------------------------------------------------------------------------
create or replace function public.admin_suporte_rodizio(p_email text, p_recebe boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  perform public.exigir_admin();
  update public.equipe set recebe_emails = coalesce(p_recebe, true),
    -- Quem volta ao rodízio entra no fim da fila, para não receber vários seguidos.
    ultima_atribuicao = case when p_recebe and not recebe_emails then clock_timestamp() else ultima_atribuicao end
  where email = v_email;
  if not found then perform public.erro('nao_encontrado', 'Esta pessoa não está na equipe.'); end if;
  perform public.registrar_acao('suporte_rodizio', v_email, jsonb_build_object('recebe_emails', p_recebe));
  if p_recebe then perform public.suporte_distribuir_pendentes(); end if;
end;
$$;

create or replace function public.admin_suporte_status(p_id bigint, p_status text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  v_eu text := public.suporte_meu_email();
begin
  perform public.exigir_admin();
  if p_status not in ('aberto', 'em_atendimento', 'encerrado') then
    perform public.erro('status_invalido', 'Situação inválida.');
  end if;
  select * into v from public.suporte_conversas where id = p_id for update;
  if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  if v.status = p_status then return; end if;

  update public.suporte_conversas set
    status = p_status,
    -- Quem começa a atender uma conversa sem responsável fica com ela.
    responsavel = case when p_status = 'em_atendimento' and responsavel is null then v_eu else responsavel end,
    atribuida_em = case when p_status = 'em_atendimento' and responsavel is null then now() else atribuida_em end,
    nao_lida = case when p_status = 'encerrado' then false else nao_lida end,
    encerrada_em = case when p_status = 'encerrado' then now() end,
    encerrada_por = case when p_status = 'encerrado' then auth.uid() end
  where id = p_id;

  perform public.suporte_evento(p_id, case p_status
    when 'encerrado' then 'Encerrada'
    when 'em_atendimento' then 'Em atendimento'
    else 'Voltou para Em aberto' end);
  perform public.registrar_acao('suporte_status', public.suporte_protocolo(p_id), jsonb_build_object('de', v.status, 'para', p_status));
end;
$$;

create or replace function public.admin_suporte_transferir(p_id bigint, p_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v public.suporte_conversas;
begin
  perform public.exigir_admin();
  if not exists (select 1 from public.equipe e join public.perfis p on p.id = e.usuario_id where e.email = v_email and p.e_admin) then
    perform public.erro('nao_encontrado', 'Escolha alguém da equipe que já tenha acesso ao painel.');
  end if;
  select * into v from public.suporte_conversas where id = p_id for update;
  if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  if v.responsavel = v_email then return; end if;
  update public.suporte_conversas set responsavel = v_email, atribuida_em = now(),
    nao_lida = case when v_email = public.suporte_meu_email() then false else true end
  where id = p_id;
  perform public.suporte_evento(p_id, case when v_email = public.suporte_meu_email()
    then 'Assumiu a conversa'
    else 'Transferida para ' || coalesce(public.suporte_nome_equipe(v_email), v_email) end);
  perform public.registrar_acao('suporte_transferir', public.suporte_protocolo(p_id), jsonb_build_object('de', v.responsavel, 'para', v_email));
end;
$$;

create or replace function public.admin_suporte_nota(p_id bigint, p_texto text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if length(btrim(coalesce(p_texto, ''))) = 0 then perform public.erro('texto_vazio', 'Escreva a nota.'); end if;
  if not exists (select 1 from public.suporte_conversas where id = p_id) then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  insert into public.suporte_mensagens (conversa_id, direcao, texto, autor_id, autor_nome)
  values (p_id, 'nota', left(btrim(p_texto), 10000), auth.uid(), public.suporte_nome_equipe(public.suporte_meu_email()));
end;
$$;

-- Prepara uma resposta (ou um e-mail novo, com p_id nulo) e devolve o que a função
-- responder-suporte precisa para enviar. Chamada pela função com o login de quem escreveu.
create or replace function public.admin_suporte_preparar_envio(
  p_id bigint, p_texto text, p_para text default null, p_assunto text default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
  v_eu text := public.suporte_meu_email();
  v_nome text;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_para text := lower(btrim(coalesce(p_para, '')));
  v_refs text[];
  v_ultima public.suporte_mensagens;
  v_msg bigint;
begin
  perform public.exigir_admin();
  if v_eu is null then perform public.erro('sem_equipe', 'Sua conta não está na lista da equipe.'); end if;
  if length(v_texto) = 0 then perform public.erro('texto_vazio', 'Escreva a mensagem.'); end if;
  if length(v_texto) > 20000 then perform public.erro('texto_longo', 'A mensagem está longa demais.'); end if;
  v_nome := public.suporte_nome_equipe(v_eu);

  if p_id is null then
    -- E-mail novo, puxado pela equipe.
    if v_para !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then perform public.erro('email_invalido', 'Confira o e-mail do destinatário.'); end if;
    if v_para like '%@iservice.app.br' then perform public.erro('email_invalido', 'Este endereço é da própria iService.'); end if;
    if length(btrim(coalesce(p_assunto, ''))) < 2 then perform public.erro('assunto_vazio', 'Escreva o assunto.'); end if;
    insert into public.suporte_conversas (assunto, contato_email, contato_nome, usuario_id, status, responsavel, atribuida_em, nao_lida)
    values (left(btrim(p_assunto), 300), v_para,
      (select nullif(btrim(nome), '') from public.perfis where lower(email) = v_para limit 1),
      (select id from public.perfis where lower(email) = v_para limit 1),
      'em_atendimento', v_eu, now(), false)
    returning * into v;
    insert into public.suporte_mensagens (conversa_id, direcao, texto, autor_id, autor_nome)
    values (v.id, 'evento', 'Conversa iniciada pela equipe', auth.uid(), v_nome);
  else
    select * into v from public.suporte_conversas where id = p_id for update;
    if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
    -- Responder leva para Em atendimento e, se ninguém cuidava, quem respondeu fica com ela.
    update public.suporte_conversas set
      status = case when status = 'aberto' then 'em_atendimento' else status end,
      responsavel = coalesce(responsavel, v_eu),
      atribuida_em = case when responsavel is null then now() else atribuida_em end,
      nao_lida = false
    where id = v.id;
    if v.status = 'aberto' then
      perform public.suporte_evento(v.id, 'Em atendimento');
    end if;
  end if;

  select * into v_ultima from public.suporte_mensagens
  where conversa_id = v.id and direcao in ('recebida', 'enviada') and envio is distinct from 'erro'
  order by criada_em desc limit 1;
  v_refs := (select coalesce(array_agg(x), '{}') from (
    select distinct unnest(coalesce(v_ultima.referencias, '{}') || case when v_ultima.message_id is not null then array[v_ultima.message_id] else '{}'::text[] end) x
  ) r where x is not null and x <> '');

  insert into public.suporte_mensagens (conversa_id, direcao, de_email, de_nome, para, assunto, texto, message_id, referencias,
    autor_id, autor_nome, envio)
  values (v.id, 'enviada', 'suporte@iservice.app.br', v_nome, array[v.contato_email],
    case when p_id is null then v.assunto else 'Re: ' || v.assunto end, v_texto, null, v_refs,
    auth.uid(), v_nome, 'enviando')
  returning id into v_msg;

  update public.suporte_conversas set mensagens = mensagens + 1, ultima_mensagem_em = now() where id = v.id;

  return jsonb_build_object(
    'mensagem_id', v_msg, 'conversa_id', v.id, 'protocolo', public.suporte_protocolo(v.id),
    'para', v.contato_email, 'contato_nome', v.contato_nome,
    'assunto', (case when p_id is null then v.assunto else 'Re: ' || v.assunto end) || ' [' || public.suporte_protocolo(v.id) || ']',
    'texto', v_texto, 'autor_nome', v_nome,
    'in_reply_to', v_ultima.message_id, 'referencias', to_jsonb(v_refs),
    'citacao', case when v_ultima.direcao = 'recebida' then jsonb_build_object(
      'de', coalesce(v_ultima.de_nome, v_ultima.de_email), 'quando', v_ultima.criada_em, 'texto', left(v_ultima.texto, 4000)) end);
end;
$$;

-- Reenviar uma resposta que falhou: devolve os mesmos dados de envio.
create or replace function public.admin_suporte_preparar_reenvio(p_mensagem bigint)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  m public.suporte_mensagens;
  v public.suporte_conversas;
  v_ant public.suporte_mensagens;
begin
  perform public.exigir_admin();
  select * into m from public.suporte_mensagens where id = p_mensagem and direcao = 'enviada' for update;
  if m.id is null then perform public.erro('nao_encontrado', 'Mensagem não encontrada.'); end if;
  if m.envio is distinct from 'erro' then perform public.erro('ja_enviada', 'Esta mensagem já foi enviada.'); end if;
  select * into v from public.suporte_conversas where id = m.conversa_id;
  select * into v_ant from public.suporte_mensagens
  where conversa_id = v.id and direcao = 'recebida' and criada_em < m.criada_em order by criada_em desc limit 1;
  update public.suporte_mensagens set envio = 'enviando', erro = null where id = m.id;
  return jsonb_build_object(
    'mensagem_id', m.id, 'conversa_id', v.id, 'protocolo', public.suporte_protocolo(v.id),
    'para', m.para[1], 'contato_nome', v.contato_nome,
    'assunto', m.assunto || ' [' || public.suporte_protocolo(v.id) || ']',
    'texto', m.texto, 'autor_nome', m.autor_nome,
    'in_reply_to', m.referencias[array_length(m.referencias, 1)], 'referencias', to_jsonb(m.referencias),
    'citacao', case when v_ant.id is not null then jsonb_build_object(
      'de', coalesce(v_ant.de_nome, v_ant.de_email), 'quando', v_ant.criada_em, 'texto', left(v_ant.texto, 4000)) end);
end;
$$;

-- Resultado do envio (só a função responder-suporte, com a chave de serviço).
-- p_message_id: o Message-ID que o Resend deu ao e-mail; é por ele que a resposta do cliente
-- volta para a mesma conversa.
create or replace function public.suporte_resultado_envio(p_mensagem bigint, p_ok boolean, p_id_externo text default null,
  p_erro text default null, p_message_id text default null)
returns void
language sql security definer
set search_path = public
as $$
  update public.suporte_mensagens
     set envio = case when p_ok then 'enviado' else 'erro' end,
         id_externo = coalesce(p_id_externo, id_externo),
         message_id = coalesce(nullif(p_message_id, ''), message_id),
         erro = case when p_ok then null else left(p_erro, 500) end
   where id = p_mensagem and direcao = 'enviada'
$$;

-- ---------------------------------------------------------------------------
-- 7. Permissões
-- ---------------------------------------------------------------------------
revoke all on function public.suporte_protocolo(bigint) from public, anon;
revoke all on function public.suporte_proximo_responsavel() from public, anon, authenticated;
revoke all on function public.suporte_evento(bigint, text) from public, anon, authenticated;
revoke all on function public.suporte_nome_equipe(text) from public, anon, authenticated;
revoke all on function public.suporte_distribuir_pendentes() from public, anon, authenticated;
revoke all on function public.suporte_saiu_da_equipe() from public, anon, authenticated;
revoke all on function public.suporte_entrou_na_equipe() from public, anon, authenticated;
revoke all on function public.suporte_receber(jsonb) from public, anon, authenticated;
revoke all on function public.suporte_meu_email() from public, anon, authenticated;
revoke all on function public.suporte_resultado_envio(bigint, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.suporte_receber(jsonb) to service_role;
grant execute on function public.suporte_resultado_envio(bigint, boolean, text, text, text) to service_role;
grant execute on function public.suporte_protocolo(bigint) to authenticated;

revoke all on function public.admin_suporte_contagem() from public, anon;
revoke all on function public.admin_suporte_conversas(text, text, text, integer, integer) from public, anon;
revoke all on function public.admin_suporte_conversa(bigint) from public, anon;
revoke all on function public.admin_suporte_html(bigint) from public, anon;
revoke all on function public.admin_suporte_equipe() from public, anon;
revoke all on function public.admin_suporte_rodizio(text, boolean) from public, anon;
revoke all on function public.admin_suporte_status(bigint, text) from public, anon;
revoke all on function public.admin_suporte_transferir(bigint, text) from public, anon;
revoke all on function public.admin_suporte_nota(bigint, text) from public, anon;
revoke all on function public.admin_suporte_preparar_envio(bigint, text, text, text) from public, anon;
revoke all on function public.admin_suporte_preparar_reenvio(bigint) from public, anon;
grant execute on function public.admin_suporte_contagem() to authenticated;
grant execute on function public.admin_suporte_conversas(text, text, text, integer, integer) to authenticated;
grant execute on function public.admin_suporte_conversa(bigint) to authenticated;
grant execute on function public.admin_suporte_html(bigint) to authenticated;
grant execute on function public.admin_suporte_equipe() to authenticated;
grant execute on function public.admin_suporte_rodizio(text, boolean) to authenticated;
grant execute on function public.admin_suporte_status(bigint, text) to authenticated;
grant execute on function public.admin_suporte_transferir(bigint, text) to authenticated;
grant execute on function public.admin_suporte_nota(bigint, text) to authenticated;
grant execute on function public.admin_suporte_preparar_envio(bigint, text, text, text) to authenticated;
grant execute on function public.admin_suporte_preparar_reenvio(bigint) to authenticated;
