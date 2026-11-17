-- Testes dos formulários do site: sugestão de profissão e reclamação (migração 20261117003200).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.anonimo(ip text default '200.1.1.1') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.headers', json_build_object('x-forwarded-for', ip || ', 10.0.0.1')::text, true);
  execute 'set local role anon';
end $$;

create function pg_temp.admin() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create function pg_temp.ok(cond boolean, nome text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', nome; end if;
  raise notice 'ok - %', nome;
end $$;

create function pg_temp.falha(sql text, nome text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    raise notice 'ok - %', nome;
    return;
  end;
  raise exception 'FALHOU: % (não deu erro)', nome;
end $$;

grant execute on all functions in schema pg_temp to anon, authenticated;

-- ---------------------------------------------------------------- equipe
-- ad = dono, mk = marketing, sp = suporte
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'dono@teste.com', now(), '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e1', 'mk@teste.com', now(), '{"nome":"Maria Marketing","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'sp@teste.com', now(), '{"nome":"Sergio Suporte","app":"cliente"}');
update public.perfis p set email = u.email from auth.users u where u.id = p.id;
update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2');
insert into public.equipe (email, nome, papel, usuario_id, convidado_em, recebe_emails) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000ad', now() - interval '3 days', true),
  ('mk@teste.com', 'Maria Marketing', 'marketing', '00000000-0000-0000-0000-0000000000e1', now() - interval '2 days', false),
  ('sp@teste.com', 'Sergio Suporte', 'suporte', '00000000-0000-0000-0000-0000000000e2', now() - interval '1 day', true)
on conflict (email) do update set papel = excluded.papel, usuario_id = excluded.usuario_id, recebe_emails = excluded.recebe_emails;

-- ---------------------------------------------------------------- tabelas fechadas
select pg_temp.anonimo();
select pg_temp.falha($$select * from public.sugestoes_profissao$$, 'visitante não lê as sugestões');
select pg_temp.falha($$insert into public.sugestoes_profissao (profissao, chave, perfil) values ('x', 'x', 'cliente')$$, 'visitante não grava direto nas sugestões');
select pg_temp.falha($$select * from public.site_reclamacoes$$, 'visitante não lê as reclamações');
select pg_temp.falha($$select * from public.site_segredo$$, 'visitante não lê o segredo');
select pg_temp.falha($$select public.site_conexao()$$, 'visitante não chama o resumo da conexão');
select pg_temp.falha($$select public.admin_sugestoes_profissao(30)$$, 'visitante não vê a tela do painel');

-- ---------------------------------------------------------------- sugestões
select pg_temp.ok((public.site_sugerir_profissao('Costureira', 'cliente', 'taguatinga', null, 'visitante0001')->>'ok')::boolean, 'cliente sugere uma profissão');
select pg_temp.ok((public.site_sugerir_profissao('  costureíra ', 'profissional', 'aguas-lindas', '61 99999-0000', 'visitante0002')->>'ok')::boolean, 'profissional sugere a mesma com outra grafia');
select pg_temp.ok((public.site_sugerir_profissao('Costureira', 'cliente', 'taguatinga', null, 'visitante0001')->>'ok')::boolean, 'repetir no mesmo dia não dá erro');
select pg_temp.ok((public.site_sugerir_profissao('Eletricista', 'cliente', 'outra', null, 'visitante0003', null)->>'ja_existe')::boolean, 'avisa quando a profissão já existe');
select pg_temp.ok((public.site_sugerir_profissao('Personal trainer', 'cliente', 'regiao-que-nao-existe', null, 'visitante0004')->>'ok')::boolean, 'região desconhecida fica em branco');
select pg_temp.ok((public.site_sugerir_profissao('Robô', 'cliente', null, null, 'visitante0005', 'http://spam')->>'ok')::boolean, 'robô que preenche o campo escondido recebe "ok"');
select pg_temp.falha($$select public.site_sugerir_profissao('Veja www.spam.com', 'cliente')$$, 'link na profissão é recusado');
select pg_temp.falha($$select public.site_sugerir_profissao('<script>', 'cliente')$$, 'símbolo na profissão é recusado');
select pg_temp.falha($$select public.site_sugerir_profissao('a', 'cliente')$$, 'profissão curta demais é recusada');
select pg_temp.falha($$select public.site_sugerir_profissao('Costureira', 'chefe')$$, 'perfil inválido é recusado');
select pg_temp.falha($$select public.site_sugerir_profissao('Costureira', 'cliente', null, 'https://spam.com')$$, 'link no contato é recusado');

select pg_temp.admin();
select pg_temp.ok((select count(*) = 4 from public.sugestoes_profissao), 'guardou 4 sugestões (repetição e robô não contam)');
select pg_temp.ok((select count(distinct chave) = 1 from public.sugestoes_profissao where chave like 'costureira'), 'grafias diferentes caem na mesma chave');
select pg_temp.ok((select regiao_id is null and not outra_cidade from public.sugestoes_profissao where chave = 'personal trainer'), 'região inválida não é guardada');
select pg_temp.ok((select bool_and(conexao ~ '^[0-9a-f]{64}$') from public.sugestoes_profissao), 'guarda só o resumo da conexão, nunca o endereço');
select pg_temp.ok((select count(*) = 0 from public.sugestoes_profissao where conexao like '%200.1.1.1%'), 'endereço da conexão não aparece em lugar nenhum');

-- Limite por aparelho: 5 por dia.
select pg_temp.anonimo('200.2.2.2');
select public.site_sugerir_profissao('Profissao ' || x, 'cliente', null, null, 'aparelho00009') from unnest(array['um', 'dois', 'tres', 'quatro', 'cinco']) x;
select pg_temp.falha($$select public.site_sugerir_profissao('Profissao seis', 'cliente', null, null, 'aparelho00009')$$, 'sexta sugestão do mesmo aparelho no dia é recusada');
-- Limite por conexão: 8 por dia, mesmo trocando o código do aparelho.
select public.site_sugerir_profissao('Outra ' || x, 'cliente', null, null, 'trocado' || x || 'xx') from unnest(array['a', 'b', 'c']) x;
select pg_temp.falha($$select public.site_sugerir_profissao('Outra d', 'cliente', null, null, 'trocadodxx')$$, 'nona sugestão da mesma conexão é recusada');
select pg_temp.anonimo('200.3.3.3');
select pg_temp.ok((public.site_sugerir_profissao('Outra d', 'cliente', null, null, 'trocadodxx')->>'ok')::boolean, 'outra conexão continua podendo sugerir');

-- ---------------------------------------------------------------- painel
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select pg_temp.ok((public.admin_sugestoes_profissao(30) #>> '{ranking,0,chave}') = 'costureira', 'a mais pedida fica no topo');
select pg_temp.ok((public.admin_sugestoes_profissao(30) #>> '{ranking,0,total}')::int = 2, 'conta 2 pedidos de costureira');
select pg_temp.ok((public.admin_sugestoes_profissao(30) #>> '{ranking,0,clientes}')::int = 1
  and (public.admin_sugestoes_profissao(30) #>> '{ranking,0,profissionais}')::int = 1, 'separa clientes e profissionais');
select pg_temp.ok((select (r->>'ja_existe')::boolean from jsonb_array_elements(public.admin_sugestoes_profissao(30)->'ranking') r where r->>'chave' = 'eletricista'), 'marca a que já existe na plataforma');
select pg_temp.ok((select r->>'contato' from jsonb_array_elements(public.admin_sugestoes_profissao(30)->'recentes') r where r->>'contato' is not null limit 1) = '61 99999-0000', 'dono vê o contato inteiro');
select pg_temp.ok((public.admin_sugestoes_profissao(null)->>'total')::int >= 4, 'período "tudo" funciona');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok((public.admin_sugestoes_profissao(30)->>'total')::int > 0, 'marketing vê as sugestões');
select pg_temp.ok((select r->>'contato' from jsonb_array_elements(public.admin_sugestoes_profissao(30)->'recentes') r where r->>'contato' is not null limit 1) = '61•••00', 'marketing vê o contato mascarado');
select pg_temp.falha($$select public.admin_apagar_sugestao((select min(id) from public.sugestoes_profissao))$$, 'marketing não apaga sugestão');

select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
select pg_temp.falha($$select public.admin_sugestoes_profissao(30)$$, 'suporte não vê as sugestões');

select pg_temp.admin();
create temp table alvo as select id from public.sugestoes_profissao where chave = 'personal trainer';
grant select on alvo to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_apagar_sugestao((select id from alvo));
select pg_temp.admin();
select pg_temp.ok(not exists (select 1 from public.sugestoes_profissao where chave = 'personal trainer'), 'dono apaga uma sugestão');
select pg_temp.ok(exists (select 1 from public.admin_acoes where acao = 'apagar_sugestao_profissao'), 'apagar fica no Registro da equipe');

-- ---------------------------------------------------------------- reclamações
select pg_temp.anonimo('201.1.1.1');
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana', 'ana-sem-arroba', 'profissional', 'O profissional não apareceu no horário marcado.')$$, 'e-mail inválido é recusado');
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana', 'ana@exemplo.com', 'inventado', 'O profissional não apareceu no horário marcado.')$$, 'motivo inválido é recusado');
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana', 'ana@exemplo.com', 'profissional', 'curto')$$, 'texto curto demais é recusado');
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana', 'ana@exemplo.com', 'profissional', repeat('a', 4001))$$, 'texto longo demais é recusado');
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana', 'falso@iservice.app.br', 'profissional', 'O profissional não apareceu no horário marcado.')$$, 'e-mail do próprio iService é recusado');
select pg_temp.ok((public.site_enviar_reclamacao('Ana Paula', 'ANA@Exemplo.com ', 'profissional', 'O profissional não apareceu no horário marcado e não respondeu.',
  'cliente', '(61) 98888-7777', '1234', 'visitante0001')->>'protocolo') ~ '^S-\d{5}$', 'reclamação devolve o protocolo');
select pg_temp.ok((public.site_enviar_reclamacao('Robô', 'robo@exemplo.com', 'outro', 'Texto qualquer de robô com mais de vinte letras.', null, null, null, null, 'preenchido')->>'protocolo') is null, 'robô recebe "ok" sem abrir conversa');

select pg_temp.admin();
select pg_temp.ok((select count(*) = 1 from public.suporte_conversas where assunto = 'Reclamação pelo site: Atendimento de um profissional'), 'reclamação vira conversa na caixa de suporte');
select pg_temp.ok((select contato_email = 'ana@exemplo.com' and contato_nome = 'Ana Paula' and status = 'aberto' from public.suporte_conversas where assunto like 'Reclamação pelo site%'), 'conversa com o e-mail e o nome de quem reclamou, Em aberto');
select pg_temp.ok((select responsavel in ('dono@teste.com', 'sp@teste.com') from public.suporte_conversas where assunto like 'Reclamação pelo site%'), 'vai para alguém do rodízio (marketing não recebe e-mails)');
select pg_temp.ok((select texto like '%Telefone: (61) 98888-7777%' and texto like '%Pedido: 1234%' and texto like '%Sou: Cliente%' and texto like '%não apareceu no horário%'
  from public.suporte_mensagens m join public.suporte_conversas c on c.id = m.conversa_id where c.assunto like 'Reclamação pelo site%' and m.direcao = 'recebida'), 'mensagem traz telefone, pedido, perfil e o relato');
select pg_temp.ok((select count(*) = 1 from public.site_reclamacoes), 'robô não entra no registro');

-- Limite por e-mail: 3 por dia.
select pg_temp.anonimo('201.2.2.2');
select public.site_enviar_reclamacao('Ana Paula', 'ana@exemplo.com', 'outro', 'Mais uma reclamação com texto suficiente aqui.', null, null, null, 'aparelho' || x || 'zz') from unnest(array['1', '2']) x;
select pg_temp.falha($$select public.site_enviar_reclamacao('Ana Paula', 'ana@exemplo.com', 'outro', 'Mais uma reclamação com texto suficiente aqui.', null, null, null, 'aparelho3zz')$$, 'quarta reclamação do mesmo e-mail no dia é recusada');
-- Limite por conexão: 5 por dia.
select public.site_enviar_reclamacao('Pessoa', 'p' || x || '@exemplo.com', 'outro', 'Reclamação de outra pessoa com texto suficiente.', null, null, null, 'outro' || x || 'aparelho') from unnest(array['1', '2', '3']) x;
select pg_temp.falha($$select public.site_enviar_reclamacao('Pessoa', 'p4@exemplo.com', 'outro', 'Reclamação de outra pessoa com texto suficiente.', null, null, null, 'outro4aparelho')$$, 'sexta reclamação da mesma conexão é recusada');

rollback;
