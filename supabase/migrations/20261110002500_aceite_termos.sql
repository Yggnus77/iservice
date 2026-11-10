-- Aceite dos Termos de Uso e da Política de Privacidade (10/11/2026)
--
-- Cada conta guarda quando aceitou e qual versão (a data de "Última atualização"
-- das páginas termos.html e privacidade.html). É a prova do consentimento (LGPD)
-- e permite pedir um novo aceite quando os textos mudarem.
--  - Cadastro por e-mail: a caixinha da tela manda a versão junto com a conta
--    (metadado "termos") e o gatilho abaixo grava na hora.
--  - Login com Google, contas antigas e Termos novos: o app mostra a tela de
--    aceite e chama aceitar_termos().

alter table public.perfis add column if not exists termos_aceitos_em timestamptz;
alter table public.perfis add column if not exists termos_versao text;

alter table public.perfis drop constraint if exists perfis_termos_versao;
alter table public.perfis add constraint perfis_termos_versao
  check (termos_versao is null or termos_versao ~ '^\d{4}-\d{2}-\d{2}$');

-- Aceite feito pelo app (tela "Antes de continuar").
create or replace function public.aceitar_termos(p_versao text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if p_versao is null or p_versao !~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.erro('versao_invalida', 'Atualize o app para aceitar os Termos.');
  end if;
  update public.perfis set termos_aceitos_em = now(), termos_versao = p_versao where id = auth.uid();
end;
$$;
revoke all on function public.aceitar_termos(text) from public, anon;
grant execute on function public.aceitar_termos(text) to authenticated;

-- Aceite marcado na tela de cadastro por e-mail. O nome começa com "termos" para
-- rodar depois de ao_criar_usuario, que cria o perfil.
create or replace function public.termos_no_cadastro()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v text := new.raw_user_meta_data ->> 'termos';
begin
  if v ~ '^\d{4}-\d{2}-\d{2}$' then
    update public.perfis set termos_aceitos_em = coalesce(new.created_at, now()), termos_versao = v where id = new.id;
  end if;
  return null;
exception when others then
  -- Nunca impedir o cadastro por causa disto; o app pede o aceite depois.
  return null;
end;
$$;
revoke all on function public.termos_no_cadastro() from public, anon, authenticated;

drop trigger if exists termos_no_cadastro on auth.users;
create trigger termos_no_cadastro after insert on auth.users
  for each row execute function public.termos_no_cadastro();
