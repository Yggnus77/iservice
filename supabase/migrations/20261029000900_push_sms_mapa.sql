-- Etapas finais do MVP (29/10/2026):
--  1. Notificações push: cada notificação nova chama a função enviar-push.
--  2. Celular confirmado por SMS (exigência ligada por app_config).
--  3. Mapa em tempo real do profissional a caminho.
--  4. Limpeza diária dos arquivos das contas excluídas (função limpar-arquivos).
--
-- As chamadas para as Edge Functions usam dois segredos do Vault, criados uma vez
-- no SQL Editor (sem eles nada é chamado e o resto funciona normalmente):
--   select vault.create_secret('https://<projeto>.supabase.co', 'iservice_url');
--   select vault.create_secret('<chave service_role>', 'iservice_chave_servico');

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- Chamada às Edge Functions
-- ---------------------------------------------------------------------------
create or replace function public.chamar_funcao(p_nome text, p_corpo jsonb default '{}')
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_url text;
  v_chave text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'iservice_url';
  select decrypted_secret into v_chave from vault.decrypted_secrets where name = 'iservice_chave_servico';
  if v_url is null or v_chave is null then return; end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || p_nome,
    body := p_corpo,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_chave),
    timeout_milliseconds := 10000
  );
exception when others then
  -- Sem Vault ou sem pg_net (banco de testes) ou falha de rede: o app segue normal.
  null;
end;
$$;

