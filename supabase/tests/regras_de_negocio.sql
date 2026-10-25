-- Testes das regras de negócio. Rodam numa transação desfeita no fim.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/regras_de_negocio.sql
begin;

create function pg_temp.cpf(base text) returns text language plpgsql as $$
declare d int[]; s int; i int; v1 int; v2 int;
begin
  d := regexp_split_to_array(base, '')::int[];
  s := 0; for i in 1..9 loop s := s + d[i] * (11 - i); end loop; v1 := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  s := 0; for i in 1..9 loop s := s + d[i] * (12 - i); end loop; s := s + v1 * 2; v2 := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  return base || v1 || v2;
end $$;

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

grant execute on all functions in schema pg_temp to authenticated;

-- ---------------------------------------------------------------- dados
-- 1 cliente na Asa Sul e 6 eletricistas: 2 bem avaliados, 1 novo, 1 longe, 2 a mais para o teste de lançamento.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000c1', 'marina@teste.com', '{"nome":"Marina Alves","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'carlos@teste.com', '{"nome":"Carlos Silva","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'alex@teste.com', '{"nome":"Alex Pereira","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'rafa@teste.com', '{"nome":"Rafael Souza","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000a4', 'luis@teste.com', '{"nome":"Luís Martins","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000a5', 'andre@teste.com', '{"nome":"André Lima","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000a6', 'diego@teste.com', '{"nome":"Diego Ferreira","app":"profissional"}');

select pg_temp.ok((select count(*) from public.perfis) = 7, 'perfil criado junto com o usuário');
select pg_temp.ok((select count(*) from public.profissionais) = 6, 'cadastro de profissional criado pelo app Profissional');

update public.perfis set nascimento = '1990-01-01', telefone = '61981234567', foto_url = 'fotos/' || id || '/perfil.jpg',
  cpf = pg_temp.cpf(lpad((row_number_cpf)::text, 9, '1'))
from (select id as pid, row_number() over (order by id) + 100000000 as row_number_cpf from public.perfis) n where n.pid = perfis.id;

-- --------------------------------------------------- cadastro do cliente
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((public.concluir_cadastro_cliente() -> 'pendencias') ? 'endereco', 'cliente sem endereço não conclui o cadastro');
select public.salvar_endereco('SQS 308', -15.8150, -47.8960, 'asa-sul', 'Bloco C', null, 'Apto 101', 'Perto da Igrejinha', '70355-030');
select pg_temp.ok((public.concluir_cadastro_cliente() ->> 'ok')::boolean, 'cliente conclui o cadastro com foto, CPF e endereço');
do $$ begin
  perform cpf from public.perfis limit 1;
  raise exception 'FALHOU: cpf legível';
exception when insufficient_privilege then raise notice 'ok - CPF não é legível por outros usuários';
end $$;
do $$ begin
  insert into public.pedidos (cliente_id, profissional_id, profissao_id, quando, endereco_texto, localizacao, responder_ate)
  values (auth.uid(), '00000000-0000-0000-0000-0000000000a1', 'eletricista', 'agora', 'x', public.ponto(0, 0), now());
  raise exception 'FALHOU: insert direto em pedidos';
exception when insufficient_privilege then raise notice 'ok - pedidos só nascem pela função criar_pedido';
end $$;
select pg_temp.admin();

-- ----------------------------------------------- cadastro do profissional
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((public.enviar_cadastro_profissional() ->> 'ok')::boolean = false, 'profissional incompleto não vai para análise');
select pg_temp.admin();

-- Completa os 6 profissionais como postgres (mesmo efeito das telas de cadastro).
insert into public.enderecos (usuario_id, logradouro, regiao_id, localizacao, principal)
select id, 'Endereço', 'asa-sul', public.ponto(-15.81, -47.89), true from public.profissionais;
update public.profissionais set area_raio_km = 15, regiao_id = 'asa-sul', area_centro = case id
  when '00000000-0000-0000-0000-0000000000a1' then public.ponto(-15.8100, -47.8900)  -- ~1 km
  when '00000000-0000-0000-0000-0000000000a2' then public.ponto(-15.7630, -47.8820)  -- Asa Norte ~6 km
  when '00000000-0000-0000-0000-0000000000a3' then public.ponto(-15.8300, -47.9800)  -- Guará ~9 km
  when '00000000-0000-0000-0000-0000000000a4' then public.ponto(-16.2530, -47.9500)  -- Luziânia ~49 km
  when '00000000-0000-0000-0000-0000000000a5' then public.ponto(-15.7990, -47.9250)
  else public.ponto(-15.8400, -47.8500) end;
insert into public.profissional_profissoes (profissional_id, profissao_id, principal) select id, 'eletricista', true from public.profissionais;
insert into public.profissional_especialidades (profissional_id, especialidade_id, preco)
select p.id, e.id, 120 from public.profissionais p join public.especialidades e on e.profissao_id = 'eletricista' and e.ordem < 3;
insert into public.documentos (profissional_id, tipo, arquivo_path)
select id, t, 'documentos/' || id || '/' || t from public.profissionais, unnest(array['documento_frente', 'selfie_documento']::public.tipo_documento[]) t;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok((public.enviar_cadastro_profissional() ->> 'status') = 'em_analise', 'cadastro completo vai para análise');
do $$ begin
  update public.profissionais set status = 'aprovado' where id = auth.uid();
  raise exception 'FALHOU: profissional se aprovou';
exception when insufficient_privilege then raise notice 'ok - profissional não aprova o próprio cadastro';
end $$;
do $$ begin
  perform public.definir_disponivel(true);
  raise exception 'FALHOU: disponível sem aprovação';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - só fica disponível depois de aprovado';
end $$;
select pg_temp.admin();

update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000c1';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select public.admin_decidir_cadastro(id, true) from public.profissionais;
select pg_temp.admin();
update public.perfis set e_admin = false where id = '00000000-0000-0000-0000-0000000000c1';
update public.profissionais set disponivel = true;

-- --------------------------------------------- busca e visibilidade justa
-- Ninguém com 5+ avaliações: fase de lançamento, todos em rodízio.
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((select bool_and(fase_lancamento) and count(*) = 5 from public.buscar_profissionais('eletricista', -15.8150, -47.8960)),
  'fase de lançamento: todos em rodízio; o de Luziânia (49 km, raio 15) fica fora');
select pg_temp.ok(
  (select array_agg(profissional_id order by posicao) from public.buscar_profissionais('eletricista', -15.8150, -47.8960, null, 'qualidade', 1))
  is distinct from
  (select array_agg(profissional_id order by posicao) from public.buscar_profissionais('eletricista', -15.8150, -47.8960, null, 'qualidade', 2)),
  'o rodízio muda a ordem a cada busca');
select pg_temp.admin();

-- 3 profissionais com 5+ avaliações: ranking por qualidade, novos intercalados.
update public.profissionais set total_avaliacoes = 40, nota_media = 4.7, servicos_concluidos = 50 where id = '00000000-0000-0000-0000-0000000000a1';
update public.profissionais set total_avaliacoes = 90, nota_media = 4.9, servicos_concluidos = 120 where id = '00000000-0000-0000-0000-0000000000a2';
update public.profissionais set total_avaliacoes = 12, nota_media = 4.9, servicos_concluidos = 15 where id = '00000000-0000-0000-0000-0000000000a3';
update public.profissionais set total_avaliacoes = 2, nota_media = 5.0 where id in ('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000a6');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(
  ((select array_agg(right(profissional_id::text, 2) order by posicao) from public.buscar_profissionais('eletricista', -15.8150, -47.8960))::text[])[1:2]
    = array['a2', 'a3'] and
  (select novo from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where posicao = 3),
  'mais bem avaliado primeiro (nota, depois nº de avaliações) e um novo entra a cada dois');
select pg_temp.ok(
  (select right(profissional_id::text, 2) from public.buscar_profissionais('eletricista', -15.8150, -47.8960, null, 'distancia') where posicao = 1) = 'a1',
  'ordenar por distância põe o mais perto primeiro');
select pg_temp.ok((select count(*) from public.top_regiao(-15.8150, -47.8960)) = 3, 'Top da região mostra só quem tem 5+ avaliações');
select pg_temp.ok((select right(profissional_id::text, 2) from public.top_regiao(-15.8150, -47.8960) where posicao = 1) = 'a2', 'Top da região começa pelo melhor');
select pg_temp.ok((select minimo = 120 and maximo = 120 and not estimada and amostras = 6
  from public.faixa_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 'asa-sul')),
  'faixa de preço (P25 a P75) calculada com os preços reais da região');
select pg_temp.ok((select minimo > 0 and maximo > minimo and estimada
  from public.faixa_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 5), 'ceilandia')),
  'faixa estimada enquanto há poucos preços reais');
