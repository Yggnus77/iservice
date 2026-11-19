-- Dados de acesso da equipe (19/11/2026)
--
-- Na aba Equipe, o dono (e quem tem cargo acima da pessoa, como o Gerente geral)
-- vê e corrige nome e e-mail de cada um e define uma senha nova. A própria
-- pessoa também corrige os seus dados.
--
-- A senha nunca é mostrada: o Supabase guarda só a versão criptografada (bcrypt),
-- que nem o dono consegue ler. Dá para definir uma nova ou mandar o link
-- "criar nova senha" para o e-mail da pessoa.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. Trocar o e-mail de alguém da equipe leva junto as conversas do suporte
-- ---------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select c.conname into v_nome
  from pg_constraint c
  where c.conrelid = 'public.suporte_conversas'::regclass and c.contype = 'f'
    and c.confrelid = 'public.equipe'::regclass
  limit 1;
  if v_nome is not null then
    execute format('alter table public.suporte_conversas drop constraint %I', v_nome);
  end if;
  alter table public.suporte_conversas add constraint suporte_conversas_responsavel_fkey
    foreign key (responsavel) references public.equipe (email) on update cascade on delete set null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Quem pode editar os dados de um membro: ele mesmo ou quem tem cargo acima
-- ---------------------------------------------------------------------------
create or replace function public.pode_editar_membro(p_membro public.equipe)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.e_admin()
    and (p_membro.usuario_id = auth.uid() or (public.pode('equipe') and public.pode_gerir_cargo(p_membro.papel)))
$$;
revoke all on function public.pode_editar_membro(public.equipe) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Lista da equipe: agora diz também se dá para editar e se a conta já existe
-- ---------------------------------------------------------------------------
drop function if exists public.admin_equipe();
create function public.admin_equipe()
returns table (
  email text, nome text, papel text, cargo_nome text, usuario_id uuid, foto_url text, situacao text,
  convidado_por text, convidado_em timestamptz, entrou_em timestamptz, ultimo_acesso timestamptz, voce boolean,
  pode_gerir boolean, pode_foto boolean, recebe_emails boolean,
  pode_editar boolean, email_login text, senha_alterada_em timestamptz, telefone text
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('equipe');
  return query
  select e.email, coalesce(nullif(btrim(p.nome), ''), e.nome), e.papel, public.cargo_nome(e.papel), e.usuario_id, p.foto_url,
    case when p.e_admin then 'ativo' else 'convite_pendente' end,
    (select c.nome from public.perfis c where c.id = e.convidado_por),
    e.convidado_em, e.entrou_em, u.last_sign_in_at, e.usuario_id = auth.uid(),
    e.usuario_id is distinct from auth.uid() and public.pode_gerir_cargo(e.papel),
    e.usuario_id is not null and public.pode_trocar_foto_equipe(e.usuario_id::text),
    e.recebe_emails,
    public.pode_editar_membro(e),
    u.email::text,
    -- Última troca de senha que a equipe registrou (pelo painel).
    (select max(a.criada_em) from public.admin_acoes a where a.acao = 'senha_equipe' and a.alvo = e.usuario_id::text),
    case when public.pode_editar_membro(e) then p.telefone end
  from public.equipe e
  left join public.perfis p on p.id = e.usuario_id
  left join auth.users u on u.id = e.usuario_id
  where e.usuario_id = auth.uid() or public.ve_membro(e.papel)
  order by public.cargo_nivel(e.papel) desc, (p.e_admin is true) desc, e.convidado_em;
end;
$$;
revoke all on function public.admin_equipe() from public, anon;
grant execute on function public.admin_equipe() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Corrigir nome e e-mail
-- ---------------------------------------------------------------------------
create or replace function public.admin_editar_membro(p_email text, p_nome text, p_novo_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_email text := lower(btrim(coalesce(p_novo_email, '')));
begin
  perform public.exigir_admin();
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, ''))) for update;
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  if not public.pode_editar_membro(v) then
    perform public.erro('sem_permissao', 'Só a própria pessoa ou quem tem cargo acima dela muda estes dados.');
  end if;
  if char_length(v_nome) < 2 or char_length(v_nome) > 80 then
    perform public.erro('nome_invalido', 'O nome precisa ter de 2 a 80 letras.');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.erro('email_invalido', 'Confira o e-mail digitado.');
  end if;
  if v_email <> v.email then
    if exists (select 1 from public.equipe where email = v_email) then
      perform public.erro('ja_na_equipe', 'Este e-mail já é de outra pessoa da equipe.');
    end if;
    if exists (select 1 from auth.users where lower(email) = v_email and id is distinct from v.usuario_id) then
      perform public.erro('email_em_uso', 'Já existe outra conta iService com este e-mail.');
    end if;
  end if;

  update public.equipe set nome = v_nome, email = v_email where email = v.email;

  if v.usuario_id is not null then
    -- O nome que aparece no painel e no app vem do perfil.
    update public.perfis set nome = v_nome where id = v.usuario_id and nome is distinct from v_nome;
    if v_email <> v.email then
      update public.perfis set email = v_email where id = v.usuario_id;
      -- O login passa a ser o e-mail novo (a senha continua a mesma).
      update auth.users set email = v_email, email_change = '', email_change_token_new = '', email_change_token_current = '',
        updated_at = now()
      where id = v.usuario_id;
      update auth.identities set identity_data = coalesce(identity_data, '{}'::jsonb) || jsonb_build_object('email', v_email),
        updated_at = now()
      where user_id = v.usuario_id and provider = 'email';
    end if;
  end if;

  perform public.registrar_acao('editar_equipe', coalesce(v.usuario_id::text, v_email),
    jsonb_build_object('nome_antes', v.nome, 'nome', v_nome, 'email_antes', v.email, 'email', v_email));
