-- Testes do valor mínimo por profissão e região e do acréscimo fora do horário comercial
-- (migração 20261118003300). Transação desfeita no fim.
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

create function pg_temp.minimos(p text) returns numeric[] language sql as $$
  select array_agg(valor order by faixa) from public.precos_minimos where profissao_id = p and faixa is not null
$$;

grant execute on all functions in schema pg_temp to authenticated;

-- ------------------------------------------------------------ tabela aprovada
select pg_temp.ok((select count(*) from public.precos_minimos where faixa is not null) = 5 * (select count(*) from public.profissoes),
  'toda profissão tem mínimo nas 5 faixas');
select pg_temp.ok(pg_temp.minimos('eletricista') = array[55, 50, 45, 40, 35]::numeric[], 'eletricista: 55, 50, 45, 40, 35');
select pg_temp.ok(pg_temp.minimos('chaveiro') = array[40, 35, 30, 30, 25]::numeric[], 'chaveiro: 40, 35, 30, 30, 25');
select pg_temp.ok(pg_temp.minimos('faxineira') = array[125, 110, 100, 90, 80]::numeric[], 'faxineira (diária): 125 a 80');
select pg_temp.ok(pg_temp.minimos('ar') = array[245, 215, 190, 175, 155]::numeric[], 'ar-condicionado: 245 a 155');
select pg_temp.ok(pg_temp.minimos('pets') = array[30, 25, 25, 20, 20]::numeric[], 'animais de estimação: 30 a 20');
select pg_temp.ok(pg_temp.minimos('promotor') = array[105, 90, 80, 75, 65]::numeric[], 'promotor de eventos (diária): 105 a 65');

select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-sul', 'servico') = 55, 'Asa Sul usa a faixa 1');
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'luziania', 'servico') = 35, 'Luziânia usa a faixa do Entorno');
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-sul', 'hora') = 20, 'por hora é convertido (55 × 0,4 ≈ 20)');
select pg_temp.ok(public.preco_minimo_profissao('faxineira', 'asa-sul', 'servico') = 50, 'faxineira por serviço é convertida da diária');
select pg_temp.ok(public.preco_minimo_profissao('eletricista', null, 'servico') = 35, 'sem região ainda vale a faixa mais barata');

-- Profissão nova já nasce com mínimos.
insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem)
values ('teste-minimo', 'Teste', 'handyman', '#000000', '#000000', 100, false, '{}', 99);
select pg_temp.ok(pg_temp.minimos('teste-minimo') = array[70, 60, 55, 50, 45]::numeric[], 'profissão nova ganha os mínimos sozinha');

