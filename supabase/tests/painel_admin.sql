-- Testes do painel administrativo. Rodam numa transação desfeita no fim.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/painel_admin.sql
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
-- ad = equipe iService, c1 = cliente, p1 = eletricista, p2 = babá
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'equipe@teste.com', '{"nome":"Equipe iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'marina@teste.com', '{"nome":"Marina Alves","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'carlos@teste.com', '{"nome":"Carlos Silva","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'joana@teste.com', '{"nome":"Joana Lima","app":"profissional"}');
update public.perfis set nascimento = '1990-01-01', telefone = '61981234567', e_cliente = true,
  foto_url = 'https://exemplo.supabase.co/storage/v1/object/public/fotos/' || id || '/perfil.jpg',
  cpf = pg_temp.cpf(lpad((n)::text, 9, '2'))
from (select id as pid, row_number() over (order by id) + 200000000 as n from public.perfis) x where x.pid = perfis.id;
insert into public.enderecos (usuario_id, logradouro, regiao_id, localizacao, principal)
select id, 'SQS 308', 'asa-sul', public.ponto(-15.815, -47.896), true from public.perfis;
update public.profissionais set area_centro = public.ponto(-15.81, -47.89), regiao_id = 'asa-sul';
insert into public.profissional_profissoes values ('00000000-0000-0000-0000-0000000000b1', 'eletricista', true), ('00000000-0000-0000-0000-0000000000b2', 'baba', true);
insert into public.profissional_especialidades (profissional_id, especialidade_id, preco)
select pp.profissional_id, e.id, 100 from public.profissional_profissoes pp join public.especialidades e on e.profissao_id = pp.profissao_id and e.ordem = 0;
insert into public.documentos (profissional_id, tipo, arquivo_path)
select id, t, id || '/' || t || '.jpg' from public.profissionais, unnest(array['documento_frente', 'selfie_documento']::public.tipo_documento[]) t;
insert into public.documentos (profissional_id, tipo, arquivo_path) values ('00000000-0000-0000-0000-0000000000b2', 'antecedentes', '00000000-0000-0000-0000-0000000000b2/antecedentes.pdf');
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.enviar_cadastro_profissional();
select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select public.enviar_cadastro_profissional();
select pg_temp.admin();
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000ad';

-- ------------------------------------------------------ acesso ao painel
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.admin_resumo();
  raise exception 'FALHOU: cliente abriu o painel';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - quem não é da equipe não abre o painel';
end $$;
do $$ begin
  perform public.admin_suspender('00000000-0000-0000-0000-0000000000b1', true, 'x');
  raise exception 'FALHOU: cliente suspendeu alguém';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - e não consegue suspender ninguém';
end $$;
select pg_temp.ok((select count(*) from public.admin_acoes) = 0, 'nem ler o registro de ações');
do $$ begin
  update public.profissoes set ativa = false where id = 'eletricista';
  if exists (select 1 from public.profissoes where id = 'eletricista' and not ativa) then raise exception 'FALHOU: cliente desligou profissão'; end if;
  raise notice 'ok - quem não é da equipe não mexe no catálogo';
end $$;
select pg_temp.admin();

-- --------------------------------------------- fila de cadastros (A01/A02)
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) from public.admin_cadastros()) = 2, 'fila mostra os cadastros em análise');
select pg_temp.ok((select exige_antecedentes from public.admin_cadastros() where id = '00000000-0000-0000-0000-0000000000b2'), 'fila destaca quem precisa de antecedentes');
select pg_temp.ok((select jsonb_array_length(public.admin_usuario('00000000-0000-0000-0000-0000000000b2') -> 'profissional' -> 'documentos')) = 3
  and (public.admin_usuario('00000000-0000-0000-0000-0000000000b2') -> 'perfil' ->> 'cpf') is not null, 'ficha traz documentos e dados completos');
do $$ begin
  perform public.admin_revisar_documento((select id from public.documentos where profissional_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'selfie_documento'), false, '');
  raise exception 'FALHOU: recusou sem motivo';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - pedir nova foto exige o motivo';
end $$;
select public.admin_revisar_documento((select id from public.documentos where profissional_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'selfie_documento'),
  false, 'Rosto cortado na foto.');
