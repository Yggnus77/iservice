-- Suporte e incidentes (Plano Diretor, tópico 7).
--
--  1. Horário de atendimento configurável (padrão: segunda a sábado, 8h às 20h, Brasília)
--     e plantão de emergência: quem está de plantão recebe os alertas 24 horas.
--  2. Emergência avisa a equipe na hora: notificação no celular e e-mail para o dono e
--     para quem está de plantão. O painel registra quando alguém ligou para a pessoa.
--  3. Gravidade de 1 a 4 em e-mails, garantia, denúncias e emergências, com prazo de
--     primeira resposta contado no horário de atendimento (gravidade 1: 15 minutos, 24h).
--  4. Resposta automática no e-mail fora do horário (a função receber-email envia).
--  5. Central de Ajuda: perguntas frequentes para os apps e o site, editáveis no painel.
--  6. Indicadores: tempo até a primeira resposta e quanto ficou dentro do prazo.

-- ---------------------------------------------------------------------------
-- 1. Horário de atendimento e plantão
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao)
values ('horario_atendimento', '{"dias": [1, 2, 3, 4, 5, 6], "inicio": "08:00", "fim": "20:00"}'::jsonb,
  'Horário do suporte (Brasília). dias: 1 = segunda ... 7 = domingo. Emergências têm plantão 24 horas.')
on conflict (chave) do nothing;

alter table public.equipe add column if not exists plantao boolean not null default false;

create or replace function public.horario_atendimento()
returns jsonb
language sql stable
set search_path = public
as $$
  select coalesce(public.cfg('horario_atendimento'), '{"dias": [1, 2, 3, 4, 5, 6], "inicio": "08:00", "fim": "20:00"}'::jsonb)
$$;

-- Está dentro do horário de atendimento agora (ou no instante dado)?
create or replace function public.em_horario_atendimento(p_quando timestamptz default now())
returns boolean
language plpgsql stable
set search_path = public
as $$
declare
  h jsonb := public.horario_atendimento();
  v_local timestamp := p_quando at time zone 'America/Sao_Paulo';
begin
  return extract(isodow from v_local)::int in (select jsonb_array_elements_text(h -> 'dias')::int)
    and v_local::time >= (h ->> 'inicio')::time
    and v_local::time < (h ->> 'fim')::time;
end;
$$;

-- Soma minutos contando só o horário de atendimento. Começando fora do horário,
-- o relógio só corre a partir da próxima abertura.
create or replace function public.somar_minutos_atendimento(p_inicio timestamptz, p_minutos integer)
returns timestamptz
language plpgsql stable
set search_path = public
as $$
declare
  h jsonb := public.horario_atendimento();
  v_dias int[] := array(select jsonb_array_elements_text(h -> 'dias')::int);
  v_ini time := (h ->> 'inicio')::time;
  v_fim time := (h ->> 'fim')::time;
  v_local timestamp := p_inicio at time zone 'America/Sao_Paulo';
  v_dia date := (p_inicio at time zone 'America/Sao_Paulo')::date;
  v_resto integer := greatest(coalesce(p_minutos, 0), 0);
  v_de timestamp;
  v_livre integer;
begin
  if coalesce(array_length(v_dias, 1), 0) = 0 or v_fim <= v_ini then
    return p_inicio + make_interval(mins => v_resto);
  end if;
  for i in 0..400 loop
    if extract(isodow from v_dia)::int = any (v_dias) then
      v_de := greatest(v_dia + v_ini, v_local);
      if v_de < v_dia + v_fim then
        v_livre := floor(extract(epoch from (v_dia + v_fim) - v_de) / 60);
        if v_resto <= v_livre then
          return (v_de + make_interval(mins => v_resto)) at time zone 'America/Sao_Paulo';
        end if;
        v_resto := v_resto - v_livre;
      end if;
    end if;
    v_dia := v_dia + 1;
  end loop;
  return p_inicio + make_interval(mins => p_minutos);
end;
$$;

-- Prazo da primeira resposta por gravidade.
--   1 crítica: 15 minutos corridos, 24 horas por dia (plantão)
--   2 alta:    1 hora de atendimento
--   3 média:   4 horas de atendimento
--   4 baixa:   1 dia de atendimento
create or replace function public.prazo_resposta(p_gravidade integer, p_desde timestamptz)
returns timestamptz
language plpgsql stable
set search_path = public
as $$
declare
  h jsonb := public.horario_atendimento();
  v_dia_util integer := greatest(floor(extract(epoch from ((h ->> 'fim')::time - (h ->> 'inicio')::time)) / 60)::int, 60);
