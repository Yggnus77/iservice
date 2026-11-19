-- Pagamento pelo app com o Asaas (decisão do usuário em 19/11/2026).
--
-- Tudo pronto e DESLIGADO (pagamento_ativo = false) até o iService ter CNPJ e
-- conta jurídica no Asaas. Quando ligar:
--   1. O profissional aprovado ganha uma conta de recebimento no Asaas (subconta).
--   2. Quando o profissional aceita um pedido com preço, o cliente recebe a cobrança
--      (Pix ou cartão) e paga pelo app. Sem pagamento, o profissional não sai "a caminho".
--      Pedido sem preço ("combinado no local") é cobrado ao concluir, pelo valor informado.
--   3. O dinheiro fica guardado na conta do iService até o serviço ser concluído.
--      Aí o valor do profissional (preço + deslocamento + acréscimos) é transferido
--      para a conta dele e a taxa de serviço fica com o iService.
--   4. Pedido cancelado depois de pago é estornado ao cliente.
--   (Telefones, e-mails e Pix ficam escondidos em todos os textos: migração 20261120004000.)
-- O trabalho com o Asaas é feito pela Edge Function "pagamentos".

insert into public.app_config (chave, valor, descricao) values
  ('pagamento_ativo', 'false'::jsonb, 'Liga o pagamento pelo app (Asaas). Só ligar com CNPJ, conta jurídica no Asaas e os segredos ASAAS_* configurados.'),
  ('pagamento_prazo_horas', '2'::jsonb, 'Horas que o cliente tem para pagar depois do aceite. Depois disso o pedido é cancelado.')
on conflict (chave) do nothing;

create or replace function public.pagamento_ativo()
returns boolean
language sql stable
set search_path = public
as $$ select coalesce((public.cfg('pagamento_ativo'))::text, 'false') = 'true' $$;

-- Conta de recebimento do profissional no Asaas (subconta).
create table if not exists public.contas_recebimento (
  profissional_id uuid primary key references public.profissionais (id) on delete cascade,
  asaas_conta_id text unique,
  asaas_carteira_id text unique,
  status text not null default 'pendente' check (status in ('pendente', 'ativa', 'falhou')),
  erro text,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now()
);
alter table public.contas_recebimento enable row level security;
revoke all on public.contas_recebimento from anon, authenticated;
grant select (profissional_id, status, criada_em) on public.contas_recebimento to authenticated;
drop policy if exists "contas_recebimento: a própria" on public.contas_recebimento;
create policy "contas_recebimento: a própria" on public.contas_recebimento for select to authenticated
  using (profissional_id = auth.uid());

-- Cliente no Asaas (um por pessoa).
create table if not exists public.clientes_pagamento (
  usuario_id uuid primary key references public.perfis (id) on delete cascade,
  asaas_cliente_id text not null unique,
  criado_em timestamptz not null default now()
);
alter table public.clientes_pagamento enable row level security;
revoke all on public.clientes_pagamento from anon, authenticated;

-- Uma cobrança por pedido (mais um complemento, se o valor final passar do pago).
create table if not exists public.pagamentos (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references public.pedidos (id) on delete cascade,
  tipo text not null default 'principal' check (tipo in ('principal', 'complemento')),
  status text not null default 'criando'
    check (status in ('criando', 'aguardando', 'pago', 'a_liberar', 'liberado', 'estornado', 'cancelado', 'falhou')),
  valor numeric(10, 2) not null check (valor > 0),
  valor_profissional numeric(10, 2) not null check (valor_profissional >= 0),
  valor_plataforma numeric(10, 2) not null check (valor_plataforma >= 0),
  asaas_cobranca_id text unique,
  asaas_transferencia_id text,
  pix_copia_cola text,
  pix_imagem text,
  link_pagamento text,
  vence_em timestamptz,
  pago_em timestamptz,
  liberado_em timestamptz,
  estornado_valor numeric(10, 2) not null default 0,
  erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (pedido_id, tipo)
);
create index if not exists pagamentos_status on public.pagamentos (status);
alter table public.pagamentos enable row level security;
revoke all on public.pagamentos from anon, authenticated;
grant select on public.pagamentos to authenticated;
drop policy if exists "pagamentos: partes do pedido" on public.pagamentos;
create policy "pagamentos: partes do pedido" on public.pagamentos for select to authenticated
  using (exists (select 1 from public.pedidos p where p.id = pedido_id and auth.uid() in (p.cliente_id, p.profissional_id))
         or (public.e_admin() and public.pode('pedidos')));
do $$ begin
  alter publication supabase_realtime add table public.pagamentos;
exception when others then null; end $$;

-- Quanto o cliente paga e quanto vai para o profissional, a partir dos valores do pedido.
create or replace function public.valores_pagamento(p_pedido public.pedidos, p_final boolean default false)
returns table (valor numeric, valor_profissional numeric, valor_plataforma numeric)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_pro numeric;
  v_taxa numeric;