revoke all on function public.chamar_funcao(text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Push
-- ---------------------------------------------------------------------------
-- O mesmo aparelho pode trocar de conta: o token passa para quem entrou por último.
create or replace function public.registrar_dispositivo(p_token text, p_app text, p_plataforma text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  insert into public.dispositivos (token, usuario_id, app, plataforma, atualizado_em)
  values (p_token, auth.uid(), p_app, p_plataforma, now())
  on conflict (token) do update set usuario_id = excluded.usuario_id, app = excluded.app,
    plataforma = excluded.plataforma, atualizado_em = now();
end;
$$;

create or replace function public.remover_dispositivo(p_token text)
returns void
language sql security definer
set search_path = public
as $$ delete from public.dispositivos where token = p_token and usuario_id = auth.uid() $$;

revoke all on function public.registrar_dispositivo(text, text, text) from public, anon;
revoke all on function public.remover_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text, text) to authenticated;
grant execute on function public.remover_dispositivo(text) to authenticated;

create or replace function public.notificacao_push()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.dispositivos where usuario_id = new.usuario_id) then
    perform public.chamar_funcao('enviar-push', jsonb_build_object('notificacao_id', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists notificacao_push on public.notificacoes;
create trigger notificacao_push after insert on public.notificacoes
  for each row execute function public.notificacao_push();

-- ---------------------------------------------------------------------------
-- 2. Celular confirmado por SMS
-- ---------------------------------------------------------------------------
-- O app manda o código pelo Supabase Auth (troca de telefone + código por SMS).
-- Depois de confirmado lá, esta função copia o número para o perfil e marca
-- telefone_verificado. O usuário não consegue marcar sozinho (sem permissão na coluna).
insert into public.app_config (chave, valor, descricao) values
  ('exigir_celular_verificado', 'false', 'Exige celular confirmado por SMS para pedir (cliente) e ficar disponível (profissional). Ligue depois de configurar o SMS no Supabase.')
on conflict (chave) do nothing;

create or replace function public.confirmar_celular()
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  v_fone text;
  v_confirmado timestamptz;
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  begin
    execute 'select phone, phone_confirmed_at from auth.users where id = $1' into v_fone, v_confirmado using auth.uid();
  exception when undefined_column then
    return false;
  end;
  if v_fone is null or v_confirmado is null then return false; end if;
  -- auth guarda 55 + DDD + número; o perfil guarda DDD + número.
  v_fone := regexp_replace(v_fone, '\D', '', 'g');
  if v_fone like '55%' and length(v_fone) > 11 then v_fone := substr(v_fone, 3); end if;
  perform set_config('iservice.confirmando_celular', 'sim', true);
  update public.perfis set telefone = v_fone, telefone_verificado = true where id = auth.uid();
  perform set_config('iservice.confirmando_celular', '', true);
  return true;
end;
$$;

revoke all on function public.confirmar_celular() from public, anon;
grant execute on function public.confirmar_celular() to authenticated;

-- Trocar o número no perfil desfaz a confirmação.
create or replace function public.celular_trocado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.telefone is distinct from old.telefone
     and coalesce(current_setting('iservice.confirmando_celular', true), '') <> 'sim' then
    new.telefone_verificado := false;
  end if;
  return new;
end;
$$;

drop trigger if exists celular_trocado on public.perfis;
create trigger celular_trocado before update of telefone on public.perfis
  for each row execute function public.celular_trocado();

create or replace function public.exigir_celular_pedido()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.cfg_bool('exigir_celular_verificado', false)
     and not coalesce((select telefone_verificado from public.perfis where id = new.cliente_id), false) then
    perform public.erro('celular_nao_verificado', 'Confirme seu celular por SMS para fazer pedidos.');
  end if;
  return new;
end;
$$;

drop trigger if exists exigir_celular_pedido on public.pedidos;
create trigger exigir_celular_pedido before insert on public.pedidos
  for each row execute function public.exigir_celular_pedido();

create or replace function public.exigir_celular_disponivel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.disponivel and not old.disponivel and new.id = auth.uid()
     and public.cfg_bool('exigir_celular_verificado', false)
     and not coalesce((select telefone_verificado from public.perfis where id = new.id), false) then
    perform public.erro('celular_nao_verificado', 'Confirme seu celular por SMS para receber pedidos.');
  end if;
  return new;
end;
$$;

drop trigger if exists exigir_celular_disponivel on public.profissionais;
create trigger exigir_celular_disponivel before update of disponivel on public.profissionais
  for each row execute function public.exigir_celular_disponivel();

-- ---------------------------------------------------------------------------
-- 3. Mapa em tempo real
-- ---------------------------------------------------------------------------
-- Só existe enquanto o profissional está a caminho (antes disso ele pode estar em
-- casa, e a casa não deve aparecer); some quando ele chega ou o pedido acaba.
-- O cliente acompanha pelo Realtime.
create table if not exists public.posicoes_pedido (
  pedido_id uuid primary key references public.pedidos (id) on delete cascade,
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  precisao_m real,
  destino_lat double precision not null,
  destino_lng double precision not null,
  atualizado_em timestamptz not null default now()
);

alter table public.posicoes_pedido enable row level security;
grant select on public.posicoes_pedido to authenticated;
drop policy if exists "posicoes: envolvidos no pedido" on public.posicoes_pedido;
create policy "posicoes: envolvidos no pedido" on public.posicoes_pedido for select to authenticated using (
  exists (select 1 from public.pedidos p where p.id = pedido_id and auth.uid() in (p.cliente_id, p.profissional_id))
);

create or replace function public.enviar_posicao(p_pedido uuid, p_lat double precision, p_lng double precision, p_precisao real default null)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ped public.pedidos;
begin
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid();
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status <> 'a_caminho' then return; end if;
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform public.erro('posicao_invalida', 'Localização inválida.');
  end if;
  insert into public.posicoes_pedido (pedido_id, profissional_id, lat, lng, precisao_m, destino_lat, destino_lng, atualizado_em)
  values (p_pedido, auth.uid(), p_lat, p_lng, p_precisao,
    st_y(v_ped.localizacao::geometry), st_x(v_ped.localizacao::geometry), now())
  on conflict (pedido_id) do update set lat = excluded.lat, lng = excluded.lng, precisao_m = excluded.precisao_m,
    atualizado_em = now();
end;
$$;

revoke all on function public.enviar_posicao(uuid, double precision, double precision, real) from public, anon;
grant execute on function public.enviar_posicao(uuid, double precision, double precision, real) to authenticated;

create or replace function public.apagar_posicao()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.status <> 'a_caminho' then
    delete from public.posicoes_pedido where pedido_id = new.id;
  end if;
  return null;
end;
$$;

drop trigger if exists apagar_posicao on public.pedidos;
create trigger apagar_posicao after update of status on public.pedidos
  for each row execute function public.apagar_posicao();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'posicoes_pedido') then
    alter publication supabase_realtime add table public.posicoes_pedido;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Limpeza diária dos arquivos das contas excluídas (depois da exclusão das 06:00)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iservice-limpar-arquivos', '0 7 * * *', $c$select public.chamar_funcao('limpar-arquivos')$c$);
  end if;
end;
$$;
