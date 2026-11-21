-- Testes da agenda completa do profissional (migração 20261121020000):
-- horário de trabalho, bloqueios, horários livres, remarcar, cancelamento em cima da hora,
-- cliente ausente e o profissional ocupado na busca. Transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

-- Espera um erro com o código dado (ex.: 'fora_do_expediente').
create function pg_temp.erro(sql text, codigo text, nome text) returns void language plpgsql as $$
declare
  v_det text;
begin
  execute sql;
  raise exception 'FALHOU: % (não deu erro)', nome;
exception when others then
  get stacked diagnostics v_det = pg_exception_detail;
  if sqlerrm like 'FALHOU%' then raise; end if;
  if v_det is distinct from codigo then raise exception 'FALHOU: % (erro inesperado: % / %)', nome, v_det, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

-- Dias de teste entre amanhã e daqui a 6 dias: um dia útil e um fim de semana.
create function pg_temp.dia(util boolean) returns date language sql as $$
  select d::date from generate_series((now() at time zone 'America/Sao_Paulo')::date + 1, (now() at time zone 'America/Sao_Paulo')::date + 6, interval '1 day') d
  where (extract(isodow from d) <= 5) = util order by d limit 1
$$;
create function pg_temp.em(util boolean, hora text) returns timestamptz language sql as $$
  select (pg_temp.dia(util) + hora::time) at time zone 'America/Sao_Paulo'
$$;
grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'agpro@teste.com', '{"nome":"Ana Agenda","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'agcli@teste.com', '{"nome":"Caio Cliente","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e3', 'agpro2@teste.com', '{"nome":"Beto Livre","app":"profissional"}');
update public.perfis set email_verificado = true where id::text like '00000000-0000-0000-0000-0000000000e%';

create temp table t (nome text primary key, pedido uuid);
grant all on t to authenticated;
create function pg_temp.ped(n text) returns uuid language sql as $$ select pedido from t where nome = n $$;
-- Pedido agendado direto na tabela (passa pela trava da agenda, como o criar_pedido).
create function pg_temp.agendar(n text, pro uuid, para timestamptz, st public.status_pedido default 'solicitado') returns void language sql as $$
  with x as (
    insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, combinado_para, endereco_texto, localizacao, responder_ate, distancia_km, status)
    values ('00000000-0000-0000-0000-0000000000e2', pro, 'eletricista', 'combinado', para, 'SQS 308', public.ponto(-15.81, -47.89),
            least(para, now() + interval '2 hours'), 10, st)
    returning id)
  insert into t select n, id from x
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- ------------------------------------------------------------ horário de trabalho
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select public.salvar_horario_trabalho('[{"dia":1,"inicio":"08:00","fim":"18:00"},{"dia":2,"inicio":"08:00","fim":"18:00"},
  {"dia":3,"inicio":"08:00","fim":"18:00"},{"dia":4,"inicio":"08:00","fim":"18:00"},{"dia":5,"inicio":"08:00","fim":"18:00"}]');
select pg_temp.ok((select count(*) = 5 from public.horarios_trabalho), 'profissional salva o horário de segunda a sexta, 8h às 18h');
select pg_temp.erro($$select public.salvar_horario_trabalho('[{"dia":1,"inicio":"18:00","fim":"08:00"}]')$$, 'horario_invalido', 'fim antes do início é recusado');
select pg_temp.ok((select count(*) = 5 from public.horarios_trabalho), 'horário inválido não apaga o que estava salvo');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select count(*) = 0 from public.horarios_trabalho), 'cliente não lê a tabela de horários de ninguém');
select pg_temp.erro($$select public.salvar_horario_trabalho('[]')$$, 'sem_permissao', 'cliente não tem agenda para salvar');
reset role;

select pg_temp.erro($$select pg_temp.agendar('sabado', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(false, '10:00'))$$,
  'fora_do_expediente', 'cliente não agenda no fim de semana (fora do expediente)');