begin
  return case p_gravidade
    when 1 then p_desde + interval '15 minutes'
    when 2 then public.somar_minutos_atendimento(p_desde, 60)
    when 3 then public.somar_minutos_atendimento(p_desde, 240)
    else public.somar_minutos_atendimento(p_desde, v_dia_util)
  end;
end;
$$;

-- Gravidade sugerida pelo texto (a equipe pode mudar no painel).
create or replace function public.gravidade_sugerida(p_texto text)
returns smallint
language sql immutable
as $$
  select case
    when p_texto ~* '(emerg(e|ê)ncia|ass(e|é)dio|agred|agress|viol(e|ê)n|amea(c|ç)|roub|furt|pol(i|í)cia|estupr|abuso|machuc|acidente|socorro|\marma\M)' then 1
    when p_texto ~* '(n(a|ã)o apareceu|n(a|ã)o veio|abandon|golpe|cobran(c|ç)a indevida|cobrou a mais|dano|quebr|estrag|preju(i|í)zo|pagamento por fora|briga)' then 2
    when p_texto ~* '(garantia|reclama|mal feito|cadastro|documento|certid|avalia(c|ç)(a|ã)o|recusad|suspens|bloquead)' then 3
    else 4
  end::smallint
$$;

-- ---------------------------------------------------------------------------
-- 2. Gravidade e primeira resposta em cada atendimento
-- ---------------------------------------------------------------------------
alter table public.suporte_conversas add column if not exists gravidade smallint not null default 4;
alter table public.suporte_conversas add column if not exists primeira_resposta_em timestamptz;
alter table public.reclamacoes add column if not exists gravidade smallint not null default 3;
alter table public.reclamacoes add column if not exists primeira_resposta_em timestamptz;
alter table public.denuncias add column if not exists gravidade smallint not null default 3;
alter table public.denuncias add column if not exists primeira_resposta_em timestamptz;
alter table public.emergencias add column if not exists contato_em timestamptz;
alter table public.emergencias add column if not exists contato_por uuid references public.perfis (id) on delete set null;

do $$
declare t text;
begin
  foreach t in array array['suporte_conversas', 'reclamacoes', 'denuncias'] loop
    if not exists (select 1 from pg_constraint where conname = t || '_gravidade_check') then
      execute format('alter table public.%I add constraint %I check (gravidade between 1 and 4)', t, t || '_gravidade_check');
    end if;
  end loop;
end $$;

-- O que já existia conta como respondido quando já teve resposta ou decisão.
update public.suporte_conversas c set primeira_resposta_em = (
  select min(m.criada_em) from public.suporte_mensagens m where m.conversa_id = c.id and m.direcao = 'enviada')
where primeira_resposta_em is null;
update public.reclamacoes r set primeira_resposta_em = (
  select min(h.criado_em) from public.reclamacao_historico h where h.reclamacao_id = r.id)
where primeira_resposta_em is null;
update public.denuncias set primeira_resposta_em = resolvida_em where primeira_resposta_em is null and resolvida_em is not null;
update public.emergencias set contato_em = atendida_em where contato_em is null and atendida_em is not null;

-- E-mail: a primeira mensagem recebida sugere a gravidade; a primeira enviada marca a resposta.
create or replace function public.suporte_prazo_mensagem()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.direcao = 'enviada' then
    update public.suporte_conversas set primeira_resposta_em = coalesce(primeira_resposta_em, new.criada_em)
    where id = new.conversa_id;
  elsif new.direcao = 'recebida' then
    update public.suporte_conversas
       set gravidade = least(gravidade, public.gravidade_sugerida(coalesce(new.assunto, '') || ' ' || left(coalesce(new.texto, ''), 4000)))
     where id = new.conversa_id and primeira_resposta_em is null;
  end if;
  return null;
end;
$$;
drop trigger if exists suporte_prazo_mensagem on public.suporte_mensagens;
create trigger suporte_prazo_mensagem after insert on public.suporte_mensagens
  for each row execute function public.suporte_prazo_mensagem();

