-- Agenda de até 7 dias.
--
-- Antes o iService era só "agora" ou "hoje"; o horário combinado servia apenas
-- quando o cliente já tinha combinado por fora. Agora, quando o profissional está
-- ocupado (ou o cliente prefere outro dia), os dois marcam um dia dentro do limite:
--
--  1. O cliente pede para um dia e horário (quando = 'combinado'), mesmo com o
--     profissional ocupado agora. O pedido continua indo só para ele.
--  2. O profissional confirma, recusa ou sugere outro horário (propor_horario).
--  3. Se ele sugerir, o cliente confirma ou recusa (responder_proposta).
--     Um pedido "agora" ou "hoje" também pode virar agendado por esse caminho.
--  4. Confirmado, os dois recebem o aviso "marcado para o dia X" (push com o som
--     da marca e e-mail) e lembretes na véspera e 1 hora antes (lembrar_agendamentos).
--
-- O limite de dias fica em app_config.dias_max_combinado (7 hoje; trocar para 30
-- vira agenda mensal sem mudar código). Prazos e lembretes também ficam lá.

-- ---------------------------------------------------------------------------
-- 1. Configurações
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao) values
  ('dias_max_combinado', '7'::jsonb, 'Até quantos dias à frente cliente e profissional podem marcar um atendimento (7 = semana; 30 = mês).'),
  ('prazo_resposta_agendado_min', '120'::jsonb, 'Minutos que o profissional tem para responder um pedido agendado para outro horário.'),
  ('prazo_resposta_proposta_min', '120'::jsonb, 'Minutos que o cliente tem para responder ao horário sugerido pelo profissional.'),
  ('lembrete_antes_min', '60'::jsonb, 'Minutos antes do horário marcado em que os dois recebem o último lembrete.'),
  ('max_agendados_aguardando', '3'::jsonb, 'Quantos pedidos agendados um cliente pode ter aguardando resposta ao mesmo tempo.')
on conflict (chave) do update set descricao = excluded.descricao;

-- ---------------------------------------------------------------------------
-- 2. Pedidos: horário sugerido pelo profissional e controle dos lembretes
-- ---------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists proposta_para timestamptz,       -- horário sugerido pelo profissional, aguardando o cliente
  add column if not exists proposta_em timestamptz,
  add column if not exists lembrete_vespera_em timestamptz,
  add column if not exists lembrete_hora_em timestamptz;

create index if not exists pedidos_agenda_idx on public.pedidos (combinado_para)
  where status = 'aceito' and quando = 'combinado';

-- "sexta, 14/11 às 09:00" · "amanhã às 09:00" · "hoje às 15:30" (horário de Brasília).
create or replace function public.texto_dia_hora(p timestamptz)
returns text
language plpgsql stable
set search_path = public
as $$
declare
  l timestamp := p at time zone 'America/Sao_Paulo';
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  dia text;
begin
  if p is null then return ''; end if;
  if l::date = hoje then dia := 'hoje';
  elsif l::date = hoje + 1 then dia := 'amanhã';
  else
    dia := (array['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'])[extract(dow from l)::int + 1]
           || ', ' || to_char(l, 'DD/MM');
  end if;
  return dia || ' às ' || to_char(l, 'HH24:MI');
end;
$$;

-- Prazo de resposta de um pedido agendado: o configurado, mas nunca depois de
-- 15 minutos antes do horário (e no mínimo 5 minutos).
create or replace function public.prazo_agendado(p_para timestamptz, p_chave text)
returns timestamptz
language sql stable
set search_path = public
as $$
  select greatest(now() + interval '5 minutes',
                  least(now() + make_interval(mins => public.cfg_num(p_chave, 120)::int), p_para - interval '15 minutes'))
$$;

-- Horário dentro do limite da agenda (de 30 minutos a dias_max_combinado dias).
create or replace function public.validar_horario_agenda(p_para timestamptz)
returns void
language plpgsql stable
set search_path = public
as $$
declare
  v_dias int := public.cfg_num('dias_max_combinado', 7)::int;
begin
  if p_para is null or p_para < now() + interval '30 minutes' or p_para > now() + make_interval(days => v_dias) then
    perform public.erro('horario_invalido', 'Escolha um horário entre daqui a 30 minutos e os próximos ' || v_dias || ' dias.');
  end if;
