-- Testes da auditoria de segurança de 10/11/2026 (migração 20261110002400).
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

-- Espera erro: roda o comando e confere que falhou.
create function pg_temp.falha(cmd text, nome text) returns void language plpgsql as $$
begin
  execute cmd;
  raise exception 'FALHOU: %', nome;
exception when others then
  if sqlerrm like 'FALHOU%' then raise; end if;
  raise notice 'ok - %', nome;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- d1 = dono do painel, s1 = suporte, c1 = cliente, p1 = profissional
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'dono@teste.com', now(), '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000e1', 'suporte@teste.com', now(), '{"nome":"Suporte iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'cliente@teste.com', now(), '{"nome":"Marina Alves","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'pro@teste.com', now(), '{"nome":"Carlos Silva","app":"profissional"}');

update public.perfis set e_admin = true where id in ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000e1');
insert into public.equipe (email, nome, papel, usuario_id) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000d1'),
  ('suporte@teste.com', 'Suporte iService', 'suporte', '00000000-0000-0000-0000-0000000000e1')
on conflict (email) do update set papel = excluded.papel, usuario_id = excluded.usuario_id;

-- ------------------------------------------------------------ permissões
select pg_temp.ok(not has_table_privilege('anon', 'public.posicoes_pedido', 'select')
  and not has_table_privilege('authenticated', 'public.posicoes_pedido', 'insert')
  and not has_table_privilege('authenticated', 'public.posicoes_pedido', 'update')
  and not has_table_privilege('authenticated', 'public.posicoes_pedido', 'delete')
  and has_table_privilege('authenticated', 'public.posicoes_pedido', 'select'),
  'mapa ao vivo é só leitura pela API');

select pg_temp.ok(has_column_privilege('authenticated', 'public.mensagens', 'texto', 'insert')
  and not has_column_privilege('authenticated', 'public.mensagens', 'criada_em', 'insert')
  and not has_column_privilege('authenticated', 'public.mensagens', 'lida_em', 'insert'),
  'mensagem não aceita data inventada');

select pg_temp.ok(has_column_privilege('authenticated', 'public.documentos', 'arquivo_path', 'insert')
  and not has_column_privilege('authenticated', 'public.documentos', 'revisado_por', 'insert')
  and not has_column_privilege('authenticated', 'public.documentos', 'status', 'insert'),
  'documento não chega já revisado');

select pg_temp.ok(not has_column_privilege('authenticated', 'public.certificacoes', 'criado_em', 'insert')
  and not has_column_privilege('authenticated', 'public.certificacoes', 'status', 'insert'),
  'certificação não chega com data ou status inventados');

select pg_temp.ok(not has_function_privilege('anon', 'public.notificacao_push()', 'execute')
  and not has_function_privilege('authenticated', 'public.apagar_posicao()', 'execute')
  and not has_function_privilege('anon', 'public.admin_site(integer)', 'execute'),
  'funções de gatilho e do painel fora da API para visitantes');

-- ------------------------------------------------------- arquivos do dono
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
insert into public.documentos (profissional_id, tipo, arquivo_path)
values (auth.uid(), 'documento_frente', auth.uid() || '/documento_frente-1.jpg');
select pg_temp.ok(true, 'profissional envia documento da própria pasta');
select pg_temp.falha($$insert into public.documentos (profissional_id, tipo, arquivo_path)
  values (auth.uid(), 'documento_frente', '00000000-0000-0000-0000-0000000000c1/rg.jpg')$$,
  'documento não pode apontar para o arquivo de outra pessoa');
select pg_temp.falha($$insert into public.documentos (profissional_id, tipo, arquivo_path)
  values (auth.uid(), 'selfie_documento', auth.uid() || '/../00000000-0000-0000-0000-0000000000c1/rg.jpg')$$,
  'caminho com .. é recusado');
select pg_temp.falha($$insert into public.portfolio (profissional_id, depois_path)
  values (auth.uid(), '00000000-0000-0000-0000-0000000000c1/foto.jpg')$$,
  'portfólio não usa foto de outra pessoa');
select pg_temp.falha($$insert into public.certificacoes (profissional_id, nome, arquivo_path)
  values (auth.uid(), 'NR-10', '00000000-0000-0000-0000-0000000000c1/x.pdf')$$,
  'certificação não usa arquivo de outra pessoa');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
update public.perfis set foto_url = 'https://aurjqwqqrxaexmwozezr.supabase.co/storage/v1/object/public/fotos/' || auth.uid() || '/perfil-1.jpg'
where id = auth.uid();
select pg_temp.ok(true, 'foto de perfil do Storage do iService é aceita');
select pg_temp.falha($$update public.perfis set foto_url = 'https://outro-projeto.supabase.co/storage/v1/object/public/fotos/' || auth.uid() || '/x.gif'
  where id = auth.uid()$$, 'foto de perfil de outro projeto Supabase é recusada');
select pg_temp.ok(public.arquivos_do_usuario(array[
    'https://aurjqwqqrxaexmwozezr.supabase.co/storage/v1/object/public/avaliacoes/00000000-0000-0000-0000-0000000000c1/p/1.jpg'],
    'avaliacoes', '00000000-0000-0000-0000-0000000000c1')
  and not public.arquivos_do_usuario(array['https://exemplo.com/rastreio.gif'], 'avaliacoes', '00000000-0000-0000-0000-0000000000c1')
  and not public.arquivos_do_usuario(array_fill('00000000-0000-0000-0000-0000000000c1/a.jpg'::text, array[11]), 'avaliacoes',
    '00000000-0000-0000-0000-0000000000c1'),
  'fotos de avaliação só do Storage, da pasta do cliente e no máximo 10');

-- ---------------------------------------------------------------- Storage
select pg_temp.admin();
insert into storage.objects (bucket_id, name) values
  ('documentos', '00000000-0000-0000-0000-0000000000a1/documento_frente-1.jpg'),
  ('fotos', '00000000-0000-0000-0000-0000000000a1/perfil-1.jpg');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
with x as (update storage.objects set name = name where bucket_id = 'documentos' returning 1)
select pg_temp.ok((select count(*) from x) = 0, 'documento enviado não pode ser sobrescrito');
with x as (delete from storage.objects where bucket_id = 'documentos' returning 1)
select pg_temp.ok((select count(*) from x) = 0, 'documento enviado não pode ser apagado pelo usuário');
with x as (update storage.objects set name = name where bucket_id = 'fotos' returning 1)
select pg_temp.ok((select count(*) from x) = 1, 'foto de perfil continua podendo ser trocada');

-- ------------------------------------------------- dados verificados
select pg_temp.admin();
update public.profissionais set status = 'aprovado' where id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select pg_temp.falha($$update public.perfis set nome = 'Outra Pessoa' where id = auth.uid()$$,
  'profissional aprovado não troca o nome sozinho');
select pg_temp.falha($$update public.perfis set nascimento = '1970-01-01' where id = auth.uid()$$,
  'profissional aprovado não troca a data de nascimento sozinho');
update public.perfis set telefone = '61981234567', letra_grande = true where id = auth.uid();
select pg_temp.ok(true, 'profissional aprovado ainda edita telefone e preferências');
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
update public.perfis set nome = 'Marina A. Alves' where id = auth.uid();
select pg_temp.ok((select nome from public.perfis where id = auth.uid()) = 'Marina A. Alves', 'cliente edita o próprio nome');
select pg_temp.admin();
update public.profissionais set status = 'recusado' where id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
update public.perfis set nome = 'Carlos Silva Junior' where id = auth.uid();
select pg_temp.ok(true, 'cadastro recusado pode corrigir o nome e reenviar');

-- ---------------------------------------------------------------- equipe
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
select pg_temp.falha($$select public.admin_suspender('00000000-0000-0000-0000-0000000000d1', true, 'tentativa')$$,
  'suporte não consegue suspender o dono');
select public.admin_suspender('00000000-0000-0000-0000-0000000000c1', true, 'teste');
select pg_temp.admin();
select pg_temp.ok((select suspenso_em is not null from public.perfis where id = '00000000-0000-0000-0000-0000000000c1'),
  'suporte ainda suspende clientes');

rollback;