-- Garantia: o primeiro passo registrado pela equipe é a primeira resposta.
create or replace function public.reclamacao_prazo()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_table_name = 'reclamacoes' then
    new.gravidade := least(new.gravidade, public.gravidade_sugerida(coalesce(new.motivo, '') || ' ' || coalesce(new.descricao, '')),
      3)::smallint;
    return new;
  end if;
  update public.reclamacoes set primeira_resposta_em = coalesce(primeira_resposta_em, new.criado_em)
  where id = new.reclamacao_id;
  return null;
end;
$$;
drop trigger if exists reclamacao_gravidade on public.reclamacoes;
create trigger reclamacao_gravidade before insert on public.reclamacoes
  for each row execute function public.reclamacao_prazo();
drop trigger if exists reclamacao_primeira_resposta on public.reclamacao_historico;
create trigger reclamacao_primeira_resposta after insert on public.reclamacao_historico
  for each row execute function public.reclamacao_prazo();

-- Denúncia: gravidade pelo motivo; responder = sair de "aberta".
create or replace function public.denuncia_prazo()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.gravidade := case
      when new.motivo ~* 'ass(e|é)dio|comportamento' then 1
      when new.motivo ~* 'golpe|cobran|n(a|ã)o apareceu|abandon|dano' then 2
      else least(3, public.gravidade_sugerida(coalesce(new.descricao, '')))
    end;
  elsif new.status is distinct from old.status and old.status = 'aberta' then
    new.primeira_resposta_em := coalesce(new.primeira_resposta_em, now());
  end if;
  return new;
end;
$$;
drop trigger if exists denuncia_prazo on public.denuncias;
create trigger denuncia_prazo before insert or update on public.denuncias
  for each row execute function public.denuncia_prazo();

-- ---------------------------------------------------------------------------
-- 3. Emergência avisa a equipe na hora
-- ---------------------------------------------------------------------------
-- Vai para o dono e para quem está de plantão (com acesso às emergências).
-- Sem ninguém de plantão, todo mundo que tem acesso às emergências recebe.
create or replace function public.avisar_emergencia()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_nome text;
  v_tel text;
  v_papel text;
  v_codigo text;
  v_corpo text;
  v_tem_plantao boolean;
  m record;
begin
  select nullif(btrim(nome), ''), telefone into v_nome, v_tel from public.perfis where id = new.usuario_id;
  if new.pedido_id is not null then
    select codigo, case when cliente_id = new.usuario_id then 'cliente' else 'profissional' end
      into v_codigo, v_papel from public.pedidos where id = new.pedido_id;
  end if;
  v_corpo := coalesce(v_nome, 'Uma pessoa') || coalesce(' (' || v_papel || ')', '')
    || ' apertou o botão de emergência' || coalesce(' no pedido #' || v_codigo, '') || '. Ligue agora'
    || coalesce(': ' || v_tel, '') || '.';

  select exists (
    select 1 from public.equipe e
    where e.plantao and e.usuario_id is not null and 'emergencias' = any (public.cargo_permissoes(e.papel))
  ) into v_tem_plantao;

  for m in
    select distinct e.usuario_id from public.equipe e
    where e.usuario_id is not null
      and e.usuario_id <> new.usuario_id
      and 'emergencias' = any (public.cargo_permissoes(e.papel))
      and (e.papel = 'dono' or e.plantao or not v_tem_plantao)
  loop
    perform public.notificar(m.usuario_id, 'emergencia_equipe', 'EMERGÊNCIA no iService', v_corpo,
      jsonb_build_object('emergencia_id', new.id, 'pedido', v_codigo, 'pessoa', v_nome, 'papel', v_papel,
        'telefone', v_tel, 'criada_em', new.criada_em));
  end loop;
  return null;
end;
$$;
drop trigger if exists avisar_emergencia on public.emergencias;
create trigger avisar_emergencia after insert on public.emergencias
  for each row execute function public.avisar_emergencia();

-- O alerta da equipe também vai por e-mail.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.tipo_tem_email(text)'::regprocedure) into v_def;
  if position('emergencia_equipe' in v_def) = 0 then
    if position('''lembrete_agendamento''' in v_def) = 0 then
      raise exception 'tipo_tem_email mudou: confira antes de aplicar';
    end if;
    execute replace(v_def, '''lembrete_agendamento''', '''lembrete_agendamento'', ''emergencia_equipe''');
  end if;
end $$;