select pg_temp.admin();

-- Planos: com a cobrança ligada, o alcance do plano grátis (10 km) tira o Alex (6 km fica) e o Rafael (9 km fica)... e o VIP chega a 20.
update public.app_config set valor = 'true' where chave = 'cobranca_ativa';
update public.profissionais set area_raio_km = 50 where id = '00000000-0000-0000-0000-0000000000a4';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(not exists (select 1 from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where right(profissional_id::text, 2) = 'a4'),
  'plano grátis com cobrança ligada não alcança 49 km');
select pg_temp.admin();
update public.profissionais set plano = 'premium', plano_valido_ate = now() + interval '30 days' where id = '00000000-0000-0000-0000-0000000000a4';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((select posicao > 1 from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where right(profissional_id::text, 2) = 'a4'),
  'Premium alcança 50 km mas não compra o primeiro lugar');
select pg_temp.admin();
update public.app_config set valor = 'false' where chave = 'cobranca_ativa';
update public.profissionais set area_raio_km = 15, plano = 'gratis' where id = '00000000-0000-0000-0000-0000000000a4';

-- ------------------------------------------------------- pedido direcionado
create temp table t (pedido uuid);
grant all on t to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
insert into t select (public.criar_pedido('00000000-0000-0000-0000-0000000000a2', 'eletricista',
  (select id from public.enderecos where usuario_id = auth.uid()), 'agora', null, 'Chuveiro parou')).id;
