-- Recebimentos do profissional e página Pagamentos do painel (decisão de 20/11/2026:
-- pagamento pelo app e taxa de 10% ligados desde o lançamento, em 05/01/2027).
--
-- A conta de recebimento é uma subconta do Asaas no nome do profissional. O Asaas manda
-- um e-mail para ele ativar a conta e enviar documento e selfie. Depois de aprovada,
-- os repasses caem nela e ele saca por Pix pelo app do Asaas.
-- A chave de API da subconta (devolvida uma vez, na criação) fica no Vault.

-- ---------------------------------------------------------------------------
-- 1. Situação da conta no Asaas
-- ---------------------------------------------------------------------------
alter table public.contas_recebimento add column if not exists situacao text not null default 'aguardando_ativacao';
alter table public.contas_recebimento drop constraint if exists contas_recebimento_situacao_check;
alter table public.contas_recebimento add constraint contas_recebimento_situacao_check
  check (situacao in ('aguardando_ativacao', 'em_analise', 'aprovada', 'recusada'));
alter table public.contas_recebimento add column if not exists link_documentos text;
alter table public.contas_recebimento add column if not exists conferida_em timestamptz;
grant select (profissional_id, status, situacao, link_documentos, criada_em) on public.contas_recebimento to authenticated;

-- Chave da subconta: só a função "pagamentos" (service_role) guarda e lê.
create or replace function public.guardar_chave_subconta(p_profissional uuid, p_chave text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_nome text := 'asaas_subconta_' || p_profissional::text;
begin
  delete from vault.secrets where name = v_nome;
  perform vault.create_secret(p_chave, v_nome, 'Chave de API da subconta Asaas do profissional');
end;
$$;
revoke all on function public.guardar_chave_subconta(uuid, text) from public, anon, authenticated;
grant execute on function public.guardar_chave_subconta(uuid, text) to service_role;

create or replace function public.chave_subconta(p_profissional uuid)
returns text
language sql stable security definer
set search_path = public
as $$ select decrypted_secret from vault.decrypted_secrets where name = 'asaas_subconta_' || p_profissional::text $$;
revoke all on function public.chave_subconta(uuid) from public, anon, authenticated;
grant execute on function public.chave_subconta(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Recebimentos do profissional (tela Recebimentos no app)
-- ---------------------------------------------------------------------------
create or replace function public.meus_recebimentos()
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_uid uuid := auth.uid();
  v_conta public.contas_recebimento;
begin
  if v_uid is null or not exists (select 1 from public.profissionais where id = v_uid) then
    perform public.erro('sem_permissao', 'Só para profissionais.');
  end if;
  select * into v_conta from public.contas_recebimento where profissional_id = v_uid;
  return jsonb_build_object(
    'ativo', public.pagamento_ativo(),
    'taxa_servico_pct', round(public.cfg_num('taxa_servico', 0.1) * 100),
    'conta', case when v_conta.profissional_id is null then null else jsonb_build_object(
      'status', v_conta.status, 'situacao', v_conta.situacao, 'link_documentos', v_conta.link_documentos) end,
    'a_receber', (select coalesce(sum(g.valor_profissional), 0) from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
                  where p.profissional_id = v_uid and g.status in ('pago', 'a_liberar')),
    'aguardando_cliente', (select coalesce(sum(g.valor_profissional), 0) from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
                  where p.profissional_id = v_uid and g.status = 'aguardando'),
    'recebido_mes', (select coalesce(sum(g.valor_profissional), 0) from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
                  where p.profissional_id = v_uid and g.status = 'liberado' and g.liberado_em >= date_trunc('month', now())),
    'itens', coalesce((select jsonb_agg(x order by x.data desc) from (
      select g.id, g.pedido_id, g.tipo, g.status, g.valor_profissional valor,
        coalesce(g.liberado_em, g.pago_em, g.criado_em) data,
        coalesce(e.nome, pr.nome) servico,
        split_part(coalesce(c.nome, ''), ' ', 1) cliente
      from public.pagamentos g
      join public.pedidos p on p.id = g.pedido_id
      left join public.especialidades e on e.id = p.especialidade_id
      left join public.profissoes pr on pr.id = p.profissao_id
      left join public.perfis c on c.id = p.cliente_id
      where p.profissional_id = v_uid and g.status <> 'criando'
      order by coalesce(g.liberado_em, g.pago_em, g.criado_em) desc
      limit 50) x), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.meus_recebimentos() from public, anon;
grant execute on function public.meus_recebimentos() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Página Pagamentos do painel (quem tem Pedidos)
-- ---------------------------------------------------------------------------
create or replace function public.admin_pagamentos(p_status text default null, p_busca text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_busca text := nullif(trim(coalesce(p_busca, '')), '');
begin
  perform public.exigir_permissao('pedidos');
  return jsonb_build_object(
    'ativo', public.pagamento_ativo(),
    'resumo', (select jsonb_build_object(
        'aguardando', count(*) filter (where status = 'aguardando'),
        'guardado', coalesce(sum(valor - estornado_valor) filter (where status in ('pago', 'a_liberar')), 0),
        'liberado_mes', coalesce(sum(valor_profissional) filter (where status = 'liberado' and liberado_em >= date_trunc('month', now())), 0),
        'taxa_mes', coalesce(sum(valor_plataforma) filter (where status = 'liberado' and liberado_em >= date_trunc('month', now())), 0),
        'estornado_mes', coalesce(sum(estornado_valor) filter (where status = 'estornado' and atualizado_em >= date_trunc('month', now())), 0),
        'com_erro', count(*) filter (where status = 'falhou' or erro is not null and status not in ('liberado', 'estornado', 'cancelado')))
      from public.pagamentos),
    'contas', (select jsonb_build_object(
        'total', count(*),
        'aprovadas', count(*) filter (where situacao = 'aprovada'),
        'pendentes', count(*) filter (where situacao in ('aguardando_ativacao', 'em_analise')),
        'com_problema', count(*) filter (where status = 'falhou' or situacao = 'recusada'))
      from public.contas_recebimento),
    'itens', coalesce((select jsonb_agg(x order by x.criado_em desc) from (
      select g.id, g.pedido_id, g.tipo, g.status, g.valor, g.valor_profissional, g.valor_plataforma, g.estornado_valor,
        g.criado_em, g.pago_em, g.liberado_em, g.vence_em, g.erro,
        c.nome cliente, pf.nome profissional, p.status pedido_status
      from public.pagamentos g
      join public.pedidos p on p.id = g.pedido_id
      left join public.perfis c on c.id = p.cliente_id
      left join public.perfis pf on pf.id = p.profissional_id
      where (p_status is null or p_status = '' or g.status = p_status
             or (p_status = 'com_erro' and (g.status = 'falhou' or g.erro is not null)))
        and (v_busca is null or c.nome ilike '%' || v_busca || '%' or pf.nome ilike '%' || v_busca || '%'
             or g.pedido_id::text like v_busca || '%')
      order by g.criado_em desc
      limit 200) x), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_pagamentos(text, text) from public, anon;
grant execute on function public.admin_pagamentos(text, text) to authenticated;

-- Refazer um passo que falhou (cobrança, repasse ou conta), pelo painel.
create or replace function public.admin_pagamento_refazer(p_pagamento uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  g public.pagamentos;
begin
  perform public.exigir_permissao('pedidos');
  select * into g from public.pagamentos where id = p_pagamento;
  if g.id is null then perform public.erro('nao_encontrado', 'Pagamento não encontrado.'); end if;
  update public.pagamentos set erro = null, atualizado_em = now() where id = g.id;
  perform public.chamar_funcao('pagamentos', jsonb_build_object('acao', 'sincronizar'));
end;
$$;
revoke all on function public.admin_pagamento_refazer(uuid) from public, anon;
grant execute on function public.admin_pagamento_refazer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Respostas prontas do suporte sobre pagamento
-- ---------------------------------------------------------------------------
update public.suporte_respostas set titulo = 'Como funciona o pagamento',
  texto = E'Olá, {nome}!\n\nA partir de 5 de janeiro de 2027, todo serviço é pago pelo app, com Pix ou cartão, logo depois que o profissional aceita o pedido. O valor fica guardado e só vai para o profissional quando o serviço é concluído. Se o pedido for cancelado antes do atendimento, o dinheiro volta para você.\n\nNunca pague direto ao profissional nem por fora do app: assim você fica protegido pela Garantia iService.\n\n{atendente}'
where titulo = 'Pagamento direto ao profissional';
insert into public.suporte_respostas (titulo, texto) values
  ('Ativar a conta de recebimento', E'Olá, {nome}!\n\nPara receber pelos serviços, abra o app iService Profissional, vá em Ganhos > Recebimentos e toque em "Enviar documento e selfie". A conta fica no seu nome e CPF, no Asaas, nossa instituição de pagamento parceira. A análise costuma levar poucos minutos e, no máximo, 2 dias úteis.\n\nDepois de aprovada, os valores dos serviços concluídos caem nela, e você saca por Pix pelo app do Asaas.\n\n{atendente}')
on conflict do nothing;