-- Painel: lista com o contato registrado.
drop function if exists public.admin_emergencias(boolean);
create function public.admin_emergencias(p_abertas boolean default true)
returns table (id bigint, pedido_id uuid, codigo text, usuario_id uuid, usuario text, telefone text, papel text,
  lat numeric, lng numeric, criada_em timestamptz, atendida_em timestamptz, atendida_por text, nota_atendimento text,
  contato_em timestamptz, contato_por text, prazo timestamptz)
language plpgsql stable security definer
set search_path = public, extensions
as $$
begin
  perform public.exigir_permissao('emergencias');
  return query
  select e.id, e.pedido_id, p.codigo, e.usuario_id, u.nome, u.telefone,
    case when p.id is null then null when e.usuario_id = p.cliente_id then 'cliente' else 'profissional' end,
    round(extensions.st_y(e.localizacao::extensions.geometry)::numeric, 5), round(extensions.st_x(e.localizacao::extensions.geometry)::numeric, 5),
    e.criada_em, e.atendida_em, (select a.nome from public.perfis a where a.id = e.atendida_por), e.nota_atendimento,
    e.contato_em, (select a.nome from public.perfis a where a.id = e.contato_por), e.criada_em + interval '15 minutes'
  from public.emergencias e
  join public.perfis u on u.id = e.usuario_id
  left join public.pedidos p on p.id = e.pedido_id
  where not p_abertas or e.atendida_em is null
  order by e.atendida_em is not null, e.criada_em desc
  limit 200;
end;
$$;
revoke all on function public.admin_emergencias(boolean) from public, anon;
grant execute on function public.admin_emergencias(boolean) to authenticated;

