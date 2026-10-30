-- As Edge Functions passam a ser chamadas com uma senha interna gerada pelo
-- próprio banco (Vault), em vez da chave service_role copiada à mão.
-- Assim ninguém precisa copiar chave, e trocar as chaves do Supabase não quebra nada.

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'iservice_segredo_funcoes') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'iservice_segredo_funcoes');
  end if;
end;
$$;

-- A antiga chave copiada não é mais usada.
delete from vault.secrets where name = 'iservice_chave_servico';

-- Só as Edge Functions (service_role) leem a senha, para conferir quem chama.
create or replace function public.segredo_funcoes()
returns text
language sql stable security definer
set search_path = public
as $$ select decrypted_secret from vault.decrypted_secrets where name = 'iservice_segredo_funcoes' $$;

revoke all on function public.segredo_funcoes() from public, anon, authenticated;
grant execute on function public.segredo_funcoes() to service_role;

create or replace function public.chamar_funcao(p_nome text, p_corpo jsonb default '{}')
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_url text;
  v_segredo text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'iservice_url';
  select decrypted_secret into v_segredo from vault.decrypted_secrets where name = 'iservice_segredo_funcoes';
  if v_url is null or v_segredo is null then return; end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || p_nome,
    body := p_corpo,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-iservice-segredo', v_segredo),
    timeout_milliseconds := 10000
  );
exception when others then
  -- Sem Vault ou sem pg_net (banco de testes) ou falha de rede: o app segue normal.
  null;
end;
$$;

revoke all on function public.chamar_funcao(text, jsonb) from public, anon, authenticated;
