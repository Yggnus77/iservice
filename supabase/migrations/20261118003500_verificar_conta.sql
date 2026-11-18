-- Verificação da conta no cadastro: a pessoa escolhe receber o código por
-- e-mail ou por SMS e só usa a plataforma depois de digitar o código.
--
-- Para quem escolhe SMS conseguir entrar, o "Confirm email" do Supabase fica
-- desligado; com isso auth.users.email_confirmed_at deixa de provar alguma coisa
-- (o Supabase preenche na hora do cadastro). A prova passa a ser do iService:
--   perfis.email_verificado     código do e-mail (ou Google, ou link do Supabase)
--   perfis.telefone_verificado  código do SMS (já existia)
--   perfis.verificado_em        primeira vez que a conta ficou verificada
-- A equipe do painel e as boas-vindas passam a depender disso.

-- ---------------------------------------------------------------------------
-- 1. Colunas (o usuário não consegue marcar sozinho: o update de perfis é por coluna)
-- ---------------------------------------------------------------------------
alter table public.perfis add column if not exists email_verificado boolean not null default false;
alter table public.perfis add column if not exists verificado_em timestamptz;

-- Contas de hoje: o "Confirm email" estava ligado, então e-mail confirmado é e-mail verificado.
update public.perfis p
   set email_verificado = true
  from auth.users u
 where u.id = p.id and u.email_confirmed_at is not null and not p.email_verificado;
update public.perfis
   set verificado_em = coalesce(criado_em, now())
 where verificado_em is null and (email_verificado or telefone_verificado);