begin
  if p_final and p_pedido.valor_cobrado is not null then
    v_pro := p_pedido.valor_cobrado;
    v_taxa := public.valor_taxa_servico(v_pro);
  elsif p_pedido.preco_informado is not null then
    v_pro := p_pedido.preco_informado + p_pedido.deslocamento + p_pedido.taxa_urgencia + p_pedido.taxa_fora_horario;
    v_taxa := p_pedido.taxa_servico;
  else
    return;
  end if;
  return query select round(v_pro + v_taxa, 2), round(v_pro, 2), round(v_taxa, 2);
end;
$$;
revoke all on function public.valores_pagamento(public.pedidos, boolean) from public, anon, authenticated;

-- O pedido mudou de situação: cobra, libera ou estorna.
create or replace function public.pagamento_do_pedido()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v record;
begin
  if not public.pagamento_ativo() or new.status is not distinct from old.status then return new; end if;

  if new.status = 'aceito' then
    select * into v from public.valores_pagamento(new, false);
    if v.valor is not null and v.valor > 0 then
      insert into public.pagamentos (pedido_id, valor, valor_profissional, valor_plataforma, vence_em)
      values (new.id, v.valor, v.valor_profissional, v.valor_plataforma,
              now() + make_interval(hours => public.cfg_num('pagamento_prazo_horas', 2)::int))
      on conflict (pedido_id, tipo) do nothing;
      perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'cobrar', 'pedido_id', new.id));
    end if;
  elsif new.status = 'concluido' then
    perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'concluir', 'pedido_id', new.id));
  elsif new.status in ('cancelado', 'recusado', 'expirado') then
    perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'estornar', 'pedido_id', new.id));
  end if;
  return new;
end;
$$;
revoke all on function public.pagamento_do_pedido() from public, anon, authenticated;
drop trigger if exists pagamento_do_pedido on public.pedidos;
create trigger pagamento_do_pedido after update of status on public.pedidos
  for each row execute function public.pagamento_do_pedido();

-- Sem pagamento confirmado, o profissional não sai para o atendimento.
create or replace function public.exigir_pagamento()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if public.pagamento_ativo() and old.status = 'aceito' and new.status in ('a_caminho', 'em_atendimento')
     and exists (select 1 from public.pagamentos where pedido_id = new.id and tipo = 'principal' and status in ('criando', 'aguardando', 'falhou')) then
    perform public.erro('aguardando_pagamento', 'O cliente ainda não pagou. Você é avisado assim que o pagamento cair.');
  end if;
  return new;
end;
$$;
revoke all on function public.exigir_pagamento() from public, anon, authenticated;
drop trigger if exists exigir_pagamento on public.pedidos;
create trigger exigir_pagamento before update of status on public.pedidos
  for each row execute function public.exigir_pagamento();

-- Profissional aprovado ganha a conta de recebimento.
create or replace function public.conta_recebimento_ao_aprovar()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if public.pagamento_ativo() and new.status = 'aprovado' and old.status is distinct from 'aprovado' then
    insert into public.contas_recebimento (profissional_id) values (new.id) on conflict do nothing;
    perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'criar_conta', 'profissional_id', new.id));
  end if;
  return new;
end;
$$;
revoke all on function public.conta_recebimento_ao_aprovar() from public, anon, authenticated;
drop trigger if exists conta_recebimento_ao_aprovar on public.profissionais;
create trigger conta_recebimento_ao_aprovar after update of status on public.profissionais
  for each row execute function public.conta_recebimento_ao_aprovar();

-- A cada 15 minutos: cria contas que faltam, refaz transferências e cobranças que falharam
-- e cancela pedidos não pagos no prazo. Só faz algo com o pagamento ligado.
create or replace function public.processar_pagamentos()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.pagamento_ativo() then return; end if;
  insert into public.contas_recebimento (profissional_id)
  select id from public.profissionais where status = 'aprovado' on conflict do nothing;
  update public.pedidos p set status = 'cancelado'
  from public.pagamentos g
  where g.pedido_id = p.id and g.tipo = 'principal' and g.status = 'aguardando' and g.vence_em < now() and p.status = 'aceito';
  perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'sincronizar'));
end;
$$;
revoke all on function public.processar_pagamentos() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'iservice-pagamentos';
    perform cron.schedule('iservice-pagamentos', '*/15 * * * *', 'select public.processar_pagamentos()');
  end if;
end;
$$;

-- Para a Edge Function: valores finais de um pedido (pelo valor informado ao concluir).
create or replace function public.valores_pagamento_final(p_pedido_id uuid)
returns table (valor numeric, valor_profissional numeric, valor_plataforma numeric)
language sql stable security definer
set search_path = public
as $$ select v.* from public.pedidos p, lateral public.valores_pagamento(p, true) v where p.id = p_pedido_id $$;
revoke all on function public.valores_pagamento_final(uuid) from public, anon, authenticated;
grant execute on function public.valores_pagamento_final(uuid) to service_role;
grant execute on function public.notificar(uuid, text, text, text, jsonb) to service_role;