select pg_temp.erro($$select pg_temp.agendar('cedo', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '07:00'))$$,
  'fora_do_expediente', 'nem antes das 8h');
select pg_temp.erro($$select pg_temp.agendar('tarde', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '18:00'))$$,
  'fora_do_expediente', 'nem a partir das 18h');
select pg_temp.agendar('dez', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '10:00'), 'aceito');
select pg_temp.ok(pg_temp.ped('dez') is not null, 'dentro do expediente agenda normalmente');
select pg_temp.agendar('livre', '00000000-0000-0000-0000-0000000000e3', pg_temp.em(false, '06:30'));
select pg_temp.ok(pg_temp.ped('livre') is not null, 'profissional sem horário salvo aceita qualquer horário (como antes)');

-- ------------------------------------------------------------ outro atendimento e bloqueios
select pg_temp.erro($$select pg_temp.agendar('encavalado', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '10:30'))$$,
  'horario_ocupado', 'não marca a menos de 1 hora de outro atendimento confirmado');
select pg_temp.agendar('onze', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '11:00'));
select pg_temp.ok(pg_temp.ped('onze') is not null, '1 hora depois já pode');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok((public.bloquear_horario(pg_temp.em(true, '09:30'), pg_temp.em(true, '10:15'), 'Banco') ->> 'conflitos')::int = 1,
  'bloquear em cima de um atendimento avisa quantos ficam no período');
select pg_temp.ok((public.bloquear_horario(pg_temp.em(true, '13:00'), pg_temp.em(true, '14:00'), 'Almoço') ->> 'conflitos')::int = 0, 'bloqueia o almoço');
select pg_temp.erro($$select public.bloquear_horario(now() - interval '2 hours', now() - interval '1 hour', '')$$, 'bloqueio_invalido', 'não bloqueia o passado');
select pg_temp.erro($$select public.bloquear_horario(now() + interval '1 day', now() + interval '40 days', '')$$, 'bloqueio_invalido', 'no máximo 31 dias por bloqueio');
select pg_temp.ok((select count(*) = 2 from public.agenda_bloqueios), 'profissional vê os próprios bloqueios');
select pg_temp.ok((select (a -> 'bloqueios' -> 1 ->> 'motivo') = 'Almoço' from public.agenda_profissional(auth.uid()) a), 'na própria agenda vem o motivo');
reset role;
select pg_temp.erro($$select pg_temp.agendar('almoco', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '13:30'))$$,
  'horario_bloqueado', 'cliente não agenda no horário bloqueado');
select pg_temp.erro($$select pg_temp.agendar('antes_almoco', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '12:30'))$$,
  'horario_bloqueado', 'nem a menos de 1 hora antes do bloqueio');
select pg_temp.agendar('depois_almoco', '00000000-0000-0000-0000-0000000000e1', pg_temp.em(true, '14:00'));
select pg_temp.ok(pg_temp.ped('depois_almoco') is not null, 'no fim do bloqueio já pode');

select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select jsonb_array_length(a -> 'horario') = 5 and jsonb_array_length(a -> 'bloqueios') = 2
    and not (a -> 'bloqueios' -> 0 ? 'motivo') and jsonb_array_length(a -> 'ocupados') = 1
  from public.agenda_profissional('00000000-0000-0000-0000-0000000000e1') a),
  'cliente vê o expediente, os bloqueios (sem o motivo) e os horários já marcados');
select pg_temp.ok((select count(*) = 0 from public.agenda_bloqueios), 'cliente não lê a tabela de bloqueios');
reset role;

-- O profissional sugere horário: pode sair do expediente, mas não encavalar.
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.erro(format($$select public.propor_horario(%L, %L)$$, pg_temp.ped('onze'), pg_temp.em(true, '10:20')),
  'horario_ocupado', 'profissional não sugere horário em cima de outro atendimento');
select pg_temp.ok((select proposta_para is not null from public.propor_horario(pg_temp.ped('onze'), pg_temp.em(true, '19:00'))),
  'profissional pode sugerir fora do próprio expediente');