-- ------------------------------------------------------------ trava no cadastro
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000f1', 'pisopro@teste.com', '{"nome":"Paulo Piso","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000f2', 'pisocli@teste.com', '{"nome":"Clara Cliente","app":"cliente"}');
-- Conta verificada (e-mail ou SMS) para poder pedir e receber pedidos.
update public.perfis set email_verificado = true where not email_verificado;
update public.profissionais set regiao_id = 'asa-sul' where id = '00000000-0000-0000-0000-0000000000f1';
insert into public.profissional_profissoes values ('00000000-0000-0000-0000-0000000000f1', 'eletricista', true);
insert into public.profissional_especialidades (profissional_id, especialidade_id)
select '00000000-0000-0000-0000-0000000000f1', id from public.especialidades where profissao_id = 'eletricista' and ordem = 0;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
do $$ begin
  update public.profissional_especialidades set preco = 40 where profissional_id = auth.uid();
  raise exception 'FALHOU: aceitou preço abaixo do mínimo';
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  if sqlerrm not like '%mínimo de Eletricista na sua região é R$ 55 por serviço%' then raise exception 'FALHOU: mensagem errada: %', sqlerrm; end if;
  raise notice 'ok - profissional não salva preço abaixo do mínimo da região, com mensagem clara';
end $$;
update public.profissional_especialidades set preco = 55 where profissional_id = auth.uid();
select pg_temp.ok((select preco from public.profissional_especialidades where profissional_id = auth.uid()) = 55, 'preço igual ao mínimo é aceito');
do $$ begin
  update public.profissional_especialidades set cobranca = 'diaria' where profissional_id = auth.uid();
  raise exception 'FALHOU: aceitou trocar para diária com valor abaixo do mínimo da diária';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - trocar a forma de cobrança também confere o mínimo';
end $$;
update public.profissional_especialidades set cobranca = 'hora', preco = 20 where profissional_id = auth.uid();
select pg_temp.ok(true, 'por hora aceita o mínimo convertido');
update public.profissional_especialidades set cobranca = 'servico', preco = 60 where profissional_id = auth.uid();

-- O profissional não mexe na tabela de mínimos.
do $$ begin
  update public.precos_minimos set valor = 1 where profissao_id = 'eletricista';
  if exists (select 1 from public.precos_minimos where valor = 1) then raise exception 'FALHOU: profissional mudou o mínimo'; end if;
  raise notice 'ok - profissional não muda o mínimo';
exception when insufficient_privilege then raise notice 'ok - profissional não muda o mínimo';
end $$;
do $$ begin
  perform public.admin_definir_minimo('eletricista', 1::smallint, null, 10);
  raise exception 'FALHOU: profissional usou a função do painel';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - só a equipe usa a função do painel';
end $$;

-- A faixa "comum na região" nunca fica abaixo do mínimo.
select pg_temp.ok((select bool_and(f.minimo >= public.preco_minimo(e.id, 'asa-sul', 'servico'))
  from public.especialidades e cross join lateral public.faixa_preco(e.id, 'asa-sul', 'servico') f), 'faixa de referência respeita o mínimo');

-- ------------------------------------------------------------ painel
reset role;
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000f2';
insert into public.equipe (email, nome, papel, usuario_id) values ('gerente-piso@teste.com', 'Gerente', 'gerente', '00000000-0000-0000-0000-0000000000f2');
select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
select public.admin_definir_minimo('eletricista', 1::smallint, null, 70);
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-norte', 'servico') = 70, 'equipe sobe o mínimo da faixa');
select pg_temp.ok((select abaixo from public.admin_tabela_minimos() where profissao_id = 'eletricista' and faixa = 1 and regiao_id is null) = 1,
  'painel mostra quantos ficaram abaixo do novo mínimo');
select pg_temp.ok('especialidades_e_precos' = any (public.pendencias_profissional('00000000-0000-0000-0000-0000000000f1')),
  'preço que ficou abaixo do mínimo volta a ser pendência');
select public.admin_definir_minimo('eletricista', 1::smallint, null, null);
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-norte', 'servico') = 55, 'remover o ajuste volta ao valor da regra');
select public.admin_definir_minimo('eletricista', null, 'asa-sul', 80);
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-sul', 'servico') = 80
  and public.preco_minimo_profissao('eletricista', 'asa-norte', 'servico') = 55, 'mínimo próprio de uma região vale só nela');
select public.admin_definir_minimo('eletricista', null, 'asa-sul', null);
select pg_temp.ok(public.preco_minimo_profissao('eletricista', 'asa-sul', 'servico') = 55, 'mínimo próprio da região pode ser removido');

-- ------------------------------------------------------------ fora do horário comercial
select pg_temp.ok(not public.fora_do_horario('2026-11-17 10:00-03'), 'terça 10h é horário comercial');
select pg_temp.ok(public.fora_do_horario('2026-11-17 18:00-03'), 'terça 18h já é fora do horário');
select pg_temp.ok(public.fora_do_horario('2026-11-17 07:59-03'), 'terça 7h59 é fora do horário');
select pg_temp.ok(not public.fora_do_horario('2026-11-21 11:00-03'), 'sábado 11h é horário comercial');
select pg_temp.ok(public.fora_do_horario('2026-11-21 13:00-03'), 'sábado 13h é fora do horário');
select pg_temp.ok(public.fora_do_horario('2026-11-22 10:00-03'), 'domingo é sempre fora do horário');
select pg_temp.ok(public.fora_do_horario('2026-11-20 10:00-03'), 'feriado é sempre fora do horário');
select pg_temp.ok(public.taxa_fora_horario(100, '2026-11-17 20:00-03') = 20, '20% de R$ 100 à noite = R$ 20');
select pg_temp.ok(public.taxa_fora_horario(100, '2026-11-17 10:00-03') = 0, 'no horário comercial não tem acréscimo');

reset role;
insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, combinado_para, endereco_texto, localizacao, responder_ate, preco_informado)
values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1', 'eletricista', 'combinado',
  '2026-11-22 10:00-03', 'SQS 308', public.ponto(-15.815, -47.896), now() + interval '2 hours', 150);
select pg_temp.ok((select taxa_fora_horario from public.pedidos where profissional_id = '00000000-0000-0000-0000-0000000000f1') = 30,
  'pedido marcado para domingo nasce com 20% de acréscimo');
update public.pedidos set combinado_para = '2026-11-24 10:00-03' where profissional_id = '00000000-0000-0000-0000-0000000000f1';
select pg_temp.ok((select taxa_fora_horario from public.pedidos where profissional_id = '00000000-0000-0000-0000-0000000000f1') = 0,
  'mudar para terça de manhã tira o acréscimo');
select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
select pg_temp.ok((select taxa_fora_horario from public.meus_pedidos('cliente')) = 0, 'lista de pedidos traz o acréscimo');

reset role;
rollback;
