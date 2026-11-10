-- Testes do aceite dos Termos (migração 20261110002500). Transação desfeita no fim.
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

grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000c1', 'email@teste.com', '{"nome":"Cadastro por E-mail","app":"cliente","termos":"2026-10-27"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'google@teste.com', '{"nome":"Entrou com Google","app":"profissional"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'esperto@teste.com', '{"nome":"Versão Esquisita","app":"cliente","termos":"qualquer coisa"}');

select pg_temp.ok((select termos_versao = '2026-10-27' and termos_aceitos_em is not null from public.perfis
  where id = '00000000-0000-0000-0000-0000000000c1'), 'cadastro por e-mail grava o aceite marcado na tela');
select pg_temp.ok((select termos_versao is null and termos_aceitos_em is null from public.perfis
  where id = '00000000-0000-0000-0000-0000000000c2'), 'quem entrou com Google ainda não aceitou');
select pg_temp.ok((select termos_versao is null from public.perfis where id = '00000000-0000-0000-0000-0000000000c3')
  and exists (select 1 from public.profissionais where id = '00000000-0000-0000-0000-0000000000c2'),
  'versão inválida é ignorada sem travar o cadastro');

select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select public.aceitar_termos('2026-10-27');
select pg_temp.ok((public.meu_perfil() -> 'perfil' ->> 'termos_versao') = '2026-10-27', 'aceite pelo app aparece no perfil');
do $$ begin
  perform public.aceitar_termos('<script>');
  raise exception 'FALHOU: aceitou versão inválida';
exception when others then if sqlerrm like 'FALHOU%' then raise; end if; raise notice 'ok - versão inválida é recusada';
end $$;
do $$ begin
  update public.perfis set termos_versao = '2099-01-01' where id = auth.uid();
  raise exception 'FALHOU: editou o aceite direto';
exception when insufficient_privilege then raise notice 'ok - aceite só muda pela função';
end $$;

reset role;
set local role anon;
do $$ begin
  perform public.aceitar_termos('2026-10-27');
  raise exception 'FALHOU: visitante aceitou';
exception when insufficient_privilege then raise notice 'ok - visitante sem conta não chama a função';
end $$;
reset role;

rollback;
