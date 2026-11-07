-- Equipe do painel (06/11/2026): pessoas do suporte com o mesmo acesso do dono,
-- cada uma com o próprio login.
--
-- Como funciona:
--  1. Alguém da equipe convida pelo painel (aba Equipe) com nome e e-mail.
--  2. A pessoa abre iservice.app.br/admin/, toca em "Primeiro acesso" e cria a senha.
--     O Auth manda o e-mail de confirmação da marca.
--  3. Quando o e-mail é confirmado, o gatilho equipe_vincular libera o acesso
--     (perfis.e_admin = true). Se a pessoa já tinha conta iService com esse e-mail
--     confirmado, o acesso sai na hora do convite.
--  Remover alguém da equipe tira o e_admin na hora. O dono (quem já era admin quando
--  esta migração rodou) não pode ser removido, e ninguém remove a si mesmo.

-- ---------------------------------------------------------------------------
-- 1. Tabela
-- ---------------------------------------------------------------------------
create table if not exists public.equipe (
  email text primary key check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nome text not null check (length(btrim(nome)) between 2 and 80),
  papel text not null default 'suporte' check (papel in ('dono', 'suporte')),
  usuario_id uuid unique references public.perfis (id) on delete set null,
  convidado_por uuid references public.perfis (id) on delete set null,
  convidado_em timestamptz not null default now(),
  entrou_em timestamptz
);
alter table public.equipe enable row level security;
revoke all on public.equipe from anon, authenticated;
-- Leitura e escrita só pelas funções admin_* abaixo.

-- Quem já é admin hoje entra como dono.
insert into public.equipe (email, nome, papel, usuario_id, entrou_em)
select lower(u.email), coalesce(nullif(btrim(p.nome), ''), split_part(u.email, '@', 1)), 'dono', p.id, now()
from public.perfis p
join auth.users u on u.id = p.id
where p.e_admin and u.email is not null
on conflict (email) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Liberar o acesso quando a pessoa convidada confirma o e-mail
-- ---------------------------------------------------------------------------
create or replace function public.equipe_vincular()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.email is not null and new.email_confirmed_at is not null then
    update public.equipe e
       set usuario_id = new.id, entrou_em = coalesce(e.entrou_em, now())
     where e.email = lower(new.email) and (e.usuario_id is null or e.usuario_id = new.id);
    if found then
      update public.perfis set e_admin = true where id = new.id;
    end if;
  end if;
  return null;
exception when others then
  -- Nunca impedir o cadastro ou a confirmação do e-mail por causa da equipe.
  return null;
end;
$$;

-- O nome começa com "equipe" para rodar depois de ao_criar_usuario (que cria o perfil).
drop trigger if exists equipe_vincular on auth.users;
create trigger equipe_vincular after insert or update of email_confirmed_at, email on auth.users
  for each row execute function public.equipe_vincular();

-- Pessoa do suporte não recebe o e-mail de boas-vindas de cliente.
create or replace function public.boas_vindas()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null
     and exists (select 1 from public.perfis where id = new.id)
     and not exists (select 1 from public.equipe where email = lower(new.email)) then
    perform public.notificar(new.id, 'boas_vindas', 'Boas-vindas ao iService!',
      case when exists (select 1 from public.profissionais where id = new.id)
        then 'Complete seu cadastro e envie para análise para começar a receber pedidos.'
        else 'Encontre profissionais avaliados perto de você, ainda hoje.' end);
  end if;
  return null;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Funções do painel
-- ---------------------------------------------------------------------------
create or replace function public.admin_equipe()
returns table (
  email text, nome text, papel text, usuario_id uuid, foto_url text, situacao text,
  convidado_por text, convidado_em timestamptz, entrou_em timestamptz, ultimo_acesso timestamptz, voce boolean
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select e.email, coalesce(nullif(btrim(p.nome), ''), e.nome), e.papel, e.usuario_id, p.foto_url,
    case when p.e_admin then 'ativo' else 'convite_pendente' end,
    (select c.nome from public.perfis c where c.id = e.convidado_por),
    e.convidado_em, e.entrou_em, u.last_sign_in_at, e.usuario_id = auth.uid()
  from public.equipe e
  left join public.perfis p on p.id = e.usuario_id
  left join auth.users u on u.id = e.usuario_id
  order by (e.papel = 'dono') desc, (p.e_admin is true) desc, e.convidado_em;
end;
$$;

-- Devolve 'ativo' quando a conta já existia (acesso liberado na hora) ou 'convite_pendente'.
create or replace function public.admin_convidar_equipe(p_email text, p_nome text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_nome text := btrim(coalesce(p_nome, ''));
  v_usuario uuid;
begin
  perform public.exigir_admin();
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.erro('email_invalido', 'Confira o e-mail digitado.');
  end if;
  if length(v_nome) < 2 then
    perform public.erro('nome_invalido', 'Informe o nome da pessoa.');
  end if;
  if exists (select 1 from public.equipe where email = v_email) then
    perform public.erro('ja_na_equipe', 'Este e-mail já está na equipe.');
  end if;

  select u.id into v_usuario from auth.users u
  where lower(u.email) = v_email and u.email_confirmed_at is not null
    and exists (select 1 from public.perfis p where p.id = u.id)
  limit 1;

  insert into public.equipe (email, nome, papel, usuario_id, convidado_por, entrou_em)
  values (v_email, left(v_nome, 80), 'suporte', v_usuario, auth.uid(), case when v_usuario is not null then now() end);

  if v_usuario is not null then
    update public.perfis set e_admin = true where id = v_usuario;
  end if;

  perform public.registrar_acao('convidar_equipe', coalesce(v_usuario::text, v_email),
    jsonb_build_object('nome', v_nome, 'email', v_email));
  return case when v_usuario is not null then 'ativo' else 'convite_pendente' end;
end;
$$;

create or replace function public.admin_remover_equipe(p_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
begin
  perform public.exigir_admin();
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, '')));
  if v.email is null then
    perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.');
  end if;
  if v.papel = 'dono' then
    perform public.erro('dono', 'O dono do painel não pode ser removido.');
  end if;
  if v.usuario_id = auth.uid() then
    perform public.erro('voce_mesmo', 'Você não pode remover o seu próprio acesso.');
  end if;

  delete from public.equipe where email = v.email;
  if v.usuario_id is not null then
    update public.perfis set e_admin = false where id = v.usuario_id;
  end if;

  perform public.registrar_acao('remover_equipe', coalesce(v.usuario_id::text, v.email),
    jsonb_build_object('nome', v.nome, 'email', v.email));
end;
$$;

revoke all on function public.equipe_vincular() from public, anon, authenticated;
revoke all on function public.admin_equipe() from public, anon;
revoke all on function public.admin_convidar_equipe(text, text) from public, anon;
revoke all on function public.admin_remover_equipe(text) from public, anon;
grant execute on function public.admin_equipe() to authenticated;
grant execute on function public.admin_convidar_equipe(text, text) to authenticated;
grant execute on function public.admin_remover_equipe(text) to authenticated;
