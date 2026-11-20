-- Testes do suporte e incidentes (migração 20261120004300).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.admin() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.falha(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise exception 'FALHOU: %', nome;
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  -- Falta de permissão na tabela não conta: o erro tem de vir da regra do cargo.
  if sqlerrm like 'permission denied%' then raise exception 'FALHOU: % (erro inesperado: %)', nome, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.passa(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- d = dono, g = gerente, s = suporte, m = marketing, c = cliente, p = profissional
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000071d1', 'dono71@teste.com', now(), '{"nome":"Dono","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000071a1', 'gerente71@teste.com', now(), '{"nome":"Gerente","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000071e1', 'suporte71@teste.com', now(), '{"nome":"Suporte","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000071e2', 'suporte72@teste.com', now(), '{"nome":"Suporte Dois","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000071f1', 'mkt71@teste.com', now(), '{"nome":"Marketing","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000071c1', 'cliente71@teste.com', now(), '{"nome":"Marina Alves","app":"cliente"}');
update public.perfis set email_verificado = true where not email_verificado;
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set telefone = '61999990000' where id = '00000000-0000-0000-0000-0000000071c1';
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000071d1', '00000000-0000-0000-0000-0000000071a1',
  '00000000-0000-0000-0000-0000000071e1', '00000000-0000-0000-0000-0000000071e2', '00000000-0000-0000-0000-0000000071f1');
delete from public.equipe;
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono71@teste.com', 'Dono', 'dono', '00000000-0000-0000-0000-0000000071d1'),
  ('gerente71@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-0000000071a1'),
  ('suporte71@teste.com', 'Suporte', 'suporte', '00000000-0000-0000-0000-0000000071e1'),
  ('suporte72@teste.com', 'Suporte Dois', 'suporte', '00000000-0000-0000-0000-0000000071e2'),
  ('mkt71@teste.com', 'Marketing', 'marketing', '00000000-0000-0000-0000-0000000071f1');

-- ---------------------------------------------------------------- horário e prazos
update public.app_config set valor = '{"dias": [1, 2, 3, 4, 5, 6], "inicio": "08:00", "fim": "20:00"}' where chave = 'horario_atendimento';
-- 20/11/2026 é sexta-feira; 22/11 é domingo.
select pg_temp.ok(public.em_horario_atendimento('2026-11-20 10:00-03'), 'sexta 10h está no horário');
select pg_temp.ok(not public.em_horario_atendimento('2026-11-20 20:00-03'), 'sexta 20h já fechou');
select pg_temp.ok(not public.em_horario_atendimento('2026-11-22 10:00-03'), 'domingo está fora do horário');
select pg_temp.ok(public.prazo_resposta(1, '2026-11-22 03:00-03') = '2026-11-22 03:15-03', 'crítica: 15 minutos, mesmo de madrugada no domingo');
select pg_temp.ok(public.prazo_resposta(2, '2026-11-20 10:00-03') = '2026-11-20 11:00-03', 'alta: 1 hora dentro do horário');
select pg_temp.ok(public.prazo_resposta(2, '2026-11-21 19:30-03') = '2026-11-23 08:30-03', 'alta no sábado à noite: conta 30 min e o resto na segunda');
select pg_temp.ok(public.prazo_resposta(3, '2026-11-22 15:00-03') = '2026-11-23 12:00-03', 'média no domingo: 4 horas a partir da abertura de segunda');
select pg_temp.ok(public.prazo_resposta(4, '2026-11-20 09:00-03') = '2026-11-21 09:00-03', 'baixa: 1 dia de atendimento');
select pg_temp.ok(public.gravidade_sugerida('Fui ameaçado pelo profissional') = 1, 'ameaça é crítica');
select pg_temp.ok(public.gravidade_sugerida('O profissional não apareceu') = 2, 'não apareceu é alta');
select pg_temp.ok(public.gravidade_sugerida('Meu cadastro foi recusado') = 3, 'cadastro é média');
select pg_temp.ok(public.gravidade_sugerida('Qual o horário de vocês?') = 4, 'dúvida é baixa');
select pg_temp.ok(public.gravidade_sugerida('Quero montar um armário') = 4, 'armário não é arma');

-- ---------------------------------------------------------------- e-mail: gravidade e primeira resposta
insert into public.suporte_conversas (assunto, contato_email, status, responsavel) values ('Dúvida', 'x71@x.com', 'aberto', 'suporte71@teste.com');
insert into public.suporte_mensagens (conversa_id, direcao, de_email, assunto, texto)
select id, 'recebida', 'x71@x.com', 'Dúvida', 'O profissional não apareceu e cobrou a visita' from public.suporte_conversas where contato_email = 'x71@x.com';
select pg_temp.ok((select gravidade from public.suporte_conversas where contato_email = 'x71@x.com') = 2, 'e-mail ganha a gravidade pelo texto');
insert into public.suporte_mensagens (conversa_id, direcao, texto)
select id, 'enviada', 'Oi! Vamos ver.' from public.suporte_conversas where contato_email = 'x71@x.com';
select pg_temp.ok((select primeira_resposta_em from public.suporte_conversas where contato_email = 'x71@x.com') is not null, 'primeira resposta enviada fica registrada');
insert into public.suporte_mensagens (conversa_id, direcao, de_email, texto)
select id, 'recebida', 'x71@x.com', 'Ele me ameaçou' from public.suporte_conversas where contato_email = 'x71@x.com';
select pg_temp.ok((select gravidade from public.suporte_conversas where contato_email = 'x71@x.com') = 2, 'depois de respondido, a gravidade só muda pela equipe');

select id as conv from public.suporte_conversas where contato_email = 'x71@x.com' \gset
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.ok((select count(*) from public.admin_prazos('email', array[:conv::bigint])) = 1, 'suporte vê o prazo dos e-mails');
select pg_temp.passa('select public.admin_definir_gravidade(''email'', ' || :conv || ', 1)', 'suporte muda a gravidade do e-mail');
select pg_temp.falha('select public.admin_definir_gravidade(''email'', ' || :conv || ', 5)', 'gravidade fora de 1 a 4 é recusada');
select pg_temp.falha($$select public.admin_prazos('denuncia', array[1::bigint])$$, 'suporte não vê prazos das denúncias');
select pg_temp.como('00000000-0000-0000-0000-0000000071f1');
select pg_temp.falha($$select public.admin_prazos('email', array[1::bigint])$$, 'marketing não vê prazos dos e-mails');
select pg_temp.admin();

-- ---------------------------------------------------------------- emergência avisa a equipe
select pg_temp.como('00000000-0000-0000-0000-0000000071c1');
select public.acionar_emergencia(null, -15.79, -47.88);
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.notificacoes where tipo = 'emergencia_equipe') = 4,
  'sem plantão, todos com acesso às emergências recebem (dono, gerente e 2 do suporte)');
select pg_temp.ok(not exists (select 1 from public.notificacoes where tipo = 'emergencia_equipe' and usuario_id = '00000000-0000-0000-0000-0000000071f1'),
  'marketing não recebe alerta de emergência');
select pg_temp.ok((select corpo from public.notificacoes where tipo = 'emergencia_equipe' limit 1) like '%Marina Alves%61999990000%', 'alerta traz o nome e o telefone');
select pg_temp.ok(public.tipo_tem_email('emergencia_equipe'), 'alerta de emergência também vai por e-mail');

select pg_temp.como('00000000-0000-0000-0000-0000000071a1');
select pg_temp.passa($$select public.admin_definir_plantao('suporte71@teste.com', true)$$, 'gerente põe alguém de plantão');
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.falha($$select public.admin_definir_plantao('suporte72@teste.com', true)$$, 'suporte não mexe no plantão');
select pg_temp.admin();
select pg_temp.falha($$select public.admin_definir_plantao('mkt71@teste.com', true)$$, 'marketing não pode ficar de plantão (sem acesso às emergências)');
delete from public.notificacoes where tipo = 'emergencia_equipe';
select pg_temp.como('00000000-0000-0000-0000-0000000071c1');
select public.acionar_emergencia(null, null, null);
select pg_temp.admin();
select pg_temp.ok((select array_agg(usuario_id order by usuario_id) from public.notificacoes where tipo = 'emergencia_equipe')
  = array['00000000-0000-0000-0000-0000000071d1', '00000000-0000-0000-0000-0000000071e1']::uuid[], 'com plantão, só o dono e o plantonista recebem');

select min(id) as emerg1, max(id) as emerg2 from public.emergencias \gset
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.ok((select count(*) from public.admin_emergencias(true)) = 2 and (select bool_and(contato_em is null) from public.admin_emergencias(true)), 'emergências abertas sem contato');
select pg_temp.passa('select public.admin_contato_emergencia(' || :emerg2 || ')', 'suporte registra que ligou');
select pg_temp.ok((select contato_por from public.admin_emergencias(true) where id = :emerg2) = 'Suporte', 'painel mostra quem ligou');
select pg_temp.ok((select not atrasada from public.admin_prazos('emergencia', array[:emerg2::bigint])), 'contato em 15 minutos fica no prazo');
select pg_temp.passa('select public.admin_atender_emergencia(' || :emerg1 || ', ''Foi engano'')', 'marcar como atendida');
select pg_temp.admin();
select pg_temp.ok((select contato_em is not null from public.emergencias where id = :emerg1), 'atendida também conta como contato');

-- ---------------------------------------------------------------- denúncia
insert into public.denuncias (autor_id, alvo_id, motivo, descricao) values
  ('00000000-0000-0000-0000-0000000071c1', '00000000-0000-0000-0000-0000000071e2', 'Comportamento inadequado ou assédio', ''),
  ('00000000-0000-0000-0000-0000000071c1', '00000000-0000-0000-0000-0000000071e2', 'Perfil falso ou dados errados', '');
select pg_temp.ok((select gravidade from public.denuncias where motivo like 'Comportamento%') = 1, 'assédio é crítico');
select pg_temp.ok((select gravidade from public.denuncias where motivo like 'Perfil%') = 3, 'perfil falso é média');
update public.denuncias set status = 'em_analise' where motivo like 'Perfil%';
select pg_temp.ok((select primeira_resposta_em from public.denuncias where motivo like 'Perfil%') is not null, 'sair de aberta conta como resposta');

-- ---------------------------------------------------------------- horário pelo painel
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.falha($$select public.admin_salvar_horario(array[1,2,3,4,5], '08:00', '18:00')$$, 'suporte não muda o horário');
select pg_temp.ok((select (public.admin_atendimento() ->> 'pode_editar')::boolean) is false, 'suporte vê o horário sem poder editar');
select pg_temp.como('00000000-0000-0000-0000-0000000071d1');
select pg_temp.falha($$select public.admin_salvar_horario(array[1,2], '18:00', '08:00')$$, 'fim antes do início é recusado');
select pg_temp.falha($$select public.admin_salvar_horario(array[]::int[], '08:00', '18:00')$$, 'sem dias é recusado');
select pg_temp.passa($$select public.admin_salvar_horario(array[5,1,2,3,4,1], '08:00', '18:00')$$, 'dono muda o horário');
select pg_temp.ok(public.horario_atendimento() = '{"dias": [1, 2, 3, 4, 5], "inicio": "08:00", "fim": "18:00"}'::jsonb, 'horário guardado em ordem e sem repetição');
select pg_temp.ok(jsonb_array_length(public.admin_atendimento() -> 'plantao') = 4, 'lista de plantão traz só quem atende emergências');
select pg_temp.admin();

-- ---------------------------------------------------------------- resposta automática
insert into public.suporte_conversas (assunto, contato_email, mensagens) values ('Fora', 'fora71@x.com', 1), ('Robô', 'no-reply@loja.com', 1);
update public.app_config set valor = '{"dias": [1], "inicio": "08:00", "fim": "08:01"}' where chave = 'horario_atendimento';
select pg_temp.ok((public.suporte_resposta_automatica((select id from public.suporte_conversas where contato_email = 'fora71@x.com')) ->> 'enviar')::boolean,
  'fora do horário, conversa nova recebe resposta automática');
select pg_temp.ok(not (public.suporte_resposta_automatica((select id from public.suporte_conversas where contato_email = 'fora71@x.com')) ->> 'enviar')::boolean,
  'só uma resposta automática por conversa');
select pg_temp.ok(not (public.suporte_resposta_automatica((select id from public.suporte_conversas where contato_email = 'no-reply@loja.com')) ->> 'enviar')::boolean,
  'nunca responde a endereços automáticos');
select pg_temp.como('00000000-0000-0000-0000-0000000071d1');
do $$ begin
  perform public.suporte_resposta_automatica(1);
  raise exception 'FALHOU: só a função do servidor chama a resposta automática';
exception when insufficient_privilege then raise notice 'ok - só a função do servidor chama a resposta automática';
end $$;
select pg_temp.admin();

-- ---------------------------------------------------------------- Central de Ajuda
select pg_temp.ok((select count(*) from public.ajuda_perguntas) >= 15, 'perguntas iniciais carregadas');
set local role anon;
select pg_temp.ok((select count(*) from public.ajuda_perguntas where publico in ('cliente', 'todos')) >= 9, 'site e app leem a ajuda sem login');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.falha($$select public.admin_salvar_pergunta(null, 'todos', 'Geral', 'Pergunta nova?', 'Resposta nova.')$$, 'suporte não edita a ajuda');
select pg_temp.como('00000000-0000-0000-0000-0000000071f1');
select pg_temp.passa($$select public.admin_salvar_pergunta(null, 'todos', 'Geral', 'Pergunta nova?', 'Resposta nova.', 5, false)$$, 'marketing cria pergunta');
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000071c1');
select pg_temp.ok(not exists (select 1 from public.ajuda_perguntas where pergunta = 'Pergunta nova?'), 'pergunta desativada não aparece no app');
select pg_temp.admin();

-- ---------------------------------------------------------------- indicadores
select pg_temp.como('00000000-0000-0000-0000-0000000071a1');
select pg_temp.ok((public.admin_indicadores_suporte(30) ->> 'total')::int >= 5, 'indicadores somam todos os canais');
select pg_temp.ok(jsonb_array_length(public.admin_indicadores_suporte(30) -> 'canais') = 3, 'indicadores separam por canal');
select pg_temp.como('00000000-0000-0000-0000-0000000071e1');
select pg_temp.falha($$select public.admin_indicadores_suporte(30)$$, 'suporte não vê os indicadores');
select pg_temp.admin();

rollback;