end;
$$;
revoke all on function public.admin_editar_membro(text, text, text) from public, anon;
grant execute on function public.admin_editar_membro(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Definir uma senha nova (nunca dá para ler a atual)
-- ---------------------------------------------------------------------------
create or replace function public.admin_definir_senha_membro(p_email text, p_senha text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v public.equipe;
  v_senha text := coalesce(p_senha, '');
begin
  perform public.exigir_admin();
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, '')));
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  if not public.pode_editar_membro(v) then
    perform public.erro('sem_permissao', 'Só a própria pessoa ou quem tem cargo acima dela define a senha.');
  end if;
  if v.usuario_id is null or not exists (select 1 from auth.users where id = v.usuario_id) then
    perform public.erro('sem_conta', 'Esta pessoa ainda não criou a conta. Mande as instruções do primeiro acesso.');
  end if;
  if char_length(v_senha) < 8 or char_length(v_senha) > 72 or v_senha !~ '[A-Za-z]' or v_senha !~ '[0-9]' then
    perform public.erro('senha_fraca', 'A senha precisa ter de 8 a 72 caracteres, com letras e números.');
  end if;

  update auth.users set encrypted_password = extensions.crypt(v_senha, extensions.gen_salt('bf', 10)), updated_at = now()
  where id = v.usuario_id;
  -- Senha de outra pessoa: as sessões abertas dela terminam e ela entra com a senha nova.
  if v.usuario_id <> auth.uid() then
    begin
      delete from auth.sessions where user_id = v.usuario_id;
      delete from auth.refresh_tokens where user_id = v.usuario_id::text;
    exception when others then null;
    end;
  end if;
  -- Registra só que a senha mudou, nunca a senha.
  perform public.registrar_acao('senha_equipe', v.usuario_id::text, jsonb_build_object('nome', v.nome, 'email', v.email));
end;
$$;
revoke all on function public.admin_definir_senha_membro(text, text) from public, anon;
grant execute on function public.admin_definir_senha_membro(text, text) to authenticated;

-- Dono sem nome no perfil: usa o nome da equipe (o e-mail antes do @ era o padrão).
update public.equipe e set nome = btrim(p.nome)
from public.perfis p
where p.id = e.usuario_id and char_length(btrim(coalesce(p.nome, ''))) >= 2 and e.nome <> btrim(p.nome);