create or replace function public.admin_contato_emergencia(p_emergencia bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_usuario uuid;
begin
  perform public.exigir_permissao('emergencias');
  update public.emergencias set contato_em = coalesce(contato_em, now()), contato_por = coalesce(contato_por, auth.uid())
  where id = p_emergencia returning usuario_id into v_usuario;
  if v_usuario is null then perform public.erro('nao_encontrado', 'Emergência não encontrada.'); end if;
  perform public.registrar_acao('contato_emergencia', v_usuario::text, jsonb_build_object('emergencia_id', p_emergencia));
end;
$$;
revoke all on function public.admin_contato_emergencia(bigint) from public, anon;
grant execute on function public.admin_contato_emergencia(bigint) to authenticated;

-- Marcar como atendida também conta como contato feito.
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.admin_atender_emergencia(bigint, text)'::regprocedure) into v_def;
  if position('contato_em' in v_def) = 0 then
    if position('nota_atendimento = nullif(trim(p_nota), '''')' in v_def) = 0 then
      raise exception 'admin_atender_emergencia mudou: confira antes de aplicar';
    end if;
    execute replace(v_def, 'nota_atendimento = nullif(trim(p_nota), '''')',
      'nota_atendimento = nullif(trim(p_nota), ''''), contato_em = coalesce(contato_em, now()), contato_por = coalesce(contato_por, auth.uid())');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Prazos e gravidade no painel
-- ---------------------------------------------------------------------------
create or replace function public.permissao_do_atendimento(p_tipo text)
returns text
language sql immutable
as $$
  select case p_tipo when 'email' then 'emails' when 'garantia' then 'garantia' when 'denuncia' then 'denuncias'
    when 'emergencia' then 'emergencias' end
$$;

-- Gravidade, prazo e primeira resposta de uma lista de atendimentos.
create or replace function public.admin_prazos(p_tipo text, p_ids bigint[])
returns table (id bigint, gravidade smallint, prazo timestamptz, respondida_em timestamptz, atrasada boolean)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if public.permissao_do_atendimento(p_tipo) is null then perform public.erro('tipo_invalido', 'Tipo de atendimento inválido.'); end if;
  perform public.exigir_permissao(public.permissao_do_atendimento(p_tipo));
  return query
  with base as (
    select c.id, c.gravidade, c.criada_em as desde, c.primeira_resposta_em as resp
    from public.suporte_conversas c where p_tipo = 'email' and c.id = any (p_ids)
    union all
    select r.id, r.gravidade, r.criada_em, r.primeira_resposta_em
    from public.reclamacoes r where p_tipo = 'garantia' and r.id = any (p_ids)
    union all
    select d.id, d.gravidade, d.criada_em, d.primeira_resposta_em
    from public.denuncias d where p_tipo = 'denuncia' and d.id = any (p_ids)
    union all
    select e.id, 1::smallint, e.criada_em, coalesce(e.contato_em, e.atendida_em)
    from public.emergencias e where p_tipo = 'emergencia' and e.id = any (p_ids)
  )
  select b.id, b.gravidade, public.prazo_resposta(b.gravidade, b.desde), b.resp,
    coalesce(b.resp, now()) > public.prazo_resposta(b.gravidade, b.desde)
  from base b;
end;
$$;

create or replace function public.admin_definir_gravidade(p_tipo text, p_id bigint, p_gravidade integer)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  if public.permissao_do_atendimento(p_tipo) is null or p_tipo = 'emergencia' then
    perform public.erro('tipo_invalido', 'Tipo de atendimento inválido.');
  end if;
  perform public.exigir_permissao(public.permissao_do_atendimento(p_tipo));
  if p_gravidade is null or p_gravidade not between 1 and 4 then
    perform public.erro('gravidade_invalida', 'A gravidade vai de 1 (crítica) a 4 (baixa).');
  end if;
  if p_tipo = 'email' then
    update public.suporte_conversas set gravidade = p_gravidade where id = p_id returning true into v_ok;
  elsif p_tipo = 'garantia' then
    update public.reclamacoes set gravidade = p_gravidade where id = p_id returning true into v_ok;
  else
    update public.denuncias set gravidade = p_gravidade where id = p_id returning true into v_ok;
  end if;
  if v_ok is null then perform public.erro('nao_encontrado', 'Atendimento não encontrado.'); end if;
  perform public.registrar_acao('definir_gravidade', p_tipo || ':' || p_id, jsonb_build_object('gravidade', p_gravidade));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Horário e plantão pelo painel
-- ---------------------------------------------------------------------------
create or replace function public.admin_atendimento()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return jsonb_build_object(
    'horario', public.horario_atendimento(),
    'agora_aberto', public.em_horario_atendimento(),
    'pode_editar', public.pode('configuracoes'),
    'pode_plantao', public.pode('equipe_gerir'),
    'plantao', coalesce((
      select jsonb_agg(jsonb_build_object('email', e.email, 'nome', e.nome, 'papel', e.papel, 'plantao', e.plantao,
        'ativo', e.usuario_id is not null) order by e.plantao desc, e.nome)
      from public.equipe e where 'emergencias' = any (public.cargo_permissoes(e.papel))), '[]'::jsonb));
end;
$$;

create or replace function public.admin_salvar_horario(p_dias integer[], p_inicio text, p_fim text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('configuracoes');
  if p_dias is null or cardinality(p_dias) = 0 or exists (select 1 from unnest(p_dias) d where d not between 1 and 7) then
    perform public.erro('dias_invalidos', 'Escolha pelo menos um dia da semana.');
  end if;
  if p_inicio !~ '^\d{2}:\d{2}$' or p_fim !~ '^\d{2}:\d{2}$' or p_fim::time <= p_inicio::time then
    perform public.erro('horario_invalido', 'O fim do atendimento precisa ser depois do início.');
  end if;
  insert into public.app_config (chave, valor, descricao)
  values ('horario_atendimento', jsonb_build_object('dias', (select jsonb_agg(d order by d) from (select distinct unnest(p_dias) d) x),
    'inicio', p_inicio, 'fim', p_fim), 'Horário do suporte (Brasília). dias: 1 = segunda ... 7 = domingo. Emergências têm plantão 24 horas.')
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform public.registrar_acao('horario_atendimento', 'config', jsonb_build_object('dias', p_dias, 'inicio', p_inicio, 'fim', p_fim));
end;
$$;

create or replace function public.admin_definir_plantao(p_email text, p_plantao boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  perform public.exigir_permissao('equipe_gerir');
  update public.equipe set plantao = coalesce(p_plantao, false)
  where email = lower(btrim(p_email)) and 'emergencias' = any (public.cargo_permissoes(papel))
  returning true into v_ok;
  if v_ok is null then perform public.erro('nao_encontrado', 'Pessoa da equipe não encontrada ou sem acesso às emergências.'); end if;
  perform public.registrar_acao('plantao', lower(btrim(p_email)), jsonb_build_object('plantao', p_plantao));
end;
$$;

-- Resposta automática do e-mail fora do horário: a função receber-email pergunta
-- aqui se deve responder. Responde uma vez por conversa nova.
create or replace function public.suporte_resposta_automatica(p_conversa bigint)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c public.suporte_conversas;
  m public.suporte_mensagens;
begin
  select * into c from public.suporte_conversas where id = p_conversa;
  if c.id is null or c.mensagens > 1 or public.em_horario_atendimento() then
    return jsonb_build_object('enviar', false);
  end if;
  if exists (select 1 from public.suporte_mensagens where conversa_id = c.id and direcao = 'evento' and texto like 'Resposta automática%') then
    return jsonb_build_object('enviar', false);
  end if;
  if c.contato_email ~* '(^|[.+_-])(no-?reply|nao-?responda|mailer-daemon|postmaster|bounce)' or c.contato_email like '%@iservice.app.br' then
    return jsonb_build_object('enviar', false);
  end if;
  select * into m from public.suporte_mensagens where conversa_id = c.id and direcao = 'recebida' order by id desc limit 1;
  insert into public.suporte_mensagens (conversa_id, direcao, texto)
  values (c.id, 'evento', 'Resposta automática de fora do horário enviada.');
  return jsonb_build_object('enviar', true, 'para', c.contato_email, 'nome', c.contato_nome,
    'assunto', c.assunto, 'protocolo', public.suporte_protocolo(c.id), 'in_reply_to', m.message_id,
    'horario', public.horario_atendimento(), 'whatsapp', coalesce(public.cfg('whatsapp_suporte') #>> '{}', ''));
end;
$$;
revoke all on function public.suporte_resposta_automatica(bigint) from public, anon, authenticated;
grant execute on function public.suporte_resposta_automatica(bigint) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Central de Ajuda
-- ---------------------------------------------------------------------------
create table if not exists public.ajuda_perguntas (
  id bigint generated always as identity primary key,
  publico text not null default 'todos' check (publico in ('cliente', 'profissional', 'todos')),
  categoria text not null default 'Geral' check (char_length(btrim(categoria)) between 2 and 40),
  pergunta text not null check (char_length(btrim(pergunta)) between 5 and 200),
  resposta text not null check (char_length(btrim(resposta)) between 5 and 2000),
  ordem integer not null default 100,
  ativa boolean not null default true,
  atualizada_em timestamptz not null default now()
);
alter table public.ajuda_perguntas enable row level security;
revoke all on public.ajuda_perguntas from anon, authenticated;
grant select on public.ajuda_perguntas to anon, authenticated;
drop policy if exists "ajuda: todos leem as ativas" on public.ajuda_perguntas;
create policy "ajuda: todos leem as ativas" on public.ajuda_perguntas for select to anon
  using (ativa);
drop policy if exists "ajuda: contas leem as ativas e a equipe todas" on public.ajuda_perguntas;
create policy "ajuda: contas leem as ativas e a equipe todas" on public.ajuda_perguntas for select to authenticated
  using (ativa or public.e_admin());

insert into public.ajuda_perguntas (publico, categoria, pergunta, resposta, ordem)
select * from (values
  ('cliente', 'Pedidos', 'Como peço um serviço?',
   'Na tela Início, escolha a profissão. O mapa mostra os profissionais perto de você, com nota, preço médio e tempo de resposta. Abra o perfil, toque em "Pedir" e descreva o que precisa. O pedido vai só para o profissional que você escolheu.', 10),
  ('cliente', 'Pedidos', 'O profissional não respondeu. E agora?',
   'Cada profissional tem 5 minutos para responder. Se o prazo passar, toque em "Pedir a outro profissional" e o app mostra os próximos mais bem avaliados perto de você.', 20),
  ('cliente', 'Pedidos', 'Posso agendar para outro dia?',
   'Sim. Você pode agendar para até 7 dias à frente. O profissional confirma o horário ou sugere outro, e os dois recebem um lembrete na véspera.', 30),
  ('cliente', 'Pagamento', 'Quanto custa o serviço?',
   'O preço é definido pelo profissional e aparece no perfil dele. O app mostra também a faixa de preço da sua região, para você comparar antes de pedir.', 40),
  ('cliente', 'Segurança', 'Os profissionais são conferidos?',
   'Sim. Todo profissional envia documento com foto, selfie e certidões de antecedentes criminais (Polícia Federal e Justiça do DF). Uma pessoa da equipe confere tudo antes de liberar o perfil.', 50),
  ('cliente', 'Segurança', 'O que faço numa emergência durante o serviço?',
   'No acompanhamento do pedido, toque no botão de emergência. A equipe do iService é avisada na hora e liga para você. Se houver risco, ligue para o 190 (polícia) ou 192 (SAMU).', 60),
  ('cliente', 'Garantia', 'O serviço não ficou bom. Como reclamo?',
   'Você tem a Garantia iService de 30 dias depois do serviço concluído. Abra o pedido e toque em "Abrir reclamação". A nossa equipe conversa com você e com o profissional para resolver.', 70),
  ('cliente', 'Conta', 'Como excluo a minha conta?',
   'Vá em Perfil, Conta e dados, Excluir conta. Seus dados são apagados conforme a nossa Política de Privacidade.', 80),
  ('profissional', 'Cadastro', 'Quanto tempo leva a análise do cadastro?',
   'Até 2 dias úteis depois que você envia tudo. Se faltar algo, avisamos pelo app e por e-mail o que precisa corrigir.', 10),
  ('profissional', 'Cadastro', 'Por que preciso enviar antecedentes criminais?',
   'Você entra na casa das pessoas, e a certidão é o que dá confiança ao cliente. As certidões da Polícia Federal e do TJDFT são gratuitas e saem pela internet em poucos minutos. Valem 12 meses; avisamos antes de vencer.', 20),
  ('profissional', 'Pedidos', 'Como recebo pedidos?',
   'Ative o modo disponível na tela Início. Os clientes perto de você veem o seu perfil, e cada pedido chega só para você. Responda em até 5 minutos: quem responde rápido aparece mais no ranking.', 30),
  ('profissional', 'Pedidos', 'Como apareço mais no topo?',
   'O ranking considera principalmente as suas avaliações, e também o tempo de resposta. Atenda bem, responda rápido e mantenha o perfil completo, com fotos dos seus trabalhos.', 40),
  ('profissional', 'Pagamento', 'Quem define o meu preço?',
   'Você. Informe o valor médio por serviço ou por diária no seu perfil. O app mostra ao cliente a faixa de preço da região para ajudar na escolha.', 50),
  ('profissional', 'Segurança', 'Tive um problema com um cliente. O que faço?',
   'Se houver risco, use o botão de emergência no pedido ou ligue para o 190. Depois, denuncie o cliente pelo menu do pedido. A equipe analisa toda denúncia.', 60),
  ('todos', 'Atendimento', 'Como falo com o suporte do iService?',
   'Pelo WhatsApp do iService ou pelo e-mail suporte@iservice.app.br. Emergências durante um serviço têm atendimento 24 horas pelo botão de emergência.', 90)
) as v(publico, categoria, pergunta, resposta, ordem)
where not exists (select 1 from public.ajuda_perguntas);

create or replace function public.admin_salvar_pergunta(p_id bigint, p_publico text, p_categoria text, p_pergunta text,
  p_resposta text, p_ordem integer default 100, p_ativa boolean default true)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  perform public.exigir_permissao('comunicados');
  if p_id is null then
    insert into public.ajuda_perguntas (publico, categoria, pergunta, resposta, ordem, ativa)
    values (p_publico, btrim(p_categoria), btrim(p_pergunta), btrim(p_resposta), coalesce(p_ordem, 100), coalesce(p_ativa, true))
    returning id into v_id;
  else
    update public.ajuda_perguntas set publico = p_publico, categoria = btrim(p_categoria), pergunta = btrim(p_pergunta),
      resposta = btrim(p_resposta), ordem = coalesce(p_ordem, 100), ativa = coalesce(p_ativa, true), atualizada_em = now()
    where id = p_id returning id into v_id;
    if v_id is null then perform public.erro('nao_encontrado', 'Pergunta não encontrada.'); end if;
  end if;
  perform public.registrar_acao('ajuda_salvar', v_id::text, jsonb_build_object('pergunta', p_pergunta));
  return v_id;
end;
$$;

create or replace function public.admin_apagar_pergunta(p_id bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('comunicados');
  delete from public.ajuda_perguntas where id = p_id;
  if not found then perform public.erro('nao_encontrado', 'Pergunta não encontrada.'); end if;
  perform public.registrar_acao('ajuda_apagar', p_id::text, '{}'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Indicadores do suporte
-- ---------------------------------------------------------------------------
create or replace function public.admin_indicadores_suporte(p_dias integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_desde timestamptz := now() - make_interval(days => greatest(least(coalesce(p_dias, 30), 365), 1));
begin
  perform public.exigir_permissao('relatorios');
  return (
    with base as (
      select 'email' as canal, c.gravidade, c.criada_em as desde, c.primeira_resposta_em as resp
      from public.suporte_conversas c where c.criada_em >= v_desde
      union all
      select 'garantia', r.gravidade, r.criada_em, r.primeira_resposta_em from public.reclamacoes r where r.criada_em >= v_desde
      union all
      select 'denuncia', d.gravidade, d.criada_em, d.primeira_resposta_em from public.denuncias d where d.criada_em >= v_desde
      union all
      select 'emergencia', 1::smallint, e.criada_em, coalesce(e.contato_em, e.atendida_em) from public.emergencias e where e.criada_em >= v_desde
    ), calc as (
      select canal, gravidade, resp is not null as respondido,
        extract(epoch from resp - desde) / 60 as minutos,
        coalesce(resp, now()) <= public.prazo_resposta(gravidade, desde) as no_prazo
      from base
    )
    select jsonb_build_object(
      'dias', p_dias,
      'total', count(*),
      'sem_resposta', count(*) filter (where not respondido),
      'no_prazo_pct', round(100.0 * count(*) filter (where no_prazo) / nullif(count(*), 0)),
      'mediana_minutos', round((percentile_cont(0.5) within group (order by minutos))::numeric),
      'canais', coalesce((
        select jsonb_agg(jsonb_build_object('canal', canal, 'total', total, 'sem_resposta', sem, 'no_prazo_pct', pct, 'mediana_minutos', med) order by ord)
        from (
          select canal, count(*) total, count(*) filter (where not respondido) sem,
            round(100.0 * count(*) filter (where no_prazo) / nullif(count(*), 0)) pct,
            round((percentile_cont(0.5) within group (order by minutos))::numeric) med,
            array_position(array['emergencia', 'denuncia', 'garantia', 'email'], canal) ord
          from calc group by canal
        ) x), '[]'::jsonb),
      'gravidades', coalesce((
        select jsonb_agg(jsonb_build_object('gravidade', gravidade, 'total', total, 'no_prazo_pct', pct) order by gravidade)
        from (
          select gravidade, count(*) total, round(100.0 * count(*) filter (where no_prazo) / nullif(count(*), 0)) pct
          from calc group by gravidade
        ) y), '[]'::jsonb))
    from calc
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------------
revoke all on function public.horario_atendimento(), public.em_horario_atendimento(timestamptz),
  public.somar_minutos_atendimento(timestamptz, integer), public.prazo_resposta(integer, timestamptz),
  public.gravidade_sugerida(text), public.permissao_do_atendimento(text) from public, anon;
grant execute on function public.horario_atendimento(), public.em_horario_atendimento(timestamptz) to anon, authenticated;
grant execute on function public.somar_minutos_atendimento(timestamptz, integer), public.prazo_resposta(integer, timestamptz),
  public.gravidade_sugerida(text), public.permissao_do_atendimento(text) to authenticated;
revoke all on function public.suporte_prazo_mensagem(), public.reclamacao_prazo(), public.denuncia_prazo(),
  public.avisar_emergencia() from public, anon, authenticated;
revoke all on function public.admin_prazos(text, bigint[]), public.admin_definir_gravidade(text, bigint, integer),
  public.admin_atendimento(), public.admin_salvar_horario(integer[], text, text), public.admin_definir_plantao(text, boolean),
  public.admin_salvar_pergunta(bigint, text, text, text, text, integer, boolean), public.admin_apagar_pergunta(bigint),
  public.admin_indicadores_suporte(integer) from public, anon;
grant execute on function public.admin_prazos(text, bigint[]), public.admin_definir_gravidade(text, bigint, integer),
  public.admin_atendimento(), public.admin_salvar_horario(integer[], text, text), public.admin_definir_plantao(text, boolean),
  public.admin_salvar_pergunta(bigint, text, text, text, text, integer, boolean), public.admin_apagar_pergunta(bigint),
  public.admin_indicadores_suporte(integer) to authenticated;
