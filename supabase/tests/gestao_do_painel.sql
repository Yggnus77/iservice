-- Testes das ferramentas de gestão do painel (migração 20261118003400).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
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
  if sqlerrm like 'permission denied%' then raise exception 'FALHOU: % (erro inesperado: %)', nome, sqlerrm; end if;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- d = dono, b = responsável, e = suporte, f = marketing, p = profissional, q = profissional preenchendo, c = cliente
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000090d1', 'gdono@teste.com', now(), '{"nome":"Dono Gestão","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000090b1', 'gresp@teste.com', now(), '{"nome":"Resp Gestão","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000090e1', 'gsup@teste.com', now(), '{"nome":"Suporte Gestão","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000090f1', 'gmkt@teste.com', now(), '{"nome":"Mkt Gestão","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000090a1', 'gpro@teste.com', now(), '{"nome":"Paulo Problema","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000090a2', 'grasc@teste.com', now(), '{"nome":"Rita Rascunho","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000090c1', 'gcli@teste.com', now(), '{"nome":"Carla Cliente","app":"cliente"}');
update public.perfis p set email = u.email from auth.users u where u.id = p.id and u.email like 'g%@teste.com';
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000090d1', '00000000-0000-0000-0000-0000000090b1',
  '00000000-0000-0000-0000-0000000090e1', '00000000-0000-0000-0000-0000000090f1');
insert into public.equipe (email, nome, papel, usuario_id) values
  ('gdono@teste.com', 'Dono Gestão', 'dono', '00000000-0000-0000-0000-0000000090d1'),
  ('gresp@teste.com', 'Resp Gestão', 'responsavel', '00000000-0000-0000-0000-0000000090b1'),
  ('gsup@teste.com', 'Suporte Gestão', 'suporte', '00000000-0000-0000-0000-0000000090e1'),
  ('gmkt@teste.com', 'Mkt Gestão', 'marketing', '00000000-0000-0000-0000-0000000090f1')
on conflict (email) do update set papel = excluded.papel, usuario_id = excluded.usuario_id;
update public.profissionais set status = 'aprovado', aprovado_em = now() - interval '60 days', regiao_id = 'asa-sul'
where id = '00000000-0000-0000-0000-0000000090a1';
insert into public.profissional_profissoes values ('00000000-0000-0000-0000-0000000090a1', 'eletricista', true);

-- ---------------------------------------------------------------- permissão de relatórios
select pg_temp.ok('relatorios' = any (public.cargo_permissoes('dono')) and 'relatorios' = any (public.cargo_permissoes('marketing'))
  and not 'relatorios' = any (public.cargo_permissoes('suporte')), 'relatórios: dono e marketing sim, suporte não');
select pg_temp.ok(cardinality(public.cargo_permissoes('suporte')) = 7, 'suporte continua com as mesmas 7 permissões');

-- ---------------------------------------------------------------- anotações internas
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select public.admin_anotar('pessoa', '00000000-0000-0000-0000-0000000090c1', '  Ligou reclamando dia 10, prometemos retorno  ');
select pg_temp.ok((select jsonb_array_length(public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1'))) = 1, 'suporte anota na conta da pessoa');
select pg_temp.ok((public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1') -> 0 ->> 'texto') = 'Ligou reclamando dia 10, prometemos retorno',
  'a anotação é salva sem espaços sobrando');
select pg_temp.falha($$select public.admin_anotar('pessoa', '00000000-0000-0000-0000-0000000090c1', '   ')$$, 'anotação vazia não é salva');
select pg_temp.falha($$select public.admin_anotar('pedido', gen_random_uuid(), 'x')$$, 'anotação em pedido que não existe é recusada');
select pg_temp.falha($$select public.admin_anotar('outro', gen_random_uuid(), 'x')$$, 'tipo de anotação inválido é recusado');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.notas_internas', 'select'), 'a tabela de anotações não é lida direto');
reset role;
select set_config('t.nota', (select id::text from public.notas_internas order by id desc limit 1), true);
select pg_temp.como('00000000-0000-0000-0000-0000000090f1');
select pg_temp.falha($$select public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1')$$, 'marketing não lê anotações de pessoas');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select pg_temp.ok(not (public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1') -> 0 ->> 'pode_apagar')::boolean,
  'responsável não apaga a anotação de outra pessoa');
select pg_temp.falha($$select public.admin_apagar_nota(current_setting('t.nota')::bigint)$$, 'apagar anotação de outra pessoa é recusado');
select pg_temp.como('00000000-0000-0000-0000-0000000090d1');
select public.admin_fixar_nota(current_setting('t.nota')::bigint, true);
select pg_temp.ok((public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1') -> 0 ->> 'fixada')::boolean, 'anotação pode ser fixada no topo');
select public.admin_apagar_nota(current_setting('t.nota')::bigint);
select pg_temp.ok((select jsonb_array_length(public.admin_notas('pessoa', '00000000-0000-0000-0000-0000000090c1'))) = 0, 'o dono apaga qualquer anotação');

-- ---------------------------------------------------------------- advertência e suspensão com prazo
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.falha($$select public.admin_advertir('00000000-0000-0000-0000-0000000090a1', 'Atrasou o serviço')$$, 'suporte não adverte');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select pg_temp.ok(public.admin_advertir('00000000-0000-0000-0000-0000000090a1', 'Chegou 2 horas atrasado sem avisar') = 1, 'responsável adverte o profissional');
select pg_temp.falha($$select public.admin_advertir('00000000-0000-0000-0000-0000000090a1', 'x')$$, 'advertência precisa de motivo');
select pg_temp.falha($$select public.admin_advertir(auth.uid(), 'Teste de motivo')$$, 'ninguém adverte a si mesmo');
reset role;
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000090a1' and tipo = 'advertencia'),
  'o profissional recebe o aviso da advertência no app');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select pg_temp.ok(jsonb_array_length(public.admin_gestao_pessoa('00000000-0000-0000-0000-0000000090a1') -> 'advertencias') = 1, 'a ficha mostra as advertências');

select public.admin_suspender_por('00000000-0000-0000-0000-0000000090a1', 7, 'Faltou a dois serviços marcados');
reset role;
select pg_temp.ok((select suspenso_ate between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour' from public.perfis
  where id = '00000000-0000-0000-0000-0000000090a1'), 'suspensão por 7 dias guarda a data de volta');
select pg_temp.ok((select banned_until = p.suspenso_ate from auth.users u join public.perfis p on p.id = u.id
  where u.id = '00000000-0000-0000-0000-0000000090a1'), 'o bloqueio do login termina junto com o prazo');
select pg_temp.ok((select motivo_suspensao like 'Faltou a dois serviços marcados (por 7 dias, até %)' from public.perfis
  where id = '00000000-0000-0000-0000-0000000090a1'), 'o motivo mostra o prazo');
select pg_temp.ok((select status = 'suspenso' from public.profissionais where id = '00000000-0000-0000-0000-0000000090a1'), 'profissional fica suspenso');
select pg_temp.ok(public.reativar_suspensoes_vencidas() = 0, 'antes do prazo ninguém volta');
update public.perfis set suspenso_ate = now() - interval '1 minute' where id = '00000000-0000-0000-0000-0000000090a1';
select pg_temp.ok(public.reativar_suspensoes_vencidas() = 1, 'no fim do prazo a conta volta sozinha');
select pg_temp.ok((select suspenso_em is null and suspenso_ate is null from public.perfis where id = '00000000-0000-0000-0000-0000000090a1')
  and (select status = 'aprovado' from public.profissionais where id = '00000000-0000-0000-0000-0000000090a1')
  and (select banned_until is null from auth.users where id = '00000000-0000-0000-0000-0000000090a1'), 'volta aprovado e com login liberado');
select pg_temp.ok(exists (select 1 from public.admin_acoes where acao = 'reativar' and alvo = '00000000-0000-0000-0000-0000000090a1'
  and dados ->> 'motivo' = 'Fim do prazo da suspensão'), 'a volta automática fica no registro');

select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select public.admin_suspender_por('00000000-0000-0000-0000-0000000090c1', 3, 'Teste de prazo');
select public.admin_suspender_por('00000000-0000-0000-0000-0000000090c1', null, 'Fraude confirmada');
reset role;
select pg_temp.ok((select suspenso_ate is null and motivo_suspensao = 'Fraude confirmada' from public.perfis where id = '00000000-0000-0000-0000-0000000090c1')
  and (select banned_until = 'infinity' from auth.users where id = '00000000-0000-0000-0000-0000000090c1'), 'trocar para sem prazo vale na hora');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select public.admin_suspender('00000000-0000-0000-0000-0000000090c1', false);
select pg_temp.falha($$select public.admin_suspender_por('00000000-0000-0000-0000-0000000090c1', 0, 'x')$$, 'prazo zero é recusado');
select pg_temp.falha($$select public.admin_suspender_por('00000000-0000-0000-0000-0000000090c1', 400, 'x')$$, 'prazo acima de 1 ano é recusado');

-- ---------------------------------------------------------------- validade de documentos
reset role;
insert into public.documentos (profissional_id, tipo, arquivo_path, status) values
  ('00000000-0000-0000-0000-0000000090a1', 'antecedentes', '00000000-0000-0000-0000-0000000090a1/ant.pdf', 'pendente');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select public.admin_revisar_documento((select id from public.documentos where profissional_id = '00000000-0000-0000-0000-0000000090a1' and tipo = 'antecedentes'), true);
reset role;
select pg_temp.ok((select valido_ate = (now() at time zone 'America/Sao_Paulo')::date + 182 from public.documentos
  where profissional_id = '00000000-0000-0000-0000-0000000090a1' and tipo = 'antecedentes'), 'certidão aprovada vale 6 meses');
select set_config('t.doc', (select id::text from public.documentos where profissional_id = '00000000-0000-0000-0000-0000000090a1' and tipo = 'antecedentes'), true);
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.falha($$select public.admin_definir_validade('documento', current_setting('t.doc')::bigint, current_date + 10)$$, 'suporte não muda a validade');
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select public.admin_definir_validade('documento', current_setting('t.doc')::bigint, ((now() at time zone 'America/Sao_Paulo')::date + 10));
select pg_temp.ok(jsonb_array_length(public.admin_validades(30)) = 1, 'documento que vence em 10 dias aparece na lista');
select pg_temp.ok((public.admin_validades(30) -> 0 ->> 'dias')::int = 10 and not (public.admin_validades(30) -> 0 ->> 'vencido')::boolean, 'mostra quantos dias faltam');
reset role;
select pg_temp.ok(public.avisar_validades() = 1, 'aviso de "vai vencer" é enviado');
select pg_temp.ok(public.avisar_validades() = 0, 'o aviso não se repete');
update public.documentos set valido_ate = (now() at time zone 'America/Sao_Paulo')::date - 1 where id = current_setting('t.doc')::bigint;
select pg_temp.ok(public.avisar_validades() = 1, 'no vencimento sai o aviso de "venceu"');
select pg_temp.ok((select count(*) from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000090a1'
  and tipo in ('documento_vencendo', 'documento_vencido')) = 2, 'o profissional recebe os dois avisos');

-- ---------------------------------------------------------------- respostas prontas
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.ok(jsonb_array_length(public.admin_respostas_prontas()) >= 8, 'a caixa já vem com respostas prontas');
select pg_temp.falha($$select public.admin_salvar_resposta(null, 'Nova', 'Texto novo')$$, 'suporte não cria resposta pronta');
select public.admin_usar_resposta((public.admin_respostas_prontas() -> 0 ->> 'id')::bigint);
select pg_temp.como('00000000-0000-0000-0000-0000000090b1');
select public.admin_salvar_resposta(null, 'Prazo de reembolso', 'Olá, {nome}! O prazo é de 7 dias.');
select pg_temp.falha($$select public.admin_salvar_resposta(null, 'prazo de reembolso', 'Outro texto')$$, 'não cria duas com o mesmo nome');
select pg_temp.ok(exists (select 1 from jsonb_array_elements(public.admin_respostas_prontas()) x where x ->> 'titulo' = 'Prazo de reembolso'),
  'responsável cria resposta pronta');
select public.admin_apagar_resposta((select (x ->> 'id')::bigint from jsonb_array_elements(public.admin_respostas_prontas()) x where x ->> 'titulo' = 'Prazo de reembolso'));
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(public.admin_respostas_prontas()) x where x ->> 'titulo' = 'Prazo de reembolso'),
  'responsável apaga resposta pronta');
select pg_temp.como('00000000-0000-0000-0000-0000000090f1');
select pg_temp.falha($$select public.admin_respostas_prontas()$$, 'marketing não vê a caixa de e-mail');

-- ---------------------------------------------------------------- precisa de atenção
reset role;
insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, combinado_para, endereco_texto, localizacao, responder_ate,
  status, aceito_em, criado_em, preco_informado) values
  ('00000000-0000-0000-0000-0000000090c1', '00000000-0000-0000-0000-0000000090a1', 'eletricista', 'combinado', now() - interval '1 hour', 'SQS 308',
   public.ponto(-15.815, -47.896), now() + interval '1 hour', 'aceito', now() - interval '2 days', now() - interval '2 days', 100);
insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate,
  status, aceito_em, a_caminho_em, criado_em, preco_informado) values
  ('00000000-0000-0000-0000-0000000090c1', '00000000-0000-0000-0000-0000000090a1', 'eletricista', 'agora', 'SQS 308',
   public.ponto(-15.815, -47.896), now() + interval '1 hour', 'a_caminho', now() - interval '3 hours', now() - interval '2 hours', now() - interval '3 hours', 100);
-- Três cancelamentos depois de aceitar nos últimos 30 dias.
insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate,
  status, aceito_em, cancelado_por, encerrado_em, criado_em, preco_informado)