end;
$$;

-- Aviso "marcado" para os dois lados (push com o som da marca + e-mail).
create or replace function public.avisar_agendamento(p_ped public.pedidos)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_cliente text;
  v_pro text;
  v_servico text;
  v_quando text := public.texto_dia_hora(p_ped.combinado_para);
begin
  select split_part(nome, ' ', 1) into v_cliente from public.perfis where id = p_ped.cliente_id;
  select split_part(nome, ' ', 1) into v_pro from public.perfis where id = p_ped.profissional_id;
  select nome into v_servico from public.profissoes where id = p_ped.profissao_id;
  perform public.notificar(p_ped.cliente_id, 'agendamento_confirmado', 'Marcado: ' || v_quando,
    v_pro || ' confirmou o atendimento (' || coalesce(v_servico, 'serviço') || '). Avisaremos você na véspera e 1 hora antes.',
    jsonb_build_object('pedido_id', p_ped.id, 'combinado_para', p_ped.combinado_para, 'com', v_pro, 'endereco', p_ped.endereco_texto));
  perform public.notificar(p_ped.profissional_id, 'agendamento_confirmado', 'Marcado: ' || v_quando,
    'Atendimento com ' || v_cliente || ' em ' || p_ped.endereco_texto || '. Está na sua Agenda.',
    jsonb_build_object('pedido_id', p_ped.id, 'combinado_para', p_ped.combinado_para, 'com', v_cliente, 'endereco', p_ped.endereco_texto));
end;
$$;
revoke all on function public.avisar_agendamento(public.pedidos) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Criar pedido: agendar mesmo com o profissional ocupado agora
-- ---------------------------------------------------------------------------
create or replace function public.criar_pedido(
  p_profissional uuid,
  p_profissao text,
  p_endereco_id bigint,
  p_quando public.quando_pedido,
  p_especialidade bigint default null,
  p_descricao text default '',
  p_janela text default null,
  p_combinado_para timestamptz default null,
  p_fotos text[] default '{}'
)
returns public.pedidos
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_end public.enderecos;
  v_pro public.profissionais;
  v_ped public.pedidos;
  v_nome_cliente text;
  v_preco numeric;
  v_dist numeric;
  v_agendado boolean := p_quando = 'combinado';
