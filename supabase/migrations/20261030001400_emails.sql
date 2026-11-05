-- E-mails automáticos de cada etapa.
--
-- Cada etapa importante vira uma notificação (aparece no app e vai por push) e,
-- para os tipos abaixo, também por e-mail: o gatilho notificacao_email chama a
-- Edge Function enviar-email, que monta o e-mail com os modelos da marca.
-- As etapas que ainda não geravam notificação ganham gatilhos aqui:
-- boas-vindas, cadastro recebido, reclamação aberta e conta suspensa.

-- ---------------------------------------------------------------------------
-- 1. Registro dos e-mails (um por notificação; a equipe vê o que saiu)
-- ---------------------------------------------------------------------------
create table if not exists public.emails_enviados (
  notificacao_id bigint primary key references public.notificacoes (id) on delete cascade,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  tipo text not null,
  para text not null,
  assunto text not null,
  status text not null default 'enviando' check (status in ('enviando', 'enviado', 'erro', 'sem_chave')),
  erro text,
  id_externo text,
  criado_em timestamptz not null default now(),
  enviado_em timestamptz
);
create index if not exists emails_enviados_usuario_idx on public.emails_enviados (usuario_id, criado_em desc);
alter table public.emails_enviados enable row level security;
revoke all on public.emails_enviados from anon, authenticated;
grant select on public.emails_enviados to authenticated;
drop policy if exists "emails_enviados: admin lê" on public.emails_enviados;
create policy "emails_enviados: admin lê" on public.emails_enviados for select to authenticated using (public.e_admin());

insert into public.app_config (chave, valor, descricao)
values ('emails_ativos', 'true', 'Envia por e-mail os avisos de cadastro, garantia e conta')
on conflict (chave) do nothing;

-- Tipos de notificação que também vão por e-mail. Avisos do dia a dia
-- (pedido aceito, mensagem, a caminho) ficam só no push.
create or replace function public.tipo_tem_email(p_tipo text)
returns boolean
language sql immutable
as $$ select p_tipo = any (array[
  'boas_vindas', 'cadastro_recebido', 'cadastro_aprovado', 'cadastro_recusado', 'documento_recusado',
  'reclamacao_aberta', 'reclamacao_recebida', 'garantia', 'conta_suspensa', 'conta_reativada', 'exclusao_conta'
]) $$;

create or replace function public.notificacao_email()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if public.tipo_tem_email(new.tipo) and public.cfg_bool('emails_ativos', true)
     and exists (select 1 from public.perfis where id = new.usuario_id and coalesce(email, '') <> '') then
    perform public.chamar_funcao('enviar-email', jsonb_build_object('notificacao_id', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists notificacao_email on public.notificacoes;
create trigger notificacao_email after insert on public.notificacoes
  for each row execute function public.notificacao_email();

-- ---------------------------------------------------------------------------
-- 2. Boas-vindas: quando a pessoa confirma o e-mail
-- ---------------------------------------------------------------------------
create or replace function public.boas_vindas()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null
     and exists (select 1 from public.perfis where id = new.id) then
    perform public.notificar(new.id, 'boas_vindas', 'Boas-vindas ao iService!',
      case when exists (select 1 from public.profissionais where id = new.id)
        then 'Complete seu cadastro e envie para análise para começar a receber pedidos.'
        else 'Encontre profissionais avaliados perto de você, ainda hoje.' end);
  end if;
  return null;
exception when others then
  -- Nunca impedir a confirmação do e-mail por causa do aviso.
  return null;
end;
$$;

drop trigger if exists boas_vindas on auth.users;
create trigger boas_vindas after update of email_confirmed_at on auth.users
  for each row execute function public.boas_vindas();

-- ---------------------------------------------------------------------------
-- 3. Cadastro do profissional recebido (enviado ou reenviado para análise)
-- ---------------------------------------------------------------------------
create or replace function public.cadastro_recebido()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.status = 'em_analise' and old.status in ('rascunho', 'recusado') then
    perform public.notificar(new.id, 'cadastro_recebido',
      case when old.status = 'recusado' then 'Cadastro reenviado para análise' else 'Recebemos seu cadastro' end,
      'Nossa equipe está conferindo seus dados. Avisamos assim que a análise terminar.',
      jsonb_build_object('reenvio', old.status = 'recusado', 'enviado_em', now()));
  end if;
  return null;
end;
$$;

drop trigger if exists cadastro_recebido on public.profissionais;
create trigger cadastro_recebido after update of status on public.profissionais
  for each row execute function public.cadastro_recebido();

-- ---------------------------------------------------------------------------
-- 4. Reclamação aberta (Garantia iService): avisa quem abriu e a outra parte
-- ---------------------------------------------------------------------------
create or replace function public.reclamacao_aberta()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_outro uuid;
  v_protocolo text := 'G-' || lpad(new.id::text, 5, '0');
  v_dados jsonb;
begin
  select * into v_ped from public.pedidos where id = new.pedido_id;
  v_outro := case when new.autor_id = v_ped.cliente_id then v_ped.profissional_id else v_ped.cliente_id end;
  v_dados := jsonb_build_object('pedido_id', v_ped.id, 'reclamacao_id', new.id);
  perform public.notificar(new.autor_id, 'reclamacao_aberta', 'Reclamação recebida · protocolo ' || v_protocolo,
    'Nossa equipe vai analisar e mediar uma solução. Você recebe cada atualização por aqui.', v_dados);
  perform public.notificar(v_outro, 'reclamacao_recebida', 'Reclamação aberta sobre o pedido #' || v_ped.codigo,
    'A equipe iService vai ouvir os dois lados e mediar uma solução.', v_dados);
  return null;
end;
$$;

drop trigger if exists reclamacao_aberta on public.reclamacoes;
create trigger reclamacao_aberta after insert on public.reclamacoes
  for each row execute function public.reclamacao_aberta();

-- ---------------------------------------------------------------------------
-- 5. Conta suspensa (a reativação já avisa em admin_suspender)
-- ---------------------------------------------------------------------------
create or replace function public.conta_suspensa()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if old.suspenso_em is null and new.suspenso_em is not null then
    perform public.notificar(new.id, 'conta_suspensa', 'Sua conta foi suspensa',
      coalesce(nullif(trim(new.motivo_suspensao), ''), 'Fale com o suporte para saber mais.'));
  end if;
  return null;
end;
$$;

drop trigger if exists conta_suspensa on public.perfis;
create trigger conta_suspensa after update of suspenso_em on public.perfis
  for each row execute function public.conta_suspensa();

revoke all on function public.notificacao_email(), public.boas_vindas(), public.cadastro_recebido(),
  public.reclamacao_aberta(), public.conta_suspensa() from public, anon, authenticated;