select pg_temp.admin();
select pg_temp.ok((select status = 'recusado' and motivo_status like 'Envie de novo a selfie%' from public.profissionais where id = '00000000-0000-0000-0000-0000000000b1'),
  'pedir nova foto devolve o cadastro com o motivo');
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'documento_recusado'),
  'e avisa o profissional');
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok('selfie' = any(public.pendencias_profissional(auth.uid())), 'profissional vê a selfie como pendência');
insert into public.documentos (profissional_id, tipo, arquivo_path) values (auth.uid(), 'selfie_documento', auth.uid() || '/selfie2.jpg');
select pg_temp.ok((public.enviar_cadastro_profissional() ->> 'status') = 'em_analise', 'reenvia e volta para a fila');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_decidir_cadastro('00000000-0000-0000-0000-0000000000b1', true);
select public.admin_decidir_cadastro('00000000-0000-0000-0000-0000000000b2', true);
select pg_temp.admin();
select pg_temp.ok((select bool_and(status = 'aprovado' and verificado) from public.profissionais), 'aprovação marca como verificado');
select pg_temp.ok((select status = 'aprovado' from public.documentos where tipo = 'antecedentes'), 'aprovar o cadastro aprova a certidão de antecedentes');
select pg_temp.ok((select count(*) from public.admin_acoes where acao in ('aprovar_cadastro', 'recusar_documento')) = 3, 'cada decisão fica no registro');
update public.profissionais set disponivel = true;

-- ------------------------------------------------------- buscas (A06/A07)
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((select count(*) from public.buscar_profissionais('eletricista', -15.8150, -47.8960)) = 1, 'busca continua funcionando');
select public.buscar_profissionais('eletricista', -15.8150, -47.8960);
select public.buscar_profissionais('pintor', -15.8190, -48.1080);
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.buscas) = 2, 'cada busca é registrada uma vez (repetição seguida não conta)');
select pg_temp.ok((select regiao_id = 'ceilandia' and resultados = 0 and lat = -15.82 from public.buscas where profissao_id = 'pintor'),
  'busca sem resultado guarda a região e o local arredondado');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((public.admin_resumo() ->> 'buscas')::int = 2 and (public.admin_resumo() ->> 'buscas_sem_resultado')::int = 1, 'números do dia contam as buscas');
select pg_temp.ok((select sem_resultado from public.admin_buscas_por_regiao() where regiao_id = 'ceilandia' and profissao_id = 'pintor') = 1, 'buscas sem resultado por região e profissão');
select pg_temp.ok((select count(*) from public.admin_mapa_buscas()) = 1, 'mapa mostra só as buscas sem resultado');
select pg_temp.admin();

-- ------------------------------------------ pedidos, garantia e denúncias
create temp table t (pedido uuid);
grant all on t to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
insert into t select (public.criar_pedido('00000000-0000-0000-0000-0000000000b1', 'eletricista',
  (select id from public.enderecos where usuario_id = auth.uid()), 'agora', null, 'Tomada queimada')).id;
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.responder_pedido((select pedido from t), true);
insert into public.mensagens (pedido_id, autor_id, texto) values ((select pedido from t), auth.uid(), 'Chego em 20 minutos.');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) from public.admin_pedidos('andamento')) = 1, 'lista de pedidos em andamento');
select pg_temp.ok((public.admin_pedido((select pedido from t)) -> 'mensagens') = 'null'::jsonb, 'sem reclamação a equipe não lê a conversa');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select public.abrir_reclamacao((select pedido from t), 'Serviço mal feito', 'A tomada continua sem funcionar.');
select pg_temp.ok(public.denunciar('00000000-0000-0000-0000-0000000000b1', 'Comportamento inadequado', 'Foi grosseiro.', (select pedido from t)) > 0, 'cliente denuncia pelo app');
do $$ begin
  perform public.denunciar(auth.uid(), 'x');
  raise exception 'FALHOU: denunciou a si mesmo';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - não dá para denunciar a própria conta';