select '00000000-0000-0000-0000-0000000090c1', '00000000-0000-0000-0000-0000000090a1', 'eletricista', 'agora', 'SQS 308',
  public.ponto(-15.815, -47.896), now(), 'cancelado', now() - make_interval(days => g), '00000000-0000-0000-0000-0000000090a1',
  now() - make_interval(days => g) + interval '1 hour', now() - make_interval(days => g), 100
from generate_series(1, 3) g;

select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.ok((select count(*) from jsonb_array_elements(public.admin_atencao() -> 'pedidos') x where x ->> 'tipo' = 'nao_saiu') = 1,
  'pedido marcado em que o profissional não saiu aparece');
select pg_temp.ok((select count(*) from jsonb_array_elements(public.admin_atencao() -> 'pedidos') x where x ->> 'tipo' = 'demorando_chegar') = 1,
  'profissional a caminho há 2 horas aparece');
select pg_temp.ok((select count(*) from jsonb_array_elements(public.admin_atencao() -> 'pedidos') x where x ->> 'tipo' = 'cancelou_apos_aceite') = 1,
  'cancelamento depois de aceitar nas últimas 24h aparece');
select pg_temp.ok(exists (select 1 from jsonb_array_elements(public.admin_atencao() -> 'profissionais') x, jsonb_array_elements(x -> 'motivos') m
  where x ->> 'profissional_id' = '00000000-0000-0000-0000-0000000090a1' and m ->> 'codigo' = 'cancelou' and m ->> 'nivel' = 'alto'),
  'profissional com 3 cancelamentos vira alerta alto');