select pg_temp.ok((select status = 'solicitado' and taxa_urgencia = 15 and responder_ate between now() + interval '9 min' and now() + interval '11 min'
  from public.pedidos where id = (select pedido from t)), 'pedido "agora" vai só ao escolhido, com taxa de urgência e 10 min para responder');
do $$ begin
  perform public.criar_pedido('00000000-0000-0000-0000-0000000000a3', 'eletricista', (select id from public.enderecos where usuario_id = auth.uid()), 'agora');
  raise exception 'FALHOU: dois pedidos aguardando';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - um pedido aguardando resposta por vez';
end $$;
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000a2' and tipo = 'pedido_novo') = 1
  and (select count(*) from public.notificacoes where tipo = 'pedido_novo') = 1, 'só o profissional escolhido é notificado');

-- Outro profissional não vê o pedido.
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok((select count(*) from public.pedidos) = 0, 'outro profissional não enxerga o pedido');
select pg_temp.admin();

-- Aceite: some das buscas enquanto atende.
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select public.responder_pedido((select pedido from t), true);
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(not exists (select 1 from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where right(profissional_id::text, 2) = 'a2'),
  'profissional em atendimento some das buscas');
select pg_temp.ok(not exists (select 1 from public.top_regiao(-15.8150, -47.8960) where right(profissional_id::text, 2) = 'a2'),
  'e some do Top da região');
insert into public.mensagens (pedido_id, autor_id, texto) values ((select pedido from t), auth.uid(), 'Oi! O portão é o azul.');
select pg_temp.admin();

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok((select count(*) from public.mensagens) = 1, 'chat chega ao profissional');
select public.avancar_pedido((select pedido from t), 'a_caminho');
select public.avancar_pedido((select pedido from t), 'em_atendimento');
do $$ begin
  perform public.avancar_pedido((select pedido from t), 'concluido');
  raise exception 'FALHOU: concluiu sem valor';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - concluir exige o valor cobrado';
end $$;
select public.avancar_pedido((select pedido from t), 'concluido', 180, 'pix');
select pg_temp.admin();

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(exists (select 1 from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where right(profissional_id::text, 2) = 'a2'),
  'depois de concluir volta às buscas');
select public.avaliar_pedido((select pedido from t), 1::smallint, 'Atrasou');
select pg_temp.admin();
select pg_temp.ok((select total_avaliacoes = 1 and nota_media = 1 and servicos_concluidos = 121 from public.profissionais where id = '00000000-0000-0000-0000-0000000000a2'),
  'avaliação recalcula a nota a partir das avaliações reais');
select pg_temp.ok((select sum(pontos) from public.pontos where usuario_id = '00000000-0000-0000-0000-0000000000c1') = 10, 'cliente ganha pontos ao concluir');

-- Recusa e prazo: o pedido encerra e não vai a mais ninguém.
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
truncate t;
insert into t select (public.criar_pedido('00000000-0000-0000-0000-0000000000a3', 'eletricista',
  (select id from public.enderecos where usuario_id = auth.uid()), 'hoje', null, '', '14:00–16:00')).id;
select pg_temp.admin();
update public.pedidos set responder_ate = now() - interval '1 second' where id = (select pedido from t);
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok((public.responder_pedido((select pedido from t), true)).status = 'expirado', 'não dá para aceitar depois dos 10 minutos');
select pg_temp.admin();
select pg_temp.ok((select status = 'expirado' from public.pedidos where id = (select pedido from t)), 'pedido sem resposta expira');
select pg_temp.ok((select count(*) from public.pedidos where cliente_id = '00000000-0000-0000-0000-0000000000c1') = 2, 'pedido expirado não é repassado a ninguém');

-- Horário combinado: até 7 dias, e aceito não tira o profissional da busca até sair para o local.
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.criar_pedido('00000000-0000-0000-0000-0000000000a3', 'eletricista', (select id from public.enderecos where usuario_id = auth.uid()),
    'combinado', null, '', null, now() + interval '9 days');
  raise exception 'FALHOU: combinado para 9 dias';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - horário combinado só até 7 dias';
end $$;
truncate t;
insert into t select (public.criar_pedido('00000000-0000-0000-0000-0000000000a3', 'eletricista', (select id from public.enderecos where usuario_id = auth.uid()),
  'combinado', null, '', null, now() + interval '2 days')).id;
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select public.responder_pedido((select pedido from t), true);
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(exists (select 1 from public.buscar_profissionais('eletricista', -15.8150, -47.8960) where right(profissional_id::text, 2) = 'a3'),
  'horário combinado aceito não esconde o profissional antes da hora');
select pg_temp.admin();

rollback;