end $$;
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok(jsonb_array_length(public.admin_pedido((select pedido from t)) -> 'mensagens') = 1, 'com reclamação a conversa fica visível para a mediação');
select pg_temp.ok((select count(*) from public.admin_reclamacoes()) = 1, 'fila da garantia mostra a reclamação aberta');
select public.admin_mediar_reclamacao((select id from public.reclamacoes limit 1), 'em_mediacao', 'Vamos falar com o profissional.', true);
do $$ begin
  perform public.admin_mediar_reclamacao((select id from public.reclamacoes limit 1), 'resolvida', '', false);
  raise exception 'FALHOU: fechou sem resolução';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - fechar a reclamação exige a resolução';
end $$;
select public.admin_mediar_reclamacao((select id from public.reclamacoes limit 1), 'resolvida', 'Profissional voltou e trocou a tomada.', true);
select pg_temp.ok((select count(*) from public.admin_reclamacao_historico((select id from public.reclamacoes limit 1))) = 2, 'histórico da mediação');
select pg_temp.ok((select count(*) from public.admin_denuncias()) = 1, 'fila de denúncias');
select public.admin_resolver_denuncia((select id from public.denuncias limit 1), 'procedente', 'Advertência enviada.');
select pg_temp.ok((select count(*) from public.admin_denuncias()) = 0, 'denúncia resolvida sai da fila');
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.notificacoes where tipo = 'garantia') = 4, 'mediação avisa cliente e profissional');

-- ------------------------------------------------ avaliações suspeitas (A04)
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.avancar_pedido((select pedido from t), 'em_atendimento');
select public.avancar_pedido((select pedido from t), 'concluido', 90, 'pix');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select public.avaliar_pedido((select pedido from t), 5::smallint, 'Ótimo! Me chama no zap 61 9999-8888');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select 'Comentário com contato ou link' = any(sinais) and 'Serviço concluído em menos de 10 min' = any(sinais)
  from public.admin_avaliacoes_suspeitas() where pedido_id = (select pedido from t)), 'avaliação com contato e serviço relâmpago é sinalizada');
select public.admin_ocultar_avaliacao((select pedido from t), true, 'Avaliação combinada');
select pg_temp.admin();
select pg_temp.ok((select total_avaliacoes = 0 and nota_media = 0 from public.profissionais where id = '00000000-0000-0000-0000-0000000000b1'),
  'avaliação oculta não conta na nota');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(jsonb_array_length(public.perfil_profissional('00000000-0000-0000-0000-0000000000b1') -> 'avaliacoes_recentes') = 0, 'nem aparece no perfil');
select pg_temp.admin();

-- --------------------------------------------------------- suspensão (A03)
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
do $$ begin
  perform public.admin_suspender('00000000-0000-0000-0000-0000000000c1', true, '');
  raise exception 'FALHOU: suspendeu sem motivo';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - suspender exige o motivo';
end $$;
select public.admin_suspender('00000000-0000-0000-0000-0000000000c1', true, 'Denúncias repetidas');
select public.admin_suspender('00000000-0000-0000-0000-0000000000b1', true, 'Documento falso');
select pg_temp.admin();
select pg_temp.ok((select banned_until = 'infinity' from auth.users where id = '00000000-0000-0000-0000-0000000000c1'), 'suspensão bloqueia o login');
select pg_temp.ok((select status = 'suspenso' and not disponivel from public.profissionais where id = '00000000-0000-0000-0000-0000000000b1'), 'profissional suspenso sai das buscas');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.criar_pedido('00000000-0000-0000-0000-0000000000b2', 'baba', (select id from public.enderecos where usuario_id = auth.uid()), 'agora');
  raise exception 'FALHOU: suspenso fez pedido';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - cliente suspenso não faz pedidos';
end $$;
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_suspender('00000000-0000-0000-0000-0000000000c1', false);
select public.admin_suspender('00000000-0000-0000-0000-0000000000b1', false);
select pg_temp.admin();
select pg_temp.ok((select banned_until is null from auth.users where id = '00000000-0000-0000-0000-0000000000c1')
  and (select status = 'aprovado' from public.profissionais where id = '00000000-0000-0000-0000-0000000000b1'), 'reativar devolve o acesso e o cadastro aprovado');