select pg_temp.ok(jsonb_typeof(public.admin_atencao() -> 'documentos') = 'array', 'suporte vê os documentos vencendo');
select pg_temp.ok((public.admin_atencao_contagem() ->> 'total')::int >= 4, 'o menu mostra a contagem');
select public.admin_atencao_tratado((select x ->> 'chave' from jsonb_array_elements(public.admin_atencao() -> 'pedidos') x where x ->> 'tipo' = 'nao_saiu'),
  'Liguei para o profissional, ele está saindo');
select pg_temp.ok((select count(*) from jsonb_array_elements(public.admin_atencao() -> 'pedidos') x where x ->> 'tipo' = 'nao_saiu') = 0,
  '"Já tratei" tira o item da fila');
select pg_temp.ok(jsonb_array_length(public.admin_gestao_pessoa('00000000-0000-0000-0000-0000000090a1') -> 'alertas') >= 1,
  'a ficha do profissional mostra os alertas');
select public.admin_atencao_tratado((select x ->> 'chave' from jsonb_array_elements(public.admin_atencao() -> 'profissionais') x
  where x ->> 'profissional_id' = '00000000-0000-0000-0000-0000000090a1'));
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(public.admin_atencao() -> 'profissionais') x
  where x ->> 'profissional_id' = '00000000-0000-0000-0000-0000000090a1'), 'alerta tratado sai da fila');
