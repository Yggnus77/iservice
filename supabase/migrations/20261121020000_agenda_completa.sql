-- Agenda completa do profissional (pedido do usuário em 21/11/2026).
--
--   1. Horário de trabalho por dia da semana. Sem horário salvo, vale o padrão
--      de antes (qualquer horário; o app sugere das 7h às 21h).
--   2. Bloqueios: folga, almoço, compromisso. O cliente não agenda nesses horários.
--   3. Horários realmente livres: o banco recusa agendar fora do expediente, num
--      bloqueio ou em cima de outro atendimento marcado (1 hora para cada lado).
--   4. Remarcar um agendamento já confirmado: um propõe, o outro confirma.
--      Sem resposta no prazo, fica o horário original.
--   5. Cancelamento em cima da hora: o cliente que cancela com menos de
--      cancelamento_gratis_horas (2 h) do horário, ou com o profissional a caminho,
--      paga o deslocamento ao profissional. "Cliente não estava no local" vale o mesmo.
--      Com o pagamento desligado, só fica registrado (nada é cobrado).
--   6. Profissional ocupado agora continua na busca, no fim da lista, marcado como
--      "ocupado", para o cliente que quer esperar por ele poder agendar.

insert into public.app_config (chave, valor, descricao) values
  ('cancelamento_gratis_horas', '2'::jsonb, 'Até quantas horas antes do agendamento o cliente cancela sem custo. Depois disso (ou com o profissional a caminho) o deslocamento fica com o profissional.'),
  ('tolerancia_ausencia_min', '15'::jsonb, 'Minutos depois do horário (ou de sair a caminho) para o profissional poder marcar "cliente não estava no local".'),
  ('max_remarcacoes', '2'::jsonb, 'Quantas vezes um agendamento confirmado pode ser remarcado.'),
  ('prazo_resposta_remarcar_min', '120'::jsonb, 'Minutos para a outra pessoa responder a um pedido de remarcação. Sem resposta, fica o horário original.')
on conflict (chave) do nothing;

-- Valor em reais para os textos dos avisos: R$ 26,50.
create or replace function public.reais(p_valor numeric)
returns text
language sql immutable
set search_path = public
as $$ select 'R$ ' || replace(to_char(coalesce(p_valor, 0), 'FM999999990.00'), '.', ',') $$;