-- ---------------------------------------------------------- catálogo (A05)
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
update public.regioes set ativa = false where id = 'asa-sul';
update public.profissoes set nome = 'Eletricista residencial' where id = 'eletricista';
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.criar_pedido('00000000-0000-0000-0000-0000000000b2', 'baba', (select id from public.enderecos where usuario_id = auth.uid()), 'agora');
  raise exception 'FALHOU: pedido em região desligada';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - região desligada não recebe pedidos';
end $$;
select pg_temp.admin();
select pg_temp.ok((select nome = 'Eletricista residencial' from public.profissoes where id = 'eletricista'), 'equipe edita profissões');
select pg_temp.ok((select count(*) from public.admin_acoes where acao in ('update_regioes', 'update_profissoes')) = 2, 'mudanças no catálogo ficam no registro');
update public.regioes set ativa = true where id = 'asa-sul';

-- -------------------------------------------------------- comunicado (A08)
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok(public.admin_contar_publico('eletricista', 'asa-sul', 'aprovados') = 1, 'prévia conta o público do comunicado');
select pg_temp.ok(public.admin_enviar_comunicado('Chuva forte amanhã', 'Muitos pedidos de eletricista previstos.', 'eletricista', 'asa-sul') = 1,
  'comunicado vai só para o grupo escolhido');
select pg_temp.admin();
select pg_temp.ok((select count(*) from public.notificacoes where tipo = 'comunicado') = 1
  and exists (select 1 from public.notificacoes where tipo = 'comunicado' and usuario_id = '00000000-0000-0000-0000-0000000000b1'), 'eletricista da Asa Sul recebe');

-- ---------------------------------------------- preço de referência (A09)
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((select count(*) from public.admin_tabela_precos('eletricista')) = 5 * (select count(*) from public.especialidades where profissao_id = 'eletricista' and aprovada),
  'tabela mostra cada especialidade nas 5 faixas');
select public.admin_ajustar_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 1::smallint, 150, 260);
select pg_temp.ok((select minimo = 150 and maximo = 260 and not estimada from public.faixa_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 'asa-sul')),
  'ajuste da equipe vale no app');
select public.admin_ajustar_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 1::smallint);
select pg_temp.ok((select minimo <> 150 from public.faixa_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 'asa-sul')),
  'remover o ajuste volta ao cálculo');
do $$ begin
  perform public.admin_ajustar_preco((select id from public.especialidades where profissao_id = 'eletricista' and ordem = 0), 1::smallint, 300, 100);
  raise exception 'FALHOU: faixa invertida';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - faixa com máximo menor que o mínimo é recusada';
end $$;

-- --------------------------------------------------------------- emergência
select pg_temp.admin();
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select public.acionar_emergencia((select pedido from t), -15.815, -47.896);
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((public.admin_resumo() ->> 'emergencias_abertas')::int = 1, 'emergência aparece no painel');
select public.admin_atender_emergencia((select id from public.emergencias limit 1), 'Liguei para a cliente, está tudo bem.');
select pg_temp.ok((public.admin_resumo() ->> 'emergencias_abertas')::int = 0, 'emergência atendida sai da fila');
select pg_temp.ok((select count(*) from public.admin_registro()) > 5, 'registro de ações da equipe');
select pg_temp.admin();

-- ---------------------------------------------------------------- e-mails de cada etapa
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'cadastro_recebido'),
  'cadastro enviado gera aviso de cadastro recebido');
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'cadastro_recebido'
  and (dados ->> 'reenvio')::boolean), 'cadastro reenviado também avisa');
select pg_temp.ok(exists (select 1 from public.notificacoes where tipo = 'reclamacao_aberta')
  and exists (select 1 from public.notificacoes where tipo = 'reclamacao_recebida'), 'reclamação avisa quem abriu e a outra parte');
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000b1' and tipo = 'conta_suspensa'
  and corpo = 'Documento falso'), 'suspensão avisa com o motivo');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000c1';
select pg_temp.ok(exists (select 1 from public.notificacoes where usuario_id = '00000000-0000-0000-0000-0000000000c1' and tipo = 'boas_vindas'),
  'confirmar o e-mail gera boas-vindas');
select pg_temp.ok(public.tipo_tem_email('cadastro_aprovado') and not public.tipo_tem_email('mensagem'), 'só avisos importantes vão por e-mail');

rollback;