begin
  if v_uid is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if not coalesce((select e_cliente from public.perfis where id = v_uid), false) then
    perform public.erro('cadastro_incompleto', 'Complete seu cadastro, com foto, para fazer pedidos.');
  end if;
  if v_uid = p_profissional then perform public.erro('pedido_proprio', 'Você não pode contratar a si mesmo.'); end if;

  select * into v_end from public.enderecos where id = p_endereco_id and usuario_id = v_uid;
  if v_end.id is null then perform public.erro('endereco_invalido', 'Escolha um endereço válido.'); end if;

  select * into v_pro from public.profissionais where id = p_profissional;
  if v_pro.id is null or v_pro.status <> 'aprovado' then
    perform public.erro('profissional_indisponivel', 'Este profissional não está disponível.');
  end if;
  if not exists (select 1 from public.profissional_profissoes where profissional_id = p_profissional and profissao_id = p_profissao) then
    perform public.erro('profissao_invalida', 'Este profissional não atende essa profissão.');
  end if;
  if p_especialidade is not null then
    select x.preco into v_preco from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
    where x.profissional_id = p_profissional and x.especialidade_id = p_especialidade and e.profissao_id = p_profissao;
    if not found then perform public.erro('especialidade_invalida', 'Este profissional não oferece essa especialidade.'); end if;
  end if;

  v_dist := round((extensions.st_distance(public.centro_publico(v_pro.area_centro), v_end.localizacao) / 1000)::numeric, 2);
  if v_pro.area_centro is null or v_dist > public.alcance_km(v_pro.area_raio_km, v_pro.plano, v_pro.plano_valido_ate) then
    perform public.erro('fora_da_area', 'Este profissional não atende o seu endereço.');
  end if;

  if not v_agendado then
    if not v_pro.disponivel or public.em_atendimento(p_profissional) then
      perform public.erro('profissional_ocupado', 'Este profissional está ocupado agora. Agende para outro horário ou escolha outro.');
    end if;
    if exists (select 1 from public.pedidos where cliente_id = v_uid and status = 'solicitado' and quando <> 'combinado' and responder_ate > now()) then
      perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando resposta.');
    end if;
  else
    -- Agendar não depende de o profissional estar disponível agora.
    perform public.validar_horario_agenda(p_combinado_para);
    if exists (select 1 from public.pedidos where cliente_id = v_uid and profissional_id = p_profissional
               and status = 'solicitado' and responder_ate > now()) then
      perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando a resposta deste profissional.');
    end if;
    if (select count(*) from public.pedidos where cliente_id = v_uid and status = 'solicitado' and quando = 'combinado' and responder_ate > now())
       >= public.cfg_num('max_agendados_aguardando', 3) then
      perform public.erro('pedido_aguardando', 'Você já tem muitos agendamentos aguardando resposta. Espere um deles responder.');
    end if;
  end if;

  insert into public.pedidos (
    cliente_id, profissional_id, profissao_id, especialidade_id, descricao, fotos, quando, janela, combinado_para,
    endereco_id, endereco_texto, regiao_id, localizacao, distancia_km, preco_informado, taxa_urgencia, responder_ate
  ) values (
    v_uid, p_profissional, p_profissao, p_especialidade, coalesce(p_descricao, ''), coalesce(p_fotos, '{}'), p_quando,
    case when p_quando = 'hoje' then coalesce(p_janela, 'Hoje') when v_agendado then null else p_janela end,
    case when v_agendado then p_combinado_para end,
    v_end.id,
    concat_ws(', ', v_end.logradouro, v_end.bloco, v_end.numero, v_end.complemento, v_end.cidade || '/' || v_end.uf),
    v_end.regiao_id, v_end.localizacao, v_dist, v_preco,
    case when p_quando = 'agora' then public.cfg_num('taxa_urgencia', 15) else 0 end,
    case when v_agendado then public.prazo_agendado(p_combinado_para, 'prazo_resposta_agendado_min')
         else now() + make_interval(mins => public.cfg_num('prazo_resposta_min', 10)::int) end
  ) returning * into v_ped;

  update public.profissionais set pedidos_recebidos = pedidos_recebidos + 1 where id = p_profissional;
  select split_part(nome, ' ', 1) into v_nome_cliente from public.perfis where id = v_uid;
  if v_agendado then
    perform public.notificar(p_profissional, 'pedido_novo', v_nome_cliente || ' quer agendar: ' || public.texto_dia_hora(p_combinado_para),
      'Confirme, recuse ou sugira outro horário até as ' || to_char(v_ped.responder_ate at time zone 'America/Sao_Paulo', 'HH24:MI') || '.',
      jsonb_build_object('pedido_id', v_ped.id));
  else
    perform public.notificar(p_profissional, 'pedido_novo', 'Novo pedido de ' || v_nome_cliente,
      'Você tem ' || public.cfg_num('prazo_resposta_min', 10) || ' minutos para responder.', jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Prazo: pedido sem resposta, ou horário sugerido sem resposta do cliente
-- ---------------------------------------------------------------------------
create or replace function public.expirar_pedidos()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    update public.pedidos set status = 'expirado', encerrado_em = now(),
      motivo = case when proposta_para is not null then 'O cliente não respondeu ao horário sugerido' else 'Sem resposta no prazo' end
    where status = 'solicitado' and responder_ate <= now()
    returning id, cliente_id, profissional_id, proposta_para
  loop
    n := n + 1;
    if r.proposta_para is not null then
      -- O profissional respondeu (sugeriu outro horário): não conta como pedido perdido.
      perform public.notificar(r.cliente_id, 'pedido_expirado', 'O horário sugerido não foi confirmado',
        'O pedido foi encerrado. Você pode agendar de novo ou escolher outro profissional.', jsonb_build_object('pedido_id', r.id));
      perform public.notificar(r.profissional_id, 'pedido_expirado', 'O cliente não confirmou o horário',
        'O pedido foi encerrado sem prejuízo para você.', jsonb_build_object('pedido_id', r.id));
    else
      update public.profissionais set pedidos_perdidos = pedidos_perdidos + 1 where id = r.profissional_id;
      perform public.notificar(r.cliente_id, 'pedido_expirado', 'O profissional não respondeu a tempo',
        'Escolha outro profissional recomendado para o seu serviço.', jsonb_build_object('pedido_id', r.id));
      perform public.notificar(r.profissional_id, 'pedido_expirado', 'Pedido expirado',
        'O prazo de resposta acabou e o pedido foi encerrado.', jsonb_build_object('pedido_id', r.id));
    end if;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Profissional responde: aceitar, recusar (sugerir outro horário é a seção 6)
-- ---------------------------------------------------------------------------
create or replace function public.responder_pedido(p_pedido uuid, p_aceitar boolean, p_motivo text default null)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  perform public.expirar_pedidos();
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  -- Fora do prazo não aceita: devolve o pedido já expirado (sem erro, para a expiração ficar gravada).
  if v_ped.status = 'expirado' then return v_ped; end if;
  if v_ped.status <> 'solicitado' then perform public.erro('pedido_ja_respondido', 'Este pedido já foi respondido.'); end if;
  if v_ped.proposta_para is not null then
    perform public.erro('aguardando_cliente', 'Você já sugeriu outro horário. Agora é a vez do cliente confirmar.');
  end if;
  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();

  if p_aceitar then
    if v_ped.quando <> 'combinado' and public.em_atendimento(auth.uid()) then
      perform public.erro('em_atendimento', 'Conclua o atendimento atual antes de aceitar outro pedido agora. Você pode sugerir outro horário.');
    end if;
    update public.pedidos set status = 'aceito', aceito_em = now() where id = p_pedido returning * into v_ped;
    update public.profissionais set pedidos_aceitos = pedidos_aceitos + 1 where id = auth.uid();
    if v_ped.quando = 'combinado' then
      perform public.avisar_agendamento(v_ped);
    else
      perform public.notificar(v_ped.cliente_id, 'pedido_aceito', v_nome || ' aceitou seu pedido', 'Acompanhe pelo app.', jsonb_build_object('pedido_id', v_ped.id));
    end if;
  else
    update public.pedidos set status = 'recusado', encerrado_em = now(), motivo = p_motivo where id = p_pedido returning * into v_ped;
    update public.profissionais set pedidos_perdidos = pedidos_perdidos + 1 where id = auth.uid();
    perform public.notificar(v_ped.cliente_id, 'pedido_recusado',
      case when v_ped.quando = 'combinado' then v_nome || ' não pode nesse horário' else v_nome || ' não pode atender agora' end,
      'Escolha outro profissional recomendado para o seu serviço.', jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Profissional sugere outro horário (ocupado agora, ou o horário não dá)
-- ---------------------------------------------------------------------------
create or replace function public.propor_horario(p_pedido uuid, p_para timestamptz)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  perform public.expirar_pedidos();
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status = 'expirado' then return v_ped; end if;
  if v_ped.status <> 'solicitado' then perform public.erro('pedido_ja_respondido', 'Este pedido já foi respondido.'); end if;
  if v_ped.proposta_para is not null then
    perform public.erro('aguardando_cliente', 'Você já sugeriu um horário. Aguarde o cliente.');
  end if;
  perform public.validar_horario_agenda(p_para);
  if v_ped.quando = 'combinado' and v_ped.combinado_para = p_para then
    perform public.erro('mesmo_horario', 'Esse é o horário que o cliente pediu. Toque em Aceitar.');
  end if;

  update public.pedidos set proposta_para = p_para, proposta_em = now(),
    responder_ate = public.prazo_agendado(p_para, 'prazo_resposta_proposta_min')
  where id = p_pedido returning * into v_ped;

  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();
  perform public.notificar(v_ped.cliente_id, 'pedido_proposta', v_nome || ' sugeriu ' || public.texto_dia_hora(p_para),
    'Confirme no app até as ' || to_char(v_ped.responder_ate at time zone 'America/Sao_Paulo', 'HH24:MI') || ' para garantir o horário.',
    jsonb_build_object('pedido_id', v_ped.id));
  return v_ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Cliente responde ao horário sugerido
-- ---------------------------------------------------------------------------
create or replace function public.responder_proposta(p_pedido uuid, p_aceitar boolean)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  perform public.expirar_pedidos();
  select * into v_ped from public.pedidos where id = p_pedido and cliente_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status = 'expirado' then return v_ped; end if;
  if v_ped.status <> 'solicitado' or v_ped.proposta_para is null then
    perform public.erro('sem_proposta', 'Não há horário sugerido para responder.');
  end if;
  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();

  if p_aceitar then
    if v_ped.proposta_para < now() + interval '15 minutes' then
      perform public.erro('horario_invalido', 'Esse horário já passou. Peça outro ao profissional.');
    end if;
    -- Vira agendado: sem janela e sem taxa de urgência.
    update public.pedidos set quando = 'combinado', combinado_para = proposta_para, janela = null, taxa_urgencia = 0,
      proposta_para = null, status = 'aceito', aceito_em = now()
    where id = p_pedido returning * into v_ped;
    update public.profissionais set pedidos_aceitos = pedidos_aceitos + 1 where id = v_ped.profissional_id;
    perform public.avisar_agendamento(v_ped);
  else
    update public.pedidos set status = 'cancelado', encerrado_em = now(), cancelado_por = auth.uid(),
      motivo = 'O horário sugerido não serviu para o cliente'
    where id = p_pedido returning * into v_ped;
    perform public.notificar(v_ped.profissional_id, 'pedido_cancelado', v_nome || ' não pôde no horário sugerido',
      'O pedido foi encerrado sem prejuízo para você.', jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Lembretes: véspera e 1 hora antes (pg_cron a cada 5 minutos)
-- ---------------------------------------------------------------------------
create or replace function public.lembrar_agendamentos()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
  v_antes int := public.cfg_num('lembrete_antes_min', 60)::int;
  v_quando text;
begin
  -- Véspera: quando falta menos de 24 h (e mais que o lembrete final), se foi
  -- marcado com antecedência (quem marcou há pouco acabou de receber a confirmação).
  for r in
    update public.pedidos p set lembrete_vespera_em = now()
    where p.status = 'aceito' and p.quando = 'combinado' and p.lembrete_vespera_em is null
      and p.combinado_para between now() + make_interval(mins => v_antes + 30) and now() + interval '24 hours'
      and p.aceito_em < now() - interval '3 hours'
    returning p.*
  loop
    n := n + 1;
    v_quando := public.texto_dia_hora(r.combinado_para);
    perform public.notificar(r.cliente_id, 'lembrete_agendamento', 'Lembrete: atendimento ' || v_quando,
      (select split_part(nome, ' ', 1) from public.perfis where id = r.profissional_id) || ' vai até ' || r.endereco_texto || '.',
      jsonb_build_object('pedido_id', r.id, 'combinado_para', r.combinado_para, 'etapa', 'vespera',
                         'com', (select split_part(nome, ' ', 1) from public.perfis where id = r.profissional_id), 'endereco', r.endereco_texto));
    perform public.notificar(r.profissional_id, 'lembrete_agendamento', 'Lembrete: atendimento ' || v_quando,
      'Com ' || (select split_part(nome, ' ', 1) from public.perfis where id = r.cliente_id) || ' em ' || r.endereco_texto || '.',
      jsonb_build_object('pedido_id', r.id, 'combinado_para', r.combinado_para, 'etapa', 'vespera',
                         'com', (select split_part(nome, ' ', 1) from public.perfis where id = r.cliente_id), 'endereco', r.endereco_texto));
  end loop;

  -- Lembrete final (padrão 1 hora antes). Só push, sem e-mail.
  for r in
    update public.pedidos p set lembrete_hora_em = now()
    where p.status = 'aceito' and p.quando = 'combinado' and p.lembrete_hora_em is null
      and p.combinado_para between now() and now() + make_interval(mins => v_antes)
    returning p.*
  loop
    n := n + 1;
    v_quando := to_char(r.combinado_para at time zone 'America/Sao_Paulo', 'HH24:MI');
    perform public.notificar(r.cliente_id, 'lembrete_agendamento_hora', 'Hoje às ' || v_quando || ': seu atendimento',
      (select split_part(nome, ' ', 1) from public.perfis where id = r.profissional_id) || ' avisa pelo app quando sair para o seu endereço.',
      jsonb_build_object('pedido_id', r.id));
    perform public.notificar(r.profissional_id, 'lembrete_agendamento_hora', 'Hoje às ' || v_quando || ': atendimento marcado',
      'Toque em "Estou a caminho" quando sair. Endereço: ' || r.endereco_texto || '.',
      jsonb_build_object('pedido_id', r.id));
  end loop;
  return n;
end;
$$;
revoke all on function public.lembrar_agendamentos() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iservice-lembrar-agendamentos', '*/5 * * * *', 'select public.lembrar_agendamentos()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Horários já marcados de um profissional (o cliente vê só os horários)
-- ---------------------------------------------------------------------------
create or replace function public.horarios_ocupados(p_profissional uuid)
returns table (inicio timestamptz)
language sql stable security definer
set search_path = public
as $$
  select p.combinado_para
  from public.pedidos p
  where p.profissional_id = p_profissional and p.quando = 'combinado'
    and p.status in ('aceito', 'a_caminho', 'em_atendimento')
    and p.combinado_para between now() - interval '3 hours' and now() + make_interval(days => public.cfg_num('dias_max_combinado', 7)::int + 1)
  order by 1
$$;
revoke all on function public.horarios_ocupados(uuid) from public, anon;
grant execute on function public.horarios_ocupados(uuid) to authenticated;

revoke all on function public.propor_horario(uuid, timestamptz) from public, anon;
grant execute on function public.propor_horario(uuid, timestamptz) to authenticated;
revoke all on function public.responder_proposta(uuid, boolean) from public, anon;
grant execute on function public.responder_proposta(uuid, boolean) to authenticated;
grant execute on function public.texto_dia_hora(timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Lista de pedidos: com o horário sugerido
-- ---------------------------------------------------------------------------
drop function if exists public.meus_pedidos(text, text, integer);
create function public.meus_pedidos(p_papel text default 'cliente', p_grupo text default 'todos', p_limite integer default 50)
returns table (
  id uuid, codigo text, status public.status_pedido, quando public.quando_pedido, janela text, combinado_para timestamptz,
  profissao_id text, especialidade text, descricao text, endereco_texto text, distancia_km numeric,
  preco_informado numeric, taxa_urgencia numeric, valor_cobrado numeric, responder_ate timestamptz, criado_em timestamptz,
  concluido_em timestamptz, outra_parte_id uuid, outra_parte_nome text, outra_parte_foto text, avaliado boolean, nao_lidas integer,
  proposta_para timestamptz
)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.codigo, p.status, p.quando, p.janela, p.combinado_para, p.profissao_id, e.nome, p.descricao, p.endereco_texto,
    p.distancia_km, p.preco_informado, p.taxa_urgencia, p.valor_cobrado, p.responder_ate, p.criado_em, p.concluido_em,
    o.id, o.nome, o.foto_url,
    exists (select 1 from public.avaliacoes a where a.pedido_id = p.id),
    (select count(*) from public.mensagens m where m.pedido_id = p.id and m.autor_id <> auth.uid() and m.lida_em is null)::int,
    p.proposta_para
  from public.pedidos p
  left join public.especialidades e on e.id = p.especialidade_id
  join public.perfis o on o.id = case when p_papel = 'profissional' then p.cliente_id else p.profissional_id end
  where (case when p_papel = 'profissional' then p.profissional_id else p.cliente_id end) = auth.uid()
    and case p_grupo
      when 'andamento' then p.status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento')
      when 'concluidos' then p.status = 'concluido'
      when 'cancelados' then p.status in ('cancelado', 'recusado', 'expirado')
      else true end
  order by p.criado_em desc
  limit p_limite
$$;
revoke all on function public.meus_pedidos(text, text, integer) from public, anon;
grant execute on function public.meus_pedidos(text, text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. E-mail: confirmação do agendamento e lembrete da véspera
-- ---------------------------------------------------------------------------
create or replace function public.tipo_tem_email(p_tipo text)
returns boolean
language sql immutable
as $$ select p_tipo = any (array[
  'boas_vindas', 'cadastro_recebido', 'cadastro_aprovado', 'cadastro_recusado', 'documento_recusado',
  'reclamacao_aberta', 'reclamacao_recebida', 'garantia', 'conta_suspensa', 'conta_reativada', 'exclusao_conta',
  'agendamento_confirmado', 'lembrete_agendamento'
]) $$;

-- Os horários e o "hoje" seguem Brasília.
alter function public.lembrar_agendamentos() set timezone = 'America/Sao_Paulo';
