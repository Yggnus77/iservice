-- Testes da política de verificação (migração 20261120004200).
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


-- d = dono (equipe), p = profissional de fretes (rascunho), q = profissional aprovado
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000070d1', 'vdono@teste.com', now(), '{"nome":"Dono Verif","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000070a1', 'vfrete@teste.com', now(), '{"nome":"Fábio Frete","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000070a2', 'vapr@teste.com', now(), '{"nome":"Ana Aprovada","app":"profissional"}');
update public.perfis set email_verificado = true where not email_verificado;
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000070d1';
insert into public.equipe (email, nome, papel, usuario_id) values ('vdono@teste.com', 'Dono Verif', 'dono', '00000000-0000-0000-0000-0000000070d1')
on conflict (email) do update set papel = excluded.papel, usuario_id = excluded.usuario_id;
insert into public.profissional_profissoes values ('00000000-0000-0000-0000-0000000070a1', 'fretes', true), ('00000000-0000-0000-0000-0000000070a2', 'eletricista', true);

-- ---------------------------------------------------------------- exigências
select pg_temp.ok((select bool_and(exige_antecedentes) from public.profissoes), 'todas as profissões exigem antecedentes');
select pg_temp.ok((select documentos_extras from public.profissoes where id = 'fretes') = array['cnh', 'documento_veiculo'], 'Fretes pede CNH e documento do veículo');
select pg_temp.ok((select documentos_extras from public.profissoes where id = 'dedetizador') = array['vinculo_empresa'], 'Dedetizador pede vínculo com empresa');
select pg_temp.ok(public.pendencias_profissional('00000000-0000-0000-0000-0000000070a1') @> array['antecedentes', 'antecedentes_estadual', 'cnh', 'documento_veiculo'],
  'pendências do Fretes incluem as duas certidões, CNH e documento do veículo');
select pg_temp.ok(not public.pendencias_profissional('00000000-0000-0000-0000-0000000070a2') && array['cnh', 'documento_veiculo', 'vinculo_empresa'],
  'eletricista não precisa dos documentos extras');
insert into public.documentos (profissional_id, tipo, arquivo_path) values
  ('00000000-0000-0000-0000-0000000070a1', 'cnh', '00000000-0000-0000-0000-0000000070a1/cnh.jpg');
select pg_temp.ok(not 'cnh' = any (public.pendencias_profissional('00000000-0000-0000-0000-0000000070a1')), 'CNH enviada sai das pendências');
select pg_temp.falha($$update public.profissoes set documentos_extras = array['qualquer'] where id = 'fretes'$$, 'só aceita tipos de documento conhecidos');

-- ---------------------------------------------------------------- validade
insert into public.documentos (profissional_id, tipo, arquivo_path, status, revisado_em, valido_ate)
select '00000000-0000-0000-0000-0000000070a2', t, '00000000-0000-0000-0000-0000000070a2/' || t, 'aprovado', now(), current_date + 100
from unnest(array['documento_frente', 'selfie_documento', 'antecedentes', 'antecedentes_estadual']::public.tipo_documento[]) t;
select pg_temp.ok(not 'antecedentes_estadual' = any (public.pendencias_profissional('00000000-0000-0000-0000-0000000070a2')), 'certidão dentro da validade conta');
update public.documentos set valido_ate = current_date - 2 where profissional_id = '00000000-0000-0000-0000-0000000070a2' and tipo::text = 'antecedentes_estadual';
select pg_temp.ok('antecedentes_estadual' = any (public.pendencias_profissional('00000000-0000-0000-0000-0000000070a2')), 'certidão vencida volta a ser pendência');
insert into public.documentos (profissional_id, tipo, arquivo_path) values
  ('00000000-0000-0000-0000-0000000070a1', 'documento_veiculo', '00000000-0000-0000-0000-0000000070a1/crlv.jpg');
select set_config('t.crlv', (select id::text from public.documentos where profissional_id = '00000000-0000-0000-0000-0000000070a1' and tipo::text = 'documento_veiculo'), true);
select pg_temp.como('00000000-0000-0000-0000-0000000070d1');
select public.admin_revisar_documento(current_setting('t.crlv')::bigint, true);
select pg_temp.admin();
select pg_temp.ok((select valido_ate = (now() at time zone 'America/Sao_Paulo')::date + 730 from public.documentos where id = current_setting('t.crlv')::bigint),
  'documento do veículo aprovado vale 24 meses');

-- ---------------------------------------------------------------- fila com a data de envio
update public.profissionais set status = 'em_analise' where id = '00000000-0000-0000-0000-0000000070a1';
select pg_temp.como('00000000-0000-0000-0000-0000000070d1');
select pg_temp.ok((select enviado_em > now() - interval '1 minute' from public.admin_cadastros() where id = '00000000-0000-0000-0000-0000000070a1'),
  'fila mostra quando o cadastro foi enviado');
select pg_temp.falha($$select public.admin_revisar_documento(current_setting('t.crlv')::bigint, false, '')$$, 'recusar pede o motivo');

-- ---------------------------------------------------------------- 3ª advertência
select pg_temp.ok(public.admin_advertir('00000000-0000-0000-0000-0000000070a2', 'Atraso sem avisar') = 1, '1ª advertência');
select pg_temp.ok(public.admin_advertir('00000000-0000-0000-0000-0000000070a2', 'Atraso sem avisar') = 2, '2ª advertência');
select pg_temp.admin();
select pg_temp.ok((select suspenso_em is null from public.perfis where id = '00000000-0000-0000-0000-0000000070a2'), 'duas advertências não suspendem');
select pg_temp.como('00000000-0000-0000-0000-0000000070d1');
select public.admin_advertir('00000000-0000-0000-0000-0000000070a2', 'Tentou levar o cliente para fora da plataforma');
select pg_temp.admin();
select pg_temp.ok((select suspenso_em is not null and suspenso_ate::date = ((now() + interval '30 days') at time zone 'America/Sao_Paulo')::date
  or suspenso_ate between now() + interval '29 days' and now() + interval '31 days' from public.perfis where id = '00000000-0000-0000-0000-0000000070a2'),
  'a 3ª advertência suspende por 30 dias');

-- ---------------------------------------------------------------- certidões apagadas em 90 dias
insert into public.documentos (profissional_id, tipo, arquivo_path, status, revisado_em) values
  ('00000000-0000-0000-0000-0000000070a1', 'antecedentes', '00000000-0000-0000-0000-0000000070a1/antigo.pdf', 'aprovado', now() - interval '91 days'),
  ('00000000-0000-0000-0000-0000000070a1', 'antecedentes_estadual', '00000000-0000-0000-0000-0000000070a1/recente.pdf', 'aprovado', now() - interval '10 days');
select pg_temp.ok((select count(*) from public.certidoes_para_apagar() where arquivo_path like '%/antigo.pdf') = 1
  and (select count(*) from public.certidoes_para_apagar() where arquivo_path like '%/recente.pdf') = 0, 'só a certidão decidida há mais de 90 dias entra na lista');
select public.marcar_certidao_apagada(array(select id from public.certidoes_para_apagar()));
select pg_temp.ok(not exists (select 1 from public.certidoes_para_apagar()), 'depois de apagada, sai da lista');
select pg_temp.como('00000000-0000-0000-0000-0000000070d1');
select pg_temp.ok(exists (select 1 from jsonb_array_elements(public.admin_usuario('00000000-0000-0000-0000-0000000070a1') -> 'profissional' -> 'documentos') d
  where d ->> 'arquivo_apagado_em' is not null), 'a ficha mostra que o arquivo foi apagado');
select pg_temp.como('00000000-0000-0000-0000-0000000070a1');
do $$ begin
  perform public.certidoes_para_apagar();
  raise exception 'FALHOU: profissional viu a lista de certidões';
exception when insufficient_privilege then raise notice 'ok - profissional não vê a lista de certidões';
end $$;

-- ---------------------------------------------------------------- revisão pela nota
select pg_temp.admin();
update public.perfis set suspenso_em = null, suspenso_ate = null where id = '00000000-0000-0000-0000-0000000070a2';
update public.profissionais set status = 'aprovado', nota_media = 3.2, total_avaliacoes = 12 where id = '00000000-0000-0000-0000-0000000070a2';
select pg_temp.ok(exists (select 1 from public.alertas_profissionais_lista('00000000-0000-0000-0000-0000000070a2') x, jsonb_array_elements(x -> 'motivos') m
  where m ->> 'codigo' = 'nota_geral'), 'nota geral abaixo de 3,5 com 10+ avaliações pede revisão');

rollback;
