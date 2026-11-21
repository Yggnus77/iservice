-- Testes do assistente do chat do suporte (migração 20261121005000).
-- Rodam numa transação desfeita no fim.
begin;

create function pg_temp.como(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.servico() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
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

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000ad', 'dono@teste.com', '{"nome":"Dono iService","app":"cliente"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'marina@cliente.com', '{"nome":"Marina Alves","app":"cliente"}');
update public.perfis set e_admin = true where id = '00000000-0000-0000-0000-0000000000ad';
insert into public.equipe (email, nome, papel, usuario_id, convidado_em, entrou_em) values
  ('dono@teste.com', 'Dono iService', 'dono', '00000000-0000-0000-0000-0000000000ad', now(), now());

select pg_temp.ok((select count(*) from public.ajuda_perguntas where palavras = '') = 0, 'todas as perguntas vêm com outros jeitos de perguntar');
select pg_temp.ok(exists (select 1 from public.ajuda_perguntas where pergunta = 'Como cancelo um pedido?'), 'perguntas novas entraram');
select pg_temp.ok((select resposta like 'Pelo chat aqui no app%' from public.ajuda_perguntas where pergunta = 'Como falo com o suporte do iService?'), 'resposta do suporte cita o chat');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok((select count(*) from public.ajuda_perguntas where palavras <> '') > 0, 'app lê as palavras');
select pg_temp.falha($$select public.admin_palavras_pergunta(1, 'x')$$, 'cliente não edita as palavras');

select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.admin_palavras_pergunta((select id from public.ajuda_perguntas where pergunta = 'Como cancelo um pedido?'), '  cancelar,   desistir  ');
select pg_temp.ok((select palavras = 'cancelar, desistir' from public.ajuda_perguntas where pergunta = 'Como cancelo um pedido?'), 'equipe salva as palavras, sem espaços sobrando');
select pg_temp.falha($$select public.admin_palavras_pergunta(-1, 'x')$$, 'pergunta inexistente dá erro');

rollback;