select pg_temp.ok(jsonb_array_length(public.admin_gestao_pessoa('00000000-0000-0000-0000-0000000090a1') -> 'alertas') >= 1,
  'mas continua visível na ficha');
select pg_temp.como('00000000-0000-0000-0000-0000000090f1');
select pg_temp.falha($$select public.admin_atencao()$$, 'marketing não vê a fila de atenção');
select pg_temp.ok((public.admin_atencao_contagem() ->> 'total')::int = 0, 'contagem do marketing é zero');

-- ---------------------------------------------------------------- relatórios
select pg_temp.como('00000000-0000-0000-0000-0000000090f1');
select pg_temp.ok((public.admin_relatorio(current_date - 29, current_date) #>> '{atual,pedidos}')::int = 5, 'relatório conta os pedidos do período');
select pg_temp.ok((public.admin_relatorio(current_date - 29, current_date) #>> '{atual,cancelados_profissional}')::int = 3, 'separa os cancelados pelo profissional');
select pg_temp.ok(jsonb_array_length(public.admin_relatorio(current_date - 6, current_date) -> 'por_dia') = 7, 'série por dia tem um ponto por dia');
select pg_temp.ok(jsonb_typeof(public.admin_relatorio(current_date - 6, current_date) -> 'anterior') = 'object', 'traz o período anterior para comparar');
select pg_temp.falha($$select public.admin_relatorio(current_date, current_date - 1)$$, 'período invertido é recusado');
select pg_temp.falha($$select public.admin_relatorio(current_date - 500, current_date)$$, 'período maior que 400 dias é recusado');
select pg_temp.falha($$select public.admin_planilha_pedidos(current_date - 29, current_date)$$, 'marketing não baixa a planilha de pedidos (tem nomes)');
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.falha($$select public.admin_relatorio(current_date - 6, current_date)$$, 'suporte não vê relatórios');
select pg_temp.ok(jsonb_array_length(public.admin_planilha_pedidos(current_date - 29, current_date)) = 5, 'suporte baixa a planilha de pedidos');

-- ---------------------------------------------------------------- cadastros incompletos
select pg_temp.como('00000000-0000-0000-0000-0000000090e1');
select pg_temp.ok(exists (select 1 from jsonb_array_elements(public.admin_cadastros_incompletos()) x
  where x ->> 'id' = '00000000-0000-0000-0000-0000000090a2' and jsonb_array_length(x -> 'pendencias') > 0), 'quem está preenchendo aparece com o que falta');
select pg_temp.ok((select x ->> 'telefone' is null from jsonb_array_elements(public.admin_cadastros_incompletos()) x
  where x ->> 'id' = '00000000-0000-0000-0000-0000000090a2'), 'suporte não vê o telefone na lista');
select pg_temp.ok(public.admin_lembrar_cadastro(array['00000000-0000-0000-0000-0000000090a2', '00000000-0000-0000-0000-0000000090a1']::uuid[]) = 1,
  'lembrete vai só para quem está com o cadastro incompleto');
select pg_temp.ok(public.admin_lembrar_cadastro(array['00000000-0000-0000-0000-0000000090a2']::uuid[]) = 0, 'no máximo um lembrete por dia');
reset role;
select pg_temp.ok((select corpo like 'Rita, para concluir o seu cadastro no iService falta: %' from public.notificacoes
  where usuario_id = '00000000-0000-0000-0000-0000000090a2' and tipo = 'completar_cadastro'), 'o lembrete diz o que falta, pelo nome');
select pg_temp.como('00000000-0000-0000-0000-0000000090f1');
select pg_temp.falha($$select public.admin_lembrar_cadastro(array['00000000-0000-0000-0000-0000000090a2']::uuid[])$$, 'marketing não manda lembrete');

-- ---------------------------------------------------------------- de fora da equipe
select pg_temp.como('00000000-0000-0000-0000-0000000090c1');
select pg_temp.falha($$select public.admin_atencao_contagem()$$, 'cliente não usa nada do painel');
select pg_temp.falha($$select public.admin_notas('pessoa', auth.uid())$$, 'cliente não lê anotações');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.advertencias', 'select')
  and not has_table_privilege('authenticated', 'public.atencao_vistos', 'select'), 'cliente não lê advertências nem a fila');

rollback;