create or replace function public.conta_verificada(p_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$ select coalesce((select email_verificado or telefone_verificado from public.perfis where id = p_id), false) $$;
revoke all on function public.conta_verificada(uuid) from public, anon;
grant execute on function public.conta_verificada(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Código por e-mail
-- ---------------------------------------------------------------------------
-- Só o resumo (hash) do código fica guardado; o código vai direto para a função
-- de e-mail. Ninguém lê esta tabela pelo app.
create table if not exists public.codigos_email (
  usuario_id uuid primary key references public.perfis (id) on delete cascade,
  codigo_hash text not null,
  email text not null,
  expira_em timestamptz not null,
  tentativas smallint not null default 0,
  enviado_em timestamptz not null default now(),
  envios_na_hora smallint not null default 1,
  hora_inicio timestamptz not null default now()
);
alter table public.codigos_email enable row level security;
revoke all on public.codigos_email from anon, authenticated;

create or replace function public.resumo_codigo(p_usuario uuid, p_codigo text)
returns text
language sql immutable
set search_path = public, extensions
as $$ select encode(extensions.digest(p_usuario::text || ':' || p_codigo, 'sha256'), 'hex') $$;
revoke all on function public.resumo_codigo(uuid, text) from public, anon, authenticated;

-- Manda um código de 6 números para o e-mail da conta. Devolve o e-mail usado.
create or replace function public.pedir_codigo_email()
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := auth.uid();
  v_email text;
  v_verificado boolean;
  v_codigo text;
  v_ant public.codigos_email%rowtype;
  v_envios smallint := 1;
  v_hora timestamptz := now();
begin
  if v_id is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  select u.email into v_email from auth.users u where u.id = v_id;
  select email_verificado into v_verificado from public.perfis where id = v_id;
  if coalesce(v_email, '') = '' then perform public.erro('sem_email', 'Sua conta não tem e-mail. Verifique pelo SMS.'); end if;
  if v_verificado then perform public.erro('ja_verificado', 'Seu e-mail já está confirmado.'); end if;

  select * into v_ant from public.codigos_email where usuario_id = v_id for update;
  if found then
    if v_ant.enviado_em > now() - interval '60 seconds' then
      perform public.erro('aguarde', 'Espere um minuto para pedir outro código.');
    end if;
    if v_ant.hora_inicio > now() - interval '1 hour' then
      if v_ant.envios_na_hora >= 5 then
        perform public.erro('muitas_tentativas', 'Você pediu muitos códigos. Tente de novo daqui a uma hora ou verifique pelo SMS.');
      end if;
      v_envios := v_ant.envios_na_hora + 1;
      v_hora := v_ant.hora_inicio;
    end if;
  end if;

  v_codigo := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');

  insert into public.codigos_email (usuario_id, codigo_hash, email, expira_em, tentativas, enviado_em, envios_na_hora, hora_inicio)
  values (v_id, public.resumo_codigo(v_id, v_codigo), lower(v_email), now() + interval '15 minutes', 0, now(), v_envios, v_hora)
  on conflict (usuario_id) do update set
    codigo_hash = excluded.codigo_hash, email = excluded.email, expira_em = excluded.expira_em,
    tentativas = 0, enviado_em = excluded.enviado_em, envios_na_hora = excluded.envios_na_hora,
    hora_inicio = excluded.hora_inicio;

  perform public.chamar_funcao('enviar-email',
    jsonb_build_object('verificacao', jsonb_build_object('usuario_id', v_id, 'email', v_email, 'codigo', v_codigo)));
  return v_email;
end;
$$;
revoke all on function public.pedir_codigo_email() from public, anon;
grant execute on function public.pedir_codigo_email() to authenticated;

-- Confere o código. Cinco erros invalidam o código (precisa pedir outro).
create or replace function public.confirmar_codigo_email(p_codigo text)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid := auth.uid();
  v_c public.codigos_email%rowtype;
  v_email text;
begin
  if v_id is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if (select email_verificado from public.perfis where id = v_id) then return true; end if;

  select * into v_c from public.codigos_email where usuario_id = v_id for update;
  if not found or v_c.expira_em < now() or v_c.tentativas >= 5 then
    perform public.erro('codigo_vencido', 'Este código venceu. Peça um novo.');
  end if;
  select lower(email) into v_email from auth.users where id = v_id;
  if v_email is distinct from v_c.email then
    perform public.erro('codigo_vencido', 'O e-mail da conta mudou. Peça um novo código.');
  end if;

  if public.resumo_codigo(v_id, regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g')) <> v_c.codigo_hash then
    update public.codigos_email set tentativas = tentativas + 1 where usuario_id = v_id;
    return false;
  end if;

  delete from public.codigos_email where usuario_id = v_id;
  update public.perfis set email_verificado = true where id = v_id;
  return true;
end;
$$;
revoke all on function public.confirmar_codigo_email(text) from public, anon;
grant execute on function public.confirmar_codigo_email(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. E-mail verificado por outros caminhos
-- ---------------------------------------------------------------------------
-- Google (o Google já confirmou o e-mail) e o link de confirmação do Supabase
-- (enquanto o "Confirm email" estiver ligado, a confirmação vem como update).
create or replace function public.verificar_email_auth()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_google boolean := coalesce(new.raw_app_meta_data -> 'providers', '[]'::jsonb) ? 'google'
                      or new.raw_app_meta_data ->> 'provider' = 'google';
begin
  if tg_op = 'INSERT' then
    if v_google and new.email is not null then
      update public.perfis set email_verificado = true where id = new.id and not email_verificado;
    end if;
  elsif (old.email_confirmed_at is null and new.email_confirmed_at is not null)
     or (v_google and not (coalesce(old.raw_app_meta_data -> 'providers', '[]'::jsonb) ? 'google'))
     or (new.email is distinct from old.email and new.email is not null and new.email_confirmed_at is not null
         and old.email is not null) then
    -- Troca de e-mail: o Supabase só grava o novo depois do link de confirmação.
    update public.perfis set email_verificado = true where id = new.id and not email_verificado;
    if new.email is distinct from old.email then
      perform public.equipe_vincular_usuario(new.id);
    end if;
  end if;
  return null;
exception when others then
  return null;
end;
$$;

-- O nome começa com "verificar" para rodar depois de ao_criar_usuario (que cria o perfil).
drop trigger if exists verificar_email_auth on auth.users;
create trigger verificar_email_auth after insert or update of email_confirmed_at, email, raw_app_meta_data on auth.users
  for each row execute function public.verificar_email_auth();

-- ---------------------------------------------------------------------------
-- 4. Equipe do painel: entra só quem verificou o e-mail convidado
-- ---------------------------------------------------------------------------
create or replace function public.equipe_vincular_usuario(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select lower(u.email) into v_email
  from auth.users u join public.perfis p on p.id = u.id
  where u.id = p_id and p.email_verificado;
  if v_email is null then return; end if;
  update public.equipe e
     set usuario_id = p_id, entrou_em = coalesce(e.entrou_em, now())
   where e.email = v_email and (e.usuario_id is null or e.usuario_id = p_id);
  if found then
    update public.perfis set e_admin = true where id = p_id;
  end if;
end;
$$;
revoke all on function public.equipe_vincular_usuario(uuid) from public, anon, authenticated;

-- O gatilho antigo confiava em email_confirmed_at; agora quem decide é o perfil.
create or replace function public.equipe_vincular()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.equipe_vincular_usuario(new.id);
  return null;
exception when others then
  return null;
end;
$$;

create or replace function public.admin_convidar_equipe(p_email text, p_nome text, p_cargo text default 'suporte')
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cargo text := coalesce(nullif(btrim(p_cargo), ''), 'suporte');
  v_usuario uuid;
begin
  perform public.exigir_permissao('equipe_gerir');
  if v_cargo not in ('gerente', 'responsavel', 'suporte', 'marketing') then
    perform public.erro('cargo_invalido', 'Escolha um cargo da lista.');
  end if;
  if not public.pode_gerir_cargo(v_cargo) then
    perform public.erro('sem_permissao', 'Só o dono convida alguém como ' || public.cargo_nome(v_cargo) || '.');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.erro('email_invalido', 'Confira o e-mail digitado.');
  end if;
  if length(v_nome) < 2 then
    perform public.erro('nome_invalido', 'Informe o nome da pessoa.');
  end if;
  if exists (select 1 from public.equipe where email = v_email) then
    perform public.erro('ja_na_equipe', 'Este e-mail já está na equipe.');
  end if;

  -- Só quem já verificou a conta pelo e-mail entra direto (verificar pelo SMS
  -- não prova que a pessoa é dona do e-mail convidado).
  select u.id into v_usuario from auth.users u
  join public.perfis p on p.id = u.id
  where lower(u.email) = v_email and p.email_verificado
  limit 1;

  insert into public.equipe (email, nome, papel, usuario_id, convidado_por, entrou_em, recebe_emails)
  values (v_email, left(v_nome, 80), v_cargo, v_usuario, auth.uid(), case when v_usuario is not null then now() end,
    v_cargo <> 'marketing');

  if v_usuario is not null then
    update public.perfis set e_admin = true where id = v_usuario;
  end if;

  perform public.registrar_acao('convidar_equipe', coalesce(v_usuario::text, v_email),
    jsonb_build_object('nome', v_nome, 'email', v_email, 'cargo', v_cargo));
  return case when v_usuario is not null then 'ativo' else 'convite_pendente' end;
end;
$$;

revoke all on function public.admin_convidar_equipe(text, text, text) from public, anon;
grant execute on function public.admin_convidar_equipe(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Conta verificada: boas-vindas e equipe
-- ---------------------------------------------------------------------------
-- As boas-vindas saíam quando o Supabase confirmava o e-mail; agora saem quando
-- a conta fica verificada pela primeira vez (e-mail ou SMS).
drop trigger if exists boas_vindas on auth.users;

create or replace function public.conta_verificada_marcar()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.verificado_em is null and (new.email_verificado or new.telefone_verificado) then
    new.verificado_em := now();
    begin
      if not exists (select 1 from public.equipe e join auth.users u on lower(u.email) = e.email where u.id = new.id) then
        perform public.notificar(new.id, 'boas_vindas', 'Boas-vindas ao iService!',
          case when exists (select 1 from public.profissionais where id = new.id)
            then 'Complete seu cadastro e envie para análise para começar a receber pedidos.'
            else 'Encontre profissionais avaliados perto de você, ainda hoje.' end);
      end if;
    exception when others then
      null; -- nunca impedir a verificação por causa do aviso
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists conta_verificada_marcar on public.perfis;
create trigger conta_verificada_marcar before update of email_verificado, telefone_verificado on public.perfis
  for each row execute function public.conta_verificada_marcar();

create or replace function public.email_verificado_equipe()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.email_verificado and not old.email_verificado then
    perform public.equipe_vincular_usuario(new.id);
  end if;
  return null;
exception when others then
  return null;
end;
$$;

drop trigger if exists email_verificado_equipe on public.perfis;
create trigger email_verificado_equipe after update of email_verificado on public.perfis
  for each row execute function public.email_verificado_equipe();

-- ---------------------------------------------------------------------------
-- 6. Sem conta verificada, não pede nem recebe pedidos
-- ---------------------------------------------------------------------------
create or replace function public.exigir_celular_pedido()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.conta_verificada(new.cliente_id) then
    perform public.erro('conta_nao_verificada', 'Verifique sua conta pelo e-mail ou SMS para fazer pedidos.');
  end if;
  if public.cfg_bool('exigir_celular_verificado', false)
     and not coalesce((select telefone_verificado from public.perfis where id = new.cliente_id), false) then
    perform public.erro('celular_nao_verificado', 'Confirme seu celular por SMS para fazer pedidos.');
  end if;
  return new;
end;
$$;

create or replace function public.exigir_celular_disponivel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.disponivel and not old.disponivel and new.id = auth.uid() then
    if not public.conta_verificada(new.id) then
      perform public.erro('conta_nao_verificada', 'Verifique sua conta pelo e-mail ou SMS para receber pedidos.');
    end if;
    if public.cfg_bool('exigir_celular_verificado', false)
       and not coalesce((select telefone_verificado from public.perfis where id = new.id), false) then
      perform public.erro('celular_nao_verificado', 'Confirme seu celular por SMS para receber pedidos.');
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.exigir_celular_pedido() from public, anon, authenticated;
revoke all on function public.exigir_celular_disponivel() from public, anon, authenticated;
revoke all on function public.conta_verificada_marcar() from public, anon, authenticated;
revoke all on function public.email_verificado_equipe() from public, anon, authenticated;
revoke all on function public.verificar_email_auth() from public, anon, authenticated;
revoke all on function public.equipe_vincular() from public, anon, authenticated;