-- ---------------------------------------------------------------------------
-- 1. Horário de trabalho (um intervalo por dia; 0 = domingo ... 6 = sábado)
-- ---------------------------------------------------------------------------
create table if not exists public.horarios_trabalho (
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  dia smallint not null check (dia between 0 and 6),
  inicio time not null,
  fim time not null,
  primary key (profissional_id, dia),
  check (fim > inicio)
);
alter table public.horarios_trabalho enable row level security;
revoke all on public.horarios_trabalho from anon, authenticated;
grant select on public.horarios_trabalho to authenticated;
drop policy if exists "horarios_trabalho: o próprio" on public.horarios_trabalho;
create policy "horarios_trabalho: o próprio" on public.horarios_trabalho for select to authenticated
  using (profissional_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Bloqueios da agenda
-- ---------------------------------------------------------------------------
create table if not exists public.agenda_bloqueios (
  id bigint generated always as identity primary key,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  inicio timestamptz not null,
  fim timestamptz not null,
  motivo text not null default '' check (length(motivo) <= 80),
  criado_em timestamptz not null default now(),
  check (fim > inicio)
);
create index if not exists agenda_bloqueios_pro on public.agenda_bloqueios (profissional_id, fim);
alter table public.agenda_bloqueios enable row level security;
revoke all on public.agenda_bloqueios from anon, authenticated;
grant select on public.agenda_bloqueios to authenticated;
drop policy if exists "agenda_bloqueios: o próprio" on public.agenda_bloqueios;
create policy "agenda_bloqueios: o próprio" on public.agenda_bloqueios for select to authenticated
  using (profissional_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Pedidos: remarcação e cancelamento em cima da hora
-- ---------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists remarcar_para timestamptz,
  add column if not exists remarcar_por uuid,
  add column if not exists remarcar_ate timestamptz,
  add column if not exists remarcacoes smallint not null default 0,
  add column if not exists taxa_cancelamento numeric(10, 2) not null default 0,
  add column if not exists cancelado_em_cima boolean not null default false,
  add column if not exists cliente_ausente boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3. O horário está livre na agenda do profissional?
--    Devolve null quando está livre ou o motivo: fora_do_expediente, bloqueado, ocupado.
--    p_so_conflito: só confere outros atendimentos (quando é o próprio profissional que escolhe).
-- ---------------------------------------------------------------------------
create or replace function public.motivo_horario_indisponivel(p_profissional uuid, p_para timestamptz, p_ignorar uuid default null, p_so_conflito boolean default false)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_local timestamp := p_para at time zone 'America/Sao_Paulo';
begin
  if not p_so_conflito then
    if exists (select 1 from public.horarios_trabalho where profissional_id = p_profissional)
       and not exists (
         select 1 from public.horarios_trabalho h
         where h.profissional_id = p_profissional and h.dia = extract(dow from v_local)::int
           and v_local::time >= h.inicio and v_local::time < h.fim) then
      return 'fora_do_expediente';
    end if;
    if exists (
      select 1 from public.agenda_bloqueios b
      where b.profissional_id = p_profissional and p_para > b.inicio - interval '1 hour' and p_para < b.fim) then
      return 'bloqueado';
    end if;
  end if;
  if exists (
    select 1 from public.pedidos o
    where o.profissional_id = p_profissional and o.quando = 'combinado'
      and o.status in ('aceito', 'a_caminho', 'em_atendimento')
      and o.id is distinct from p_ignorar
      and abs(extract(epoch from (o.combinado_para - p_para))) < 3600) then
    return 'ocupado';
  end if;
  return null;
end;
$$;
revoke all on function public.motivo_horario_indisponivel(uuid, timestamptz, uuid, boolean) from public, anon, authenticated;

create or replace function public.validar_horario_profissional(p_profissional uuid, p_para timestamptz, p_ignorar uuid default null, p_so_conflito boolean default false)
returns void
language plpgsql stable security definer
set search_path = public
as $$
begin
  case public.motivo_horario_indisponivel(p_profissional, p_para, p_ignorar, p_so_conflito)
    when 'fora_do_expediente' then
      perform public.erro('fora_do_expediente', 'Esse horário está fora do horário de atendimento do profissional. Escolha outro.');
    when 'bloqueado' then
      perform public.erro('horario_bloqueado', 'O profissional não atende nesse horário. Escolha outro.');
    when 'ocupado' then
      perform public.erro('horario_ocupado', 'Esse horário já está marcado com outro cliente. Escolha outro.');
    else null;
  end case;
end;
$$;
revoke all on function public.validar_horario_profissional(uuid, timestamptz, uuid, boolean) from public, anon, authenticated;

-- Agendamento novo (criar_pedido) e horário sugerido pelo profissional passam pela agenda.
create or replace function public.conferir_agenda_do_pedido()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.quando = 'combinado' and new.combinado_para is not null then
      perform public.validar_horario_profissional(new.profissional_id, new.combinado_para, null, false);
    end if;
  elsif new.proposta_para is not null and new.proposta_para is distinct from old.proposta_para then
    -- O próprio profissional escolheu: só não pode encavalar com outro atendimento.
    perform public.validar_horario_profissional(new.profissional_id, new.proposta_para, new.id, true);
  end if;
  return new;
end;
$$;
revoke all on function public.conferir_agenda_do_pedido() from public, anon, authenticated;
drop trigger if exists conferir_agenda_do_pedido on public.pedidos;
create trigger conferir_agenda_do_pedido before insert or update of proposta_para on public.pedidos
  for each row execute function public.conferir_agenda_do_pedido();

-- Agenda de um profissional para escolher horário: expediente, bloqueios e horários marcados.
-- Para o próprio profissional vem também o id e o motivo de cada bloqueio.
create or replace function public.agenda_profissional(p_profissional uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'horario', coalesce((select jsonb_agg(jsonb_build_object('dia', h.dia, 'inicio', to_char(h.inicio, 'HH24:MI'), 'fim', to_char(h.fim, 'HH24:MI')) order by h.dia)
                         from public.horarios_trabalho h where h.profissional_id = p_profissional), '[]'::jsonb),
    'bloqueios', coalesce((select jsonb_agg(
                             case when p_profissional = auth.uid()
                               then jsonb_build_object('id', b.id, 'inicio', b.inicio, 'fim', b.fim, 'motivo', b.motivo)
                               else jsonb_build_object('inicio', b.inicio, 'fim', b.fim) end order by b.inicio)
                           from public.agenda_bloqueios b
                           where b.profissional_id = p_profissional and b.fim > now()
                             and b.inicio < now() + make_interval(days => public.cfg_num('dias_max_combinado', 7)::int + 60)), '[]'::jsonb),
    'ocupados', coalesce((select jsonb_agg(p.combinado_para order by p.combinado_para)
                          from public.pedidos p
                          where p.profissional_id = p_profissional and p.quando = 'combinado'
                            and p.status in ('aceito', 'a_caminho', 'em_atendimento')
                            and p.combinado_para between now() - interval '3 hours'
                                and now() + make_interval(days => public.cfg_num('dias_max_combinado', 7)::int + 1)), '[]'::jsonb)
  )
  where auth.uid() is not null
$$;
revoke all on function public.agenda_profissional(uuid) from public, anon;
grant execute on function public.agenda_profissional(uuid) to authenticated;

-- O profissional salva o horário de trabalho: [{dia, inicio, fim}, ...]. Lista vazia ou null
-- volta ao padrão (qualquer horário).
create or replace function public.salvar_horario_trabalho(p_horario jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r jsonb;
  v_dia int;
  v_ini time;
  v_fim time;
begin
  if not exists (select 1 from public.profissionais where id = auth.uid()) then
    perform public.erro('sem_permissao', 'Só profissionais têm agenda.');
  end if;
  if p_horario is not null and jsonb_typeof(p_horario) <> 'array' then
    perform public.erro('horario_invalido', 'Horário de trabalho inválido.');
  end if;
  delete from public.horarios_trabalho where profissional_id = auth.uid();
  for r in select * from jsonb_array_elements(coalesce(p_horario, '[]'::jsonb)) loop
    begin
      v_dia := (r ->> 'dia')::int;
      v_ini := (r ->> 'inicio')::time;
      v_fim := (r ->> 'fim')::time;
    exception when others then
      perform public.erro('horario_invalido', 'Horário de trabalho inválido.');
    end;
    if v_dia is null or v_dia not between 0 and 6 or v_ini is null or v_fim is null then
      perform public.erro('horario_invalido', 'Horário de trabalho inválido.');
    end if;
    if v_fim <= v_ini + interval '30 minutes' then
      perform public.erro('horario_invalido', 'O fim do expediente precisa ser pelo menos 30 minutos depois do início.');
    end if;
    insert into public.horarios_trabalho (profissional_id, dia, inicio, fim) values (auth.uid(), v_dia, v_ini, v_fim)
    on conflict (profissional_id, dia) do update set inicio = excluded.inicio, fim = excluded.fim;
  end loop;
end;
$$;
revoke all on function public.salvar_horario_trabalho(jsonb) from public, anon;
grant execute on function public.salvar_horario_trabalho(jsonb) to authenticated;

-- Bloqueia um período. Devolve o id e quantos atendimentos confirmados caem nele
-- (eles continuam marcados: o profissional decide se remarca ou cancela).
create or replace function public.bloquear_horario(p_inicio timestamptz, p_fim timestamptz, p_motivo text default '')
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_conflitos int;
begin
  if not exists (select 1 from public.profissionais where id = auth.uid()) then
    perform public.erro('sem_permissao', 'Só profissionais têm agenda.');
  end if;
  if p_inicio is null or p_fim is null or p_fim <= p_inicio then
    perform public.erro('bloqueio_invalido', 'O fim precisa ser depois do início.');
  end if;
  if p_fim <= now() then perform public.erro('bloqueio_invalido', 'Esse período já passou.'); end if;
  if p_inicio > now() + interval '90 days' or p_fim - p_inicio > interval '31 days' then
    perform public.erro('bloqueio_invalido', 'Bloqueie no máximo 31 dias de cada vez, nos próximos 90 dias.');
  end if;
  if (select count(*) from public.agenda_bloqueios where profissional_id = auth.uid() and fim > now()) >= 60 then
    perform public.erro('bloqueio_invalido', 'Você já tem muitos bloqueios. Apague os que não precisa mais.');
  end if;
  insert into public.agenda_bloqueios (profissional_id, inicio, fim, motivo)
  values (auth.uid(), p_inicio, p_fim, left(btrim(coalesce(p_motivo, '')), 80))
  returning id into v_id;
  select count(*) into v_conflitos from public.pedidos p
  where p.profissional_id = auth.uid() and p.quando = 'combinado' and p.status = 'aceito'
    and p.combinado_para > p_inicio - interval '1 hour' and p.combinado_para < p_fim;
  return jsonb_build_object('id', v_id, 'conflitos', v_conflitos);
end;
$$;
revoke all on function public.bloquear_horario(timestamptz, timestamptz, text) from public, anon;
grant execute on function public.bloquear_horario(timestamptz, timestamptz, text) to authenticated;

create or replace function public.desbloquear_horario(p_id bigint)
returns void
language sql security definer
set search_path = public
as $$ delete from public.agenda_bloqueios where id = p_id and profissional_id = auth.uid() $$;
revoke all on function public.desbloquear_horario(bigint) from public, anon;
grant execute on function public.desbloquear_horario(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Remarcar um agendamento confirmado
-- ---------------------------------------------------------------------------
create or replace function public.remarcar_pedido(p_pedido uuid, p_para timestamptz)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_pelo_pro boolean;
  v_nome text;
  v_outro uuid;
begin
  select * into v_ped from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id) for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status <> 'aceito' or v_ped.quando <> 'combinado' or v_ped.combinado_para <= now() then
    perform public.erro('nao_remarcavel', 'Só dá para remarcar um agendamento confirmado que ainda não começou.');
  end if;
  if v_ped.remarcar_para is not null and v_ped.remarcar_ate > now() then
    perform public.erro('remarcacao_pendente', 'Já existe um pedido de remarcação aguardando resposta.');
  end if;
  if v_ped.remarcacoes >= public.cfg_num('max_remarcacoes', 2) then
    perform public.erro('limite_remarcacoes', 'Este agendamento já foi remarcado o máximo de vezes. Cancele e agende de novo, se precisar.');
  end if;
  perform public.validar_horario_agenda(p_para);
  if p_para = v_ped.combinado_para then perform public.erro('mesmo_horario', 'Esse já é o horário marcado.'); end if;
  v_pelo_pro := v_ped.profissional_id = auth.uid();
  -- O cliente só escolhe horários livres; o profissional pode sair do próprio expediente.
  perform public.validar_horario_profissional(v_ped.profissional_id, p_para, v_ped.id, v_pelo_pro);

  update public.pedidos set remarcar_para = p_para, remarcar_por = auth.uid(),
    remarcar_ate = public.prazo_agendado(least(p_para, combinado_para), 'prazo_resposta_remarcar_min')
  where id = p_pedido returning * into v_ped;

  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();
  v_outro := case when v_pelo_pro then v_ped.cliente_id else v_ped.profissional_id end;
  perform public.notificar(v_outro, 'pedido_remarcar', v_nome || ' pediu para remarcar para ' || public.texto_dia_hora(p_para),
    'Confirme ou mantenha o horário de ' || public.texto_dia_hora(v_ped.combinado_para) || ' até as '
      || to_char(v_ped.remarcar_ate at time zone 'America/Sao_Paulo', 'HH24:MI') || '.',
    jsonb_build_object('pedido_id', v_ped.id));
  return v_ped;
end;
$$;
revoke all on function public.remarcar_pedido(uuid, timestamptz) from public, anon;
grant execute on function public.remarcar_pedido(uuid, timestamptz) to authenticated;

create or replace function public.responder_remarcacao(p_pedido uuid, p_aceitar boolean)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  select * into v_ped from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id) for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.remarcar_para is null or v_ped.status <> 'aceito' then
    perform public.erro('sem_remarcacao', 'Não há pedido de remarcação para responder.');
  end if;
  if v_ped.remarcar_por = auth.uid() then
    perform public.erro('sem_remarcacao', 'Aguarde a outra pessoa responder ao seu pedido de remarcação.');
  end if;
  if v_ped.remarcar_ate <= now() then
    perform public.erro('prazo_remarcacao', 'O prazo para responder acabou. Fica o horário original.');
  end if;
  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();

  if p_aceitar then
    if v_ped.remarcar_para < now() + interval '15 minutes' then
      perform public.erro('horario_invalido', 'Esse horário já passou. Peça outro.');
    end if;
    perform public.validar_horario_profissional(v_ped.profissional_id, v_ped.remarcar_para, v_ped.id, true);
    update public.pedidos set combinado_para = remarcar_para, remarcacoes = remarcacoes + 1,
      remarcar_para = null, remarcar_por = null, remarcar_ate = null,
      lembrete_vespera_em = null, lembrete_hora_em = null
    where id = p_pedido returning * into v_ped;
    perform public.avisar_agendamento(v_ped);
  else
    perform public.notificar(v_ped.remarcar_por, 'pedido_remarcar', v_nome || ' manteve o horário original',
      'O atendimento continua ' || public.texto_dia_hora(v_ped.combinado_para) || '.', jsonb_build_object('pedido_id', v_ped.id));
    update public.pedidos set remarcar_para = null, remarcar_por = null, remarcar_ate = null
    where id = p_pedido returning * into v_ped;
  end if;
  return v_ped;
end;
$$;
revoke all on function public.responder_remarcacao(uuid, boolean) from public, anon;
grant execute on function public.responder_remarcacao(uuid, boolean) to authenticated;

-- Quem pediu pode desistir da remarcação.
create or replace function public.desistir_remarcacao(p_pedido uuid)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
begin
  update public.pedidos set remarcar_para = null, remarcar_por = null, remarcar_ate = null
  where id = p_pedido and remarcar_por = auth.uid() returning * into v_ped;
  if v_ped.id is null then perform public.erro('sem_remarcacao', 'Não há pedido de remarcação seu neste agendamento.'); end if;
  return v_ped;
end;
$$;
revoke all on function public.desistir_remarcacao(uuid) from public, anon;
grant execute on function public.desistir_remarcacao(uuid) to authenticated;

-- Remarcações sem resposta no prazo: fica o horário original (a cada 5 minutos).
create or replace function public.expirar_remarcacoes()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    update public.pedidos p set remarcar_para = null, remarcar_por = null, remarcar_ate = null
    from (select id, remarcar_por from public.pedidos where remarcar_para is not null and remarcar_ate <= now()) v
    where p.id = v.id
    returning p.*, v.remarcar_por as quem
  loop
    n := n + 1;
    if r.status = 'aceito' then
      perform public.notificar(r.quem, 'pedido_remarcar', 'Sem resposta: fica o horário original',
        'O atendimento continua ' || public.texto_dia_hora(r.combinado_para) || '.', jsonb_build_object('pedido_id', r.id));
    end if;
  end loop;
  return n;
end;
$$;
revoke all on function public.expirar_remarcacoes() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'iservice-remarcacoes';
    perform cron.schedule('iservice-remarcacoes', '*/5 * * * *', 'select public.expirar_remarcacoes()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Cancelamento em cima da hora e cliente ausente
-- ---------------------------------------------------------------------------
-- O cliente cancelar agora sai "em cima da hora"? E quanto fica com o profissional?
create or replace function public.previa_cancelamento(p_pedido uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_em_cima boolean;
begin
  select * into v_ped from public.pedidos where id = p_pedido and cliente_id = auth.uid();
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  v_em_cima := v_ped.status = 'a_caminho'
    or (v_ped.status = 'aceito' and v_ped.quando = 'combinado'
        and v_ped.combinado_para < now() + make_interval(hours => public.cfg_num('cancelamento_gratis_horas', 2)::int));
  return jsonb_build_object(
    'em_cima', v_em_cima,
    'a_caminho', v_ped.status = 'a_caminho',
    'horas', public.cfg_num('cancelamento_gratis_horas', 2),
    'taxa', case when v_em_cima and public.pagamento_ativo() then v_ped.deslocamento else 0 end,
    'pode_remarcar', v_ped.status = 'aceito' and v_ped.quando = 'combinado' and v_ped.combinado_para > now()
      and v_ped.remarcacoes < public.cfg_num('max_remarcacoes', 2) and not coalesce(v_ped.remarcar_ate > now(), false)
  );
end;
$$;
revoke all on function public.previa_cancelamento(uuid) from public, anon;
grant execute on function public.previa_cancelamento(uuid) to authenticated;

create or replace function public.cancelar_pedido(p_pedido uuid, p_motivo text default null)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_pelo_pro boolean;
  v_em_cima boolean;
  v_taxa numeric := 0;
begin
  select * into v_ped from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id) for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  v_pelo_pro := v_ped.profissional_id = auth.uid();
  if v_ped.status not in ('solicitado', 'aceito', 'a_caminho') or (v_pelo_pro and v_ped.status = 'solicitado') then
    perform public.erro('nao_cancelavel', 'Este pedido não pode mais ser cancelado.');
  end if;
  v_em_cima := v_ped.status = 'a_caminho'
    or (v_ped.status = 'aceito' and v_ped.quando = 'combinado'
        and v_ped.combinado_para < now() + make_interval(hours => public.cfg_num('cancelamento_gratis_horas', 2)::int));
  if v_em_cima and not v_pelo_pro and public.pagamento_ativo() then v_taxa := v_ped.deslocamento; end if;

  update public.pedidos set status = 'cancelado', encerrado_em = now(), motivo = p_motivo, cancelado_por = auth.uid(),
    cancelado_em_cima = v_em_cima, taxa_cancelamento = v_taxa,
    remarcar_para = null, remarcar_por = null, remarcar_ate = null
  where id = p_pedido returning * into v_ped;
  if v_pelo_pro then
    update public.profissionais set cancelados_pelo_profissional = cancelados_pelo_profissional + 1 where id = auth.uid();
    perform public.notificar(v_ped.cliente_id, 'pedido_cancelado', 'O profissional cancelou o atendimento',
      'Escolha outro profissional recomendado. Sentimos muito pelo transtorno.', jsonb_build_object('pedido_id', v_ped.id));
  else
    perform public.notificar(v_ped.profissional_id, 'pedido_cancelado', 'O cliente cancelou o pedido',
      coalesce(p_motivo, 'O pedido foi cancelado.')
        || case when v_taxa > 0 then ' Como foi em cima da hora, você recebe ' || public.reais(v_taxa) || ' pelo deslocamento.' else '' end,
      jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;
revoke all on function public.cancelar_pedido(uuid, text) from public, anon;
grant execute on function public.cancelar_pedido(uuid, text) to authenticated;

-- O profissional chegou e o cliente não estava: encerra sem contar contra ele.
create or replace function public.marcar_cliente_ausente(p_pedido uuid)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_tol interval := make_interval(mins => public.cfg_num('tolerancia_ausencia_min', 15)::int);
  v_desde timestamptz;
  v_taxa numeric := 0;
begin
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status <> 'a_caminho' then
    perform public.erro('nao_permitido', 'Toque em "Estou a caminho" quando sair para o endereço.');
  end if;
  v_desde := greatest(coalesce(v_ped.a_caminho_em, now()), case when v_ped.quando = 'combinado' then v_ped.combinado_para end);
  if now() < v_desde + v_tol then
    perform public.erro('cedo_demais', 'Espere até as ' || to_char((v_desde + v_tol) at time zone 'America/Sao_Paulo', 'HH24:MI')
      || ' e tente falar com o cliente pelo chat antes.');
  end if;
  if public.pagamento_ativo() then v_taxa := v_ped.deslocamento; end if;
  update public.pedidos set status = 'cancelado', encerrado_em = now(), cancelado_por = auth.uid(),
    motivo = 'O cliente não estava no local', cliente_ausente = true, cancelado_em_cima = true, taxa_cancelamento = v_taxa
  where id = p_pedido returning * into v_ped;
  perform public.notificar(v_ped.cliente_id, 'pedido_cancelado', 'O profissional não encontrou você no local',
    'O atendimento foi encerrado' || case when v_taxa > 0 then ' e o deslocamento (' || public.reais(v_taxa) || ') ficou com o profissional' else '' end
      || '. Se houve engano, fale com o suporte pelo app.',
    jsonb_build_object('pedido_id', v_ped.id));
  return v_ped;
end;
$$;
revoke all on function public.marcar_cliente_ausente(uuid) from public, anon;
grant execute on function public.marcar_cliente_ausente(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Busca: quem está atendendo agora aparece no fim, como "ocupado", para agendar
-- ---------------------------------------------------------------------------
drop function if exists public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer);
drop function if exists public.buscar_profissionais_base(text, double precision, double precision, bigint, text, integer, integer);

create function public.buscar_profissionais_base(p_profissao text, p_lat double precision, p_lng double precision, p_especialidade bigint default null, p_ordem text default 'qualidade', p_rodizio integer default 0, p_limite integer default 50)
returns table (profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer, servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric, novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, fase_lancamento boolean, posicao integer, ocupado boolean)
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_local extensions.geography := public.ponto(p_lat, p_lng);
  v_min_aval int := public.cfg_num('min_avaliacoes_ranking', 5);
  v_min_top int := public.cfg_num('min_profissionais_ranking', 3);
  v_ntop int;
  v_lanc boolean;
begin
  create temporary table if not exists _cand (
    profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer,
    servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric,
    novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, sorteio text, bonus numeric, ocupado boolean
  ) on commit drop;
  -- Sessões antigas podem ter a tabela sem a coluna nova.
  alter table _cand add column if not exists ocupado boolean;
  truncate _cand;

  insert into _cand
  select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos, pr.anos_experiencia, pr.verificado,
    round((extensions.st_distance(public.centro_publico(pr.area_centro), v_local) / 1000)::numeric, 1),
    pr.total_avaliacoes < v_min_aval,
    (select min(x.preco) from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao and (p_especialidade is null or e.id = p_especialidade)),
    array(select e.nome from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao order by e.ordem, e.nome),
    exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    md5(pr.id::text || p_rodizio::text || current_date::text),
    public.bonus_resposta(pr.tempo_resposta_seg, pr.respostas_medidas),
    public.em_atendimento(pr.id)
  from public.profissionais pr
  join public.perfis pe on pe.id = pr.id
  join public.profissional_profissoes pp on pp.profissional_id = pr.id and pp.profissao_id = p_profissao
  where pr.status = 'aprovado'
    and pr.disponivel
    and pr.area_centro is not null
    and pr.id is distinct from auth.uid()
    and extensions.st_dwithin(public.centro_publico(pr.area_centro), v_local, public.alcance_km(pr.area_raio_km, pr.plano, pr.plano_valido_ate) * 1000)
    and (p_especialidade is null or exists (
      select 1 from public.profissional_especialidades x where x.profissional_id = pr.id and x.especialidade_id = p_especialidade));

  -- O ranking e o rodízio contam só quem pode atender agora; os ocupados vêm depois.
  select count(*) filter (where not c.novo and not c.ocupado) into v_ntop from _cand c;
  v_lanc := v_ntop < v_min_top;

  return query
  with ordenado as (
    select c.*,
      row_number() over (partition by c.ocupado, c.novo order by c.nota_media + c.bonus desc, c.total_avaliacoes desc, c.servicos_concluidos desc, c.distancia_km) - 1 as k_top,
      row_number() over (partition by c.ocupado, c.novo order by c.sorteio) - 1 as k_rodizio,
      row_number() over (partition by c.ocupado order by c.sorteio) as k_lanc
    from _cand c
  ),
  chave as (
    select o.*,
      (case when o.ocupado then 10000000 else 0 end) +
      case
        when p_ordem = 'distancia' then o.distancia_km * 1000
        when v_lanc then o.k_lanc
        -- dois bem avaliados, um novo, dois bem avaliados, um novo...
        when not o.novo then o.k_top + floor(o.k_top / 2.0)
        when o.k_rodizio < floor(v_ntop / 2.0) then o.k_rodizio * 3 + 2
        else 1000000 + o.k_rodizio
      end as ordem_final
    from ordenado o
  )
  select ch.profissional_id, ch.nome, ch.foto_url, ch.nota_media, ch.total_avaliacoes, ch.servicos_concluidos, ch.anos_experiencia,
    ch.verificado, ch.distancia_km, ch.novo, ch.preco_a_partir, ch.especialidades, ch.favorito, v_lanc,
    (row_number() over (order by ch.ordem_final, ch.distancia_km))::int, ch.ocupado
  from chave ch
  order by ch.ordem_final, ch.distancia_km
  limit p_limite;
end;
$$;
revoke all on function public.buscar_profissionais_base(text, double precision, double precision, bigint, text, integer, integer) from public, anon, authenticated;

create function public.buscar_profissionais(p_profissao text, p_lat double precision, p_lng double precision, p_especialidade bigint default null, p_ordem text default 'qualidade', p_rodizio integer default 0, p_limite integer default 50)
returns table (profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer, servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric, novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, fase_lancamento boolean, posicao integer, ocupado boolean)
language plpgsql security definer
set search_path = public, extensions
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_n integer;
begin
  return query select * from public.buscar_profissionais_base(p_profissao, p_lat, p_lng, p_especialidade, p_ordem, p_rodizio, p_limite);
  get diagnostics v_n = row_count;
  begin
    perform public.registrar_busca(p_profissao, p_especialidade, p_lat, p_lng, v_n);
  exception when others then
    null; -- o registro nunca pode quebrar a busca
  end;
end;
$$;
revoke all on function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) from public, anon;
grant execute on function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) to authenticated;

-- Urgência 24h é para agora: só quem pode atender agora.
create or replace function public.buscar_urgencia_24h(p_profissao text, p_lat double precision, p_lng double precision, p_especialidade bigint default null, p_ordem text default 'qualidade', p_rodizio integer default 0, p_limite integer default 50)
returns table (profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer, servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric, novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, fase_lancamento boolean, posicao integer)
language sql security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
  select b.profissional_id, b.nome, b.foto_url, b.nota_media, b.total_avaliacoes, b.servicos_concluidos,
    b.anos_experiencia, b.verificado, b.distancia_km, b.novo, b.preco_a_partir, b.especialidades, b.favorito,
    b.fase_lancamento, (row_number() over (order by b.posicao))::int
  from public.buscar_profissionais(p_profissao, p_lat, p_lng, p_especialidade, p_ordem, p_rodizio, 500) b
  join public.profissionais pr on pr.id = b.profissional_id
  where pr.atende_24h and not b.ocupado
  order by b.posicao
  limit p_limite
$$;

-- ---------------------------------------------------------------------------
-- Central de Ajuda
-- ---------------------------------------------------------------------------
update public.ajuda_perguntas set resposta =
  'Sim. Você pode agendar para até 7 dias à frente, mesmo se o profissional estiver ocupado agora. Aparecem só os horários em que ele atende e que estão livres. O profissional confirma o horário ou sugere outro, e os dois recebem um lembrete na véspera e 1 hora antes.',
  atualizada_em = now()
where pergunta = 'Posso agendar para outro dia?';

update public.ajuda_perguntas set resposta =
  'Abra o pedido em Pedidos e toque em "Cancelar pedido" (ou "Cancelar agendamento"). Dá para cancelar enquanto o profissional ainda não começou o serviço. Agendamentos podem ser cancelados sem custo até 2 horas antes. Depois disso, ou com o profissional a caminho, o valor do deslocamento fica com ele. Se o problema é só o horário, prefira "Remarcar".',
  atualizada_em = now()
where pergunta = 'Como cancelo um pedido?';

insert into public.ajuda_perguntas (publico, categoria, pergunta, resposta, ordem, palavras)
select v.publico, v.categoria, v.pergunta, v.resposta, v.ordem, v.palavras
from (values
  ('todos', 'Pedidos', 'Como remarco um agendamento?',
   'Abra o agendamento em Pedidos e toque em "Remarcar". Escolha o novo dia e horário: a outra pessoa recebe o pedido e confirma pelo app. Até ela confirmar, continua o horário de antes. Cada agendamento pode ser remarcado até 2 vezes.',
   35, 'mudar horario, trocar dia, adiar, outro dia, remarcar'),
  ('cliente', 'Pedidos', 'O profissional que eu quero está ocupado. Posso esperar por ele?',
   'Pode. Quem está atendendo agora aparece no fim da lista como "Ocupado agora". Toque nele e em "Agendar outro horário" para escolher um dia e horário livre na agenda dele.',
   36, 'ocupado, esperar, atendendo agora, indisponivel, agenda dele'),
  ('profissional', 'Atendimento', 'Como defino meus dias e horários de atendimento?',
   'Na aba Agenda, toque em "Meus horários" e marque os dias e o horário em que você atende. Os clientes só conseguem agendar dentro deles. Para folga, almoço ou compromisso, use "Bloquear horário" na Agenda.',
   37, 'horario de trabalho, expediente, folga, bloquear, almoço, dias que atendo'),
  ('profissional', 'Atendimento', 'Cheguei e o cliente não estava. O que faço?',
   'Tente falar com ele pelo chat. Se ninguém atender, 15 minutos depois do horário marcado (ou de sair a caminho) toque em "O cliente não está no local" no pedido. O atendimento é encerrado sem contar contra você e, com o pagamento pelo app, você recebe o valor do deslocamento.',
   38, 'cliente ausente, ninguem atendeu, nao estava, nao abriu, faltou')
) as v (publico, categoria, pergunta, resposta, ordem, palavras)
where not exists (select 1 from public.ajuda_perguntas a where a.pergunta = v.pergunta);