reset role;

-- O bloqueio some com desbloquear.
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select public.desbloquear_horario((select id from public.agenda_bloqueios where motivo = 'Almoço'));
select pg_temp.ok((select count(*) = 1 from public.agenda_bloqueios), 'desbloquear apaga o bloqueio');
reset role;

-- ------------------------------------------------------------ remarcar
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.erro(format($$select public.remarcar_pedido(%L, %L)$$, pg_temp.ped('dez'), pg_temp.em(false, '10:00')),
  'fora_do_expediente', 'cliente não remarca para fora do expediente');
select pg_temp.ok((select remarcar_para = pg_temp.em(true, '16:00') and remarcar_por = auth.uid() and remarcar_ate > now()
  from public.remarcar_pedido(pg_temp.ped('dez'), pg_temp.em(true, '16:00'))), 'cliente pede para remarcar para as 16h');
select pg_temp.erro(format($$select public.remarcar_pedido(%L, %L)$$, pg_temp.ped('dez'), pg_temp.em(true, '17:00')),
  'remarcacao_pendente', 'só uma remarcação pendente por vez');
select pg_temp.erro(format($$select public.responder_remarcacao(%L, true)$$, pg_temp.ped('dez')), 'sem_remarcacao', 'quem pediu não confirma a própria remarcação');
reset role;
select pg_temp.ok((select count(*) = 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000e1' and tipo = 'pedido_remarcar'),
  'profissional é avisado do pedido de remarcação');
update public.pedidos set lembrete_vespera_em = now() where id = pg_temp.ped('dez');
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok((select combinado_para = pg_temp.em(true, '16:00') and remarcar_para is null and remarcacoes = 1 and lembrete_vespera_em is null
  from public.responder_remarcacao(pg_temp.ped('dez'), true)), 'profissional confirma: novo horário, conta a remarcação e refaz os lembretes');
reset role;
select pg_temp.ok((select count(*) = 2 from public.notificacoes where tipo = 'agendamento_confirmado' and (dados ->> 'pedido_id')::uuid = pg_temp.ped('dez')),
  'os dois recebem a confirmação do novo horário');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok((select remarcar_para = pg_temp.em(true, '19:00') from public.remarcar_pedido(pg_temp.ped('dez'), pg_temp.em(true, '19:00'))),
  'profissional pode propor remarcar fora do próprio expediente');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select combinado_para = pg_temp.em(true, '16:00') and remarcar_para is null from public.responder_remarcacao(pg_temp.ped('dez'), false)),
  'cliente mantém o horário original');
select pg_temp.ok((select remarcar_para is not null from public.remarcar_pedido(pg_temp.ped('dez'), pg_temp.em(true, '15:00'))), 'remarca de novo');
select public.desistir_remarcacao(pg_temp.ped('dez'));
select pg_temp.ok((select remarcar_para is null from public.pedidos where id = pg_temp.ped('dez')), 'quem pediu pode desistir da remarcação');
reset role;

update public.pedidos set remarcar_para = pg_temp.em(true, '15:00'), remarcar_por = '00000000-0000-0000-0000-0000000000e2', remarcar_ate = now() - interval '1 minute'
where id = pg_temp.ped('dez');
select pg_temp.ok(public.expirar_remarcacoes() = 1, 'remarcação sem resposta expira');
select pg_temp.ok((select remarcar_para is null and combinado_para = pg_temp.em(true, '16:00') from public.pedidos where id = pg_temp.ped('dez')),
  'sem resposta no prazo, fica o horário original');
update public.pedidos set remarcacoes = 2 where id = pg_temp.ped('dez');
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.erro(format($$select public.remarcar_pedido(%L, %L)$$, pg_temp.ped('dez'), pg_temp.em(true, '15:00')), 'limite_remarcacoes', 'no máximo 2 remarcações');
reset role;

-- ------------------------------------------------------------ cancelamento em cima da hora
select pg_temp.agendar('em_cima', '00000000-0000-0000-0000-0000000000e3', now() + interval '1 hour', 'aceito');
select pg_temp.agendar('com_folga', '00000000-0000-0000-0000-0000000000e3', now() + interval '1 day', 'aceito');
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select (a ->> 'em_cima')::boolean and (a ->> 'taxa')::numeric = 0 and (a ->> 'pode_remarcar')::boolean
  from public.previa_cancelamento(pg_temp.ped('em_cima')) a), 'a 1 hora do horário é em cima da hora (sem cobrança com o pagamento desligado)');
select pg_temp.ok((select not (a ->> 'em_cima')::boolean from public.previa_cancelamento(pg_temp.ped('com_folga')) a), 'com 1 dia de folga, não');
select pg_temp.ok((select cancelado_em_cima and taxa_cancelamento = 0 from public.cancelar_pedido(pg_temp.ped('em_cima'), 'Imprevisto')),
  'cancelamento em cima da hora fica registrado');
reset role;

update public.app_config set valor = 'true' where chave = 'pagamento_ativo';
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select not cancelado_em_cima and taxa_cancelamento = 0 from public.cancelar_pedido(pg_temp.ped('com_folga'), 'Imprevisto')),
  'com folga, cancela sem custo mesmo com o pagamento ligado');
reset role;
select pg_temp.agendar('em_cima2', '00000000-0000-0000-0000-0000000000e3', now() + interval '90 minutes', 'aceito');
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select (a ->> 'taxa')::numeric = 35 from public.previa_cancelamento(pg_temp.ped('em_cima2')) a),
  'com o pagamento ligado, a prévia mostra o deslocamento (R$ 35 para 10 km)');
select pg_temp.ok((select taxa_cancelamento = 35 from public.cancelar_pedido(pg_temp.ped('em_cima2'), null)), 'e o cancelamento guarda o valor para o profissional');
reset role;
select pg_temp.ok((select corpo like '%você recebe R$ 35,00 pelo deslocamento%' from public.notificacoes
  where usuario_id = '00000000-0000-0000-0000-0000000000e3' and tipo = 'pedido_cancelado' order by criada_em desc, id desc limit 1),
  'profissional é avisado de que recebe o deslocamento');
update public.app_config set valor = 'false' where chave = 'pagamento_ativo';

-- ------------------------------------------------------------ cliente ausente
select pg_temp.agendar('ausente', '00000000-0000-0000-0000-0000000000e3', now() + interval '3 days', 'aceito');
update public.pedidos set quando = 'agora', combinado_para = null, status = 'a_caminho', a_caminho_em = now() - interval '5 minutes' where id = pg_temp.ped('ausente');
select pg_temp.como('00000000-0000-0000-0000-0000000000e3');
select pg_temp.erro(format($$select public.marcar_cliente_ausente(%L)$$, pg_temp.ped('ausente')), 'cedo_demais', 'cedo demais para marcar cliente ausente');
reset role;
update public.pedidos set a_caminho_em = now() - interval '20 minutes' where id = pg_temp.ped('ausente');
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.erro(format($$select public.marcar_cliente_ausente(%L)$$, pg_temp.ped('ausente')), 'pedido_nao_encontrado', 'cliente não marca a si mesmo como ausente');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e3');
select pg_temp.ok((select status = 'cancelado' and cliente_ausente and cancelado_em_cima from public.marcar_cliente_ausente(pg_temp.ped('ausente'))),
  'depois da tolerância, o profissional encerra como cliente ausente');
reset role;
select pg_temp.ok((select cancelados_pelo_profissional = 0 from public.profissionais where id = '00000000-0000-0000-0000-0000000000e3'),
  'cliente ausente não conta contra o profissional');

-- ------------------------------------------------------------ ocupado na busca
select pg_temp.ok(not public.em_atendimento('00000000-0000-0000-0000-0000000000e3'), 'sem atendimento em curso, não está ocupado');

rollback;
