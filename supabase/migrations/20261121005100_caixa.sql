-- Aba Caixa e página Comercial do painel (21/11/2026).
--
-- Receitas da plataforma num só lugar: taxas de serviço (10%) dos pedidos pagos pelo app e
-- assinaturas VIP/Premium dos profissionais, menos as tarifas do Asaas, com o líquido, a meta
-- mensal e os cadastros ativos pagantes e não pagantes.
--
-- As assinaturas ainda não são cobradas (preço em abril): as tabelas ficam prontas e a aba
-- começa a contar sozinha quando a cobrança for ligada.
-- Quem vê: permissão nova "caixa" (dono e gerente geral; o dono pode dar a outros na tela Cargos).

-- ---------------------------------------------------------------------------
-- 1. Permissão "caixa"
-- ---------------------------------------------------------------------------
create or replace function public.permissoes_catalogo()
returns table (chave text, grupo text, nome text, descricao text, ordem integer)
language sql immutable
as $$
  select * from (values
    ('inicio', 'Geral', 'Início', 'Números do dia. Sempre ligado.', 1),
    ('emails', 'Operação', 'E-mails do suporte', 'Atende os próprios e-mails e os sem responsável.', 10),
    ('emails_todos', 'Operação', 'E-mails de todos', 'Vê e transfere a conversa de qualquer pessoa e liga ou desliga o rodízio.', 11),
    ('cadastros', 'Operação', 'Cadastros', 'Vê os cadastros de profissionais em análise.', 12),
    ('cadastros_decidir', 'Operação', 'Aprovar cadastros', 'Aprova ou recusa cadastros, documentos e certificações.', 13),
    ('dados_pessoais', 'Operação', 'Dados pessoais completos', 'CPF, nascimento e documentos sem máscara.', 14),
    ('pedidos', 'Operação', 'Pedidos e pagamentos', 'Pedidos, Pagamentos e a fila Precisa de atenção.', 15),
    ('emergencias', 'Operação', 'Emergências e plantão', 'Emergências e a tela Horário, plantão e prazos.', 16),
    ('garantia', 'Operação', 'Garantia iService', 'Registra e media reclamações.', 17),
    ('garantia_decidir', 'Operação', 'Fechar reclamações', 'Fecha e reabre reclamações da Garantia.', 18),
    ('avaliacoes', 'Operação', 'Avaliações', 'Vê as avaliações e o ranking.', 19),
    ('avaliacoes_moderar', 'Operação', 'Ocultar avaliações', 'Esconde avaliações que quebram as regras.', 20),
    ('denuncias', 'Operação', 'Denúncias', 'Denúncias e avaliações suspeitas.', 21),
    ('pessoas', 'Operação', 'Pessoas', 'Consulta as contas de clientes e profissionais.', 22),
    ('pessoas_suspender', 'Operação', 'Suspender contas', 'Suspende e adverte contas.', 23),
    ('caixa', 'Financeiro', 'Caixa', 'Receitas da plataforma: taxas, assinaturas, tarifas, líquido e cadastros pagantes.', 25),
    ('comercial', 'Financeiro', 'Comercial', 'Lista de profissionais que ainda não assinam, com contato, movimento e prioridade para abordar.', 26),
    ('relatorios', 'Crescimento', 'Relatórios', 'Relatórios e indicadores.', 30),
    ('captacao', 'Crescimento', 'Captação', 'Funil de cadastros, metas por profissão e quem indicou.', 31),
    ('crescimento', 'Crescimento', 'Buscas, site e sugestões', 'Buscas e mapa, Site e downloads e Sugestões de profissões.', 32),
    ('comunicados', 'Crescimento', 'Comunicados e Central de Ajuda', 'Manda comunicados e edita a Central de Ajuda.', 33),
    ('catalogo', 'Catálogo', 'Profissões e regiões', 'Cria e altera profissões, especialidades e regiões.', 40),
    ('precos', 'Catálogo', 'Preços e mínimos', 'Ajusta preços de referência e valores mínimos.', 41),
    ('configuracoes', 'Catálogo', 'Configurações', 'Configurações gerais da plataforma.', 42),
    ('equipe', 'Equipe', 'Ver a equipe', 'Abre a tela Equipe.', 50),
    ('equipe_gerir', 'Equipe', 'Convidar e remover', 'Convida, remove e muda o cargo de quem está abaixo.', 51),
    ('registro', 'Equipe', 'Registro da equipe', 'Vê o que o próprio time fez no painel.', 52),
    ('registro_completo', 'Equipe', 'Registro completo', 'Vê o que todos fizeram no painel.', 53),
    ('cargos', 'Equipe', 'Cargos e permissões', 'Edita o que cada cargo e cada pessoa acessa.', 54)
  ) as t(chave, grupo, nome, descricao, ordem)
$$;

-- Se o dono já personalizou o cargo Gerente, ele ganha o Caixa também (o gerente tem tudo).
update public.cargo_acessos set permissoes = array_append(permissoes, 'caixa'), atualizado_em = now()
where cargo = 'gerente' and not ('caixa' = any (permissoes));
update public.cargo_acessos set permissoes = array_append(permissoes, 'comercial'), atualizado_em = now()
where cargo = 'gerente' and not ('comercial' = any (permissoes));

-- ---------------------------------------------------------------------------
-- 2. Assinaturas VIP/Premium (prontas, ainda sem cobrança)
-- ---------------------------------------------------------------------------
create table if not exists public.assinaturas (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  plano text not null check (plano in ('vip', 'premium')),
  status text not null default 'ativa' check (status in ('ativa', 'atrasada', 'cancelada', 'encerrada')),
  valor_mensal numeric(10, 2) not null check (valor_mensal >= 0),
  inicio timestamptz not null default now(),
  fim timestamptz,
  asaas_assinatura_id text unique,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index if not exists assinaturas_uma_ativa on public.assinaturas (profissional_id) where status in ('ativa', 'atrasada');
alter table public.assinaturas enable row level security;
revoke all on public.assinaturas from anon, authenticated;
grant select on public.assinaturas to authenticated;
drop policy if exists "assinaturas: o profissional vê a sua" on public.assinaturas;
create policy "assinaturas: o profissional vê a sua" on public.assinaturas for select to authenticated
  using (profissional_id = auth.uid() or public.pode('caixa'));

-- Cada mensalidade cobrada.
create table if not exists public.assinatura_cobrancas (
  id uuid primary key default gen_random_uuid(),
  assinatura_id uuid not null references public.assinaturas (id) on delete cascade,
  referencia date not null,
  status text not null default 'aguardando' check (status in ('aguardando', 'paga', 'estornada', 'cancelada', 'falhou')),
  valor numeric(10, 2) not null check (valor > 0),
  tarifa_asaas numeric(10, 2),
  asaas_cobranca_id text unique,
  pago_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (assinatura_id, referencia)
);
alter table public.assinatura_cobrancas enable row level security;
revoke all on public.assinatura_cobrancas from anon, authenticated;

-- Tarifa real do Asaas na cobrança do pedido, quando o Asaas informar (sem ela, vale a estimativa).
alter table public.pagamentos add column if not exists tarifa_asaas numeric(10, 2);

-- ---------------------------------------------------------------------------
-- 3. Estimativa de tarifas e meta
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao) values
  ('caixa_tarifa_fixa', '1.99'::jsonb, 'Caixa: tarifa estimada do Asaas por cobrança recebida, em reais (Pix). Usada enquanto o Asaas não informa a tarifa real.'),
  ('caixa_tarifa_percentual', '0'::jsonb, 'Caixa: parte da tarifa estimada do Asaas em % do valor cobrado (cartão). 0 para só Pix.'),
  ('caixa_meta_mensal', '0'::jsonb, 'Caixa: meta de receita líquida por mês, em reais. 0 = sem meta.')
on conflict (chave) do nothing;

create or replace function public.caixa_config(p_chave text, p_padrao numeric)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(valor) = 'number' then (valor #>> '{}')::numeric
    when jsonb_typeof(valor) = 'string' and (valor #>> '{}') ~ '^[0-9]+([.,][0-9]+)?$' then replace(valor #>> '{}', ',', '.')::numeric end
    from public.app_config where chave = p_chave), p_padrao)
$$;
revoke all on function public.caixa_config(text, numeric) from public, anon, authenticated;

-- Todos os lançamentos de receita (uma linha por taxa recebida ou mensalidade paga).
create or replace function public.caixa_lancamentos(p_inicio date, p_fim date)
returns table (quando timestamptz, tipo text, descricao text, pessoa text, bruto numeric, tarifa numeric, estimada boolean, liquido numeric)
language sql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
  with cfg as (select public.caixa_config('caixa_tarifa_fixa', 1.99) fixa, public.caixa_config('caixa_tarifa_percentual', 0) pct),
  taxas as (
    select g.liberado_em quando, 'taxa'::text tipo,
      'Taxa de serviço do pedido #' || p.codigo descricao,
      coalesce(c.nome, 'Cliente') || ' → ' || coalesce(pf.nome, 'Profissional') pessoa,
      g.valor_plataforma bruto,
      coalesce(g.tarifa_asaas, round(cfg.fixa + g.valor * cfg.pct / 100, 2)) tarifa,
      g.tarifa_asaas is null estimada
    from public.pagamentos g
    join public.pedidos p on p.id = g.pedido_id
    left join public.perfis c on c.id = p.cliente_id
    left join public.perfis pf on pf.id = p.profissional_id
    cross join cfg
    where g.status = 'liberado' and g.valor_plataforma > 0
      and g.liberado_em >= p_inicio and g.liberado_em < p_fim + 1),
  mensalidades as (
    select k.pago_em, 'assinatura'::text,
      'Assinatura ' || case a.plano when 'vip' then 'VIP' else 'Premium' end || ' · ' || to_char(k.referencia, 'MM/YYYY'),
      coalesce(pf.nome, 'Profissional'),
      k.valor,
      coalesce(k.tarifa_asaas, round(cfg.fixa + k.valor * cfg.pct / 100, 2)),
      k.tarifa_asaas is null
    from public.assinatura_cobrancas k
    join public.assinaturas a on a.id = k.assinatura_id
    left join public.perfis pf on pf.id = a.profissional_id
    cross join cfg
    where k.status = 'paga' and k.pago_em >= p_inicio and k.pago_em < p_fim + 1)
  select t.*, t.bruto - t.tarifa from (select * from taxas union all select * from mensalidades) t
$$;
revoke all on function public.caixa_lancamentos(date, date) from public, anon, authenticated;

-- Indicadores de um mês: resultado (dinheiro e serviços) e prospecção (quem chegou).
create or replace function public.caixa_mes(p_mes date)
returns jsonb
language sql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
  with lim as (select date_trunc('month', p_mes)::date ini, (date_trunc('month', p_mes) + interval '1 month')::date fim),
  l as (select x.* from lim, public.caixa_lancamentos(lim.ini, lim.fim - 1) x)
  select jsonb_build_object(
    'mes', (select ini from lim),
    -- Resultado
    'taxas', coalesce((select sum(bruto) from l where tipo = 'taxa'), 0),
    'assinaturas', coalesce((select sum(bruto) from l where tipo = 'assinatura'), 0),
    'tarifas', coalesce((select sum(tarifa) from l), 0),
    'liquido', coalesce((select sum(liquido) from l), 0),
    'pedidos_pagos', (select count(*) from l where tipo = 'taxa'),
    'valor_servicos', coalesce((select sum(g.valor) from public.pagamentos g, lim where g.status = 'liberado' and g.liberado_em >= lim.ini and g.liberado_em < lim.fim), 0),
    'pedidos_feitos', (select count(*) from public.pedidos p, lim where p.criado_em >= lim.ini and p.criado_em < lim.fim),
    'servicos_concluidos', (select count(*) from public.pedidos p, lim where p.status = 'concluido' and p.concluido_em >= lim.ini and p.concluido_em < lim.fim),
    'assinantes', (select count(*) from public.assinaturas a, lim where a.inicio < lim.fim and (a.fim is null or a.fim >= lim.fim)),
    -- Prospecção
    'visitas_site', (select count(*) from public.site_eventos e, lim where e.tipo = 'visita' and e.dia >= lim.ini and e.dia < lim.fim),
    'clientes_novos', (select count(*) from public.perfis pe, lim where pe.e_cliente and not coalesce(pe.e_admin, false) and pe.criado_em >= lim.ini and pe.criado_em < lim.fim),
    'clientes_primeiro_pedido', (select count(*) from (select p.cliente_id, min(p.criado_em) primeiro from public.pedidos p group by p.cliente_id) x, lim
      where x.primeiro >= lim.ini and x.primeiro < lim.fim),
    'profissionais_novos', (select count(*) from public.profissionais pr, lim where pr.criado_em >= lim.ini and pr.criado_em < lim.fim),
    'profissionais_aprovados', (select count(*) from public.profissionais pr, lim where pr.aprovado_em >= lim.ini and pr.aprovado_em < lim.fim),
    'assinantes_novos', (select count(*) from public.assinaturas a, lim where a.inicio >= lim.ini and a.inicio < lim.fim),
    'assinaturas_canceladas', (select count(*) from public.assinaturas a, lim where a.status in ('cancelada', 'encerrada') and a.fim >= lim.ini and a.fim < lim.fim)
  )
$$;
revoke all on function public.caixa_mes(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. A aba Caixa
-- ---------------------------------------------------------------------------
create or replace function public.admin_caixa(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_ini date := coalesce(p_inicio, date_trunc('month', now())::date);
  v_fim date := least(coalesce(p_fim, now()::date), now()::date);
  v_dias integer;
  v_mes date := date_trunc('month', now())::date;
begin
  perform public.exigir_permissao('caixa');
  if p_fim < p_inicio then perform public.erro('periodo_invalido', 'A data final vem antes da inicial.'); end if;
  v_ini := least(v_ini, v_fim);
  if v_fim - v_ini > 800 then perform public.erro('periodo_invalido', 'Escolha um período de até 2 anos.'); end if;
  v_dias := v_fim - v_ini + 1;

  return jsonb_build_object(
    'inicio', v_ini, 'fim', v_fim,
    'pagamento_ativo', public.pagamento_ativo(),
    'assinaturas_ativas', exists (select 1 from public.assinaturas),
    'tarifa_fixa', public.caixa_config('caixa_tarifa_fixa', 1.99),
    'tarifa_percentual', public.caixa_config('caixa_tarifa_percentual', 0),
    'meta_mensal', public.caixa_config('caixa_meta_mensal', 0),

    -- Totais do período e do período anterior de mesmo tamanho.
    'atual', (select jsonb_build_object(
        'taxas', coalesce(sum(bruto) filter (where tipo = 'taxa'), 0),
        'assinaturas', coalesce(sum(bruto) filter (where tipo = 'assinatura'), 0),
        'bruto', coalesce(sum(bruto), 0), 'tarifas', coalesce(sum(tarifa), 0), 'liquido', coalesce(sum(liquido), 0),
        'pedidos_pagos', count(*) filter (where tipo = 'taxa'), 'mensalidades', count(*) filter (where tipo = 'assinatura'),
        'tarifa_estimada', bool_or(estimada))
      from public.caixa_lancamentos(v_ini, v_fim)),
    'anterior', (select jsonb_build_object(
        'taxas', coalesce(sum(bruto) filter (where tipo = 'taxa'), 0),
        'assinaturas', coalesce(sum(bruto) filter (where tipo = 'assinatura'), 0),
        'bruto', coalesce(sum(bruto), 0), 'tarifas', coalesce(sum(tarifa), 0), 'liquido', coalesce(sum(liquido), 0))
      from public.caixa_lancamentos(v_ini - v_dias, v_ini - 1)),

    -- Ainda não entrou: taxas de pedidos pagos que esperam o fim do serviço, e estornos do período.
    'a_receber', (select coalesce(sum(valor_plataforma), 0) from public.pagamentos where status in ('pago', 'a_liberar')),
    'estornado', (select coalesce(sum(estornado_valor), 0) from public.pagamentos
      where status = 'estornado' and atualizado_em >= v_ini and atualizado_em < v_fim + 1),
    'mes_atual_liquido', (select coalesce(sum(liquido), 0) from public.caixa_lancamentos(v_mes, now()::date)),

    -- Indicadores de resultado e prospecção dos últimos 12 meses até o fim do período.
    'por_mes', (select jsonb_agg(public.caixa_mes(m.mes) order by m.mes)
      from (select generate_series(date_trunc('month', v_fim) - interval '11 months', date_trunc('month', v_fim), interval '1 month')::date mes) m),

    -- Cadastros ativos: quem paga e quem não paga.
    'cadastros', (select jsonb_build_object(
        'profissionais_aprovados', count(*) filter (where pr.status = 'aprovado'),
        'profissionais_vip', count(*) filter (where pr.status = 'aprovado' and a.plano = 'vip'),
        'profissionais_premium', count(*) filter (where pr.status = 'aprovado' and a.plano = 'premium'),
        'profissionais_atrasados', count(*) filter (where pr.status = 'aprovado' and a.status = 'atrasada'),
        'profissionais_gratis', count(*) filter (where pr.status = 'aprovado' and a.id is null),
        'profissionais_em_analise', count(*) filter (where pr.status = 'em_analise'),
        'profissionais_preenchendo', count(*) filter (where pr.status = 'rascunho'),
        'profissionais_suspensos', count(*) filter (where pr.status = 'suspenso'))
      from public.profissionais pr
      join public.perfis pe on pe.id = pr.id and pe.excluido_em is null and not coalesce(pe.e_admin, false)
      left join public.assinaturas a on a.profissional_id = pr.id and a.status in ('ativa', 'atrasada')),
    'clientes', (select jsonb_build_object(
        'ativos', count(*),
        'ja_pagaram', count(*) filter (where exists (select 1 from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
          where p.cliente_id = pe.id and g.status in ('pago', 'a_liberar', 'liberado'))),
        'pagaram_no_periodo', count(*) filter (where exists (select 1 from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
          where p.cliente_id = pe.id and g.status in ('pago', 'a_liberar', 'liberado') and g.pago_em >= v_ini and g.pago_em < v_fim + 1)),
        'pediram_sem_pagar', count(*) filter (where exists (select 1 from public.pedidos p where p.cliente_id = pe.id)
          and not exists (select 1 from public.pagamentos g join public.pedidos p on p.id = g.pedido_id
            where p.cliente_id = pe.id and g.status in ('pago', 'a_liberar', 'liberado'))))
      from public.perfis pe
      where pe.e_cliente and pe.excluido_em is null and pe.suspenso_em is null and not coalesce(pe.e_admin, false)),

    'lancamentos', coalesce((select jsonb_agg(to_jsonb(l) order by l.quando desc)
      from (select * from public.caixa_lancamentos(v_ini, v_fim) order by quando desc limit 500) l), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_caixa(date, date) from public, anon;
grant execute on function public.admin_caixa(date, date) to authenticated;

-- Planilha completa do período (sem o limite de 500 da tela).
create or replace function public.admin_caixa_planilha(p_inicio date, p_fim date)
returns setof jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('caixa');
  return query select to_jsonb(l) from public.caixa_lancamentos(p_inicio, p_fim) l order by l.quando;
end;
$$;
revoke all on function public.admin_caixa_planilha(date, date) from public, anon;
grant execute on function public.admin_caixa_planilha(date, date) to authenticated;

-- Meta e estimativa de tarifas, editadas na própria aba Caixa.
create or replace function public.admin_caixa_ajustes(p_meta numeric, p_tarifa_fixa numeric, p_tarifa_percentual numeric)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_antes jsonb;
begin
  perform public.exigir_permissao('caixa');
  if p_meta < 0 or p_meta > 100000000 or p_tarifa_fixa < 0 or p_tarifa_fixa > 100 or p_tarifa_percentual < 0 or p_tarifa_percentual > 20 then
    perform public.erro('valor_invalido', 'Confira os valores: meta a partir de zero, tarifa fixa até R$ 100 e percentual até 20%.');
  end if;
  v_antes := jsonb_build_object('meta', public.caixa_config('caixa_meta_mensal', 0),
    'tarifa_fixa', public.caixa_config('caixa_tarifa_fixa', 1.99), 'tarifa_percentual', public.caixa_config('caixa_tarifa_percentual', 0));
  update public.app_config set valor = to_jsonb(round(coalesce(p_meta, 0), 2)), atualizado_em = now() where chave = 'caixa_meta_mensal';
  update public.app_config set valor = to_jsonb(round(coalesce(p_tarifa_fixa, 0), 2)), atualizado_em = now() where chave = 'caixa_tarifa_fixa';
  update public.app_config set valor = to_jsonb(round(coalesce(p_tarifa_percentual, 0), 2)), atualizado_em = now() where chave = 'caixa_tarifa_percentual';
  perform public.registrar_acao('caixa_ajustes', null, jsonb_build_object('antes', v_antes,
    'depois', jsonb_build_object('meta', round(coalesce(p_meta, 0), 2), 'tarifa_fixa', round(coalesce(p_tarifa_fixa, 0), 2),
      'tarifa_percentual', round(coalesce(p_tarifa_percentual, 0), 2))));
end;
$$;
revoke all on function public.admin_caixa_ajustes(numeric, numeric, numeric) from public, anon;
grant execute on function public.admin_caixa_ajustes(numeric, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Página Comercial: quem ainda não assina, com tudo para a equipe comercial abordar
-- ---------------------------------------------------------------------------
create or replace function public.admin_comercial()
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_30 timestamptz := now() - interval '30 days';
begin
  perform public.exigir_permissao('comercial');
  return (
  with base as (
    select pr.id, pe.nome, pe.email, pe.telefone, pe.foto_url, pe.criado_em cadastro_em, pr.aprovado_em,
      pr.regiao_id, r.nome regiao, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos, pr.pedidos_recebidos, pr.pedidos_aceitos,
      pr.disponivel, pr.verificado, coalesce(pr.atende_24h, false) atende_24h, pr.area_raio_km,
      u.last_sign_in_at ultimo_acesso,
      a.plano plano_atual, a.status assinatura_status,
      (select max(x.fim) from public.assinaturas x where x.profissional_id = pr.id and x.status in ('cancelada', 'encerrada')) ex_assinante_ate,
      (select string_agg(pf.nome, ', ' order by pp.principal desc, pf.nome) from public.profissional_profissoes pp
        join public.profissoes pf on pf.id = pp.profissao_id where pp.profissional_id = pr.id) profissoes,
      (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id order by pp.principal desc limit 1) profissao_principal,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.criado_em >= v_30) pedidos_30d,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.status = 'concluido' and p.concluido_em >= v_30) concluidos_30d,
      (select coalesce(sum(p.valor_cobrado), 0) from public.pedidos p where p.profissional_id = pr.id and p.status = 'concluido' and p.concluido_em >= v_30) ganhos_30d,
      (select count(*) from public.buscas b where b.criada_em >= v_30 and b.regiao_id is not distinct from pr.regiao_id
        and b.profissao_id in (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id)) buscas_30d
    from public.profissionais pr
    join public.perfis pe on pe.id = pr.id and pe.excluido_em is null and pe.suspenso_em is null and not coalesce(pe.e_admin, false)
    left join public.regioes r on r.id = pr.regiao_id
    left join auth.users u on u.id = pr.id
    left join public.assinaturas a on a.profissional_id = pr.id and a.status in ('ativa', 'atrasada')
    where pr.status = 'aprovado'),
  pont as (
    select b.*,
      least(40, b.pedidos_30d * 5)
      + case when b.total_avaliacoes >= 3 and b.nota_media >= 4.5 then 15 when b.total_avaliacoes >= 1 and b.nota_media >= 4 then 8 else 0 end
      + least(20, b.buscas_30d)
      + case when b.ultimo_acesso >= now() - interval '7 days' then 15 when b.ultimo_acesso >= v_30 then 7 else 0 end
      + case when b.disponivel then 10 else 0 end pontos
    from base b)
  select jsonb_build_object(
    'resumo', (select jsonb_build_object(
        'aprovados', count(*),
        'assinantes', count(*) filter (where plano_atual is not null),
        'vip', count(*) filter (where plano_atual = 'vip'),
        'premium', count(*) filter (where plano_atual = 'premium'),
        'atrasados', count(*) filter (where assinatura_status = 'atrasada'),
        'nao_assinantes', count(*) filter (where plano_atual is null),
        'ex_assinantes', count(*) filter (where plano_atual is null and ex_assinante_ate is not null),
        'quentes', count(*) filter (where plano_atual is null and pontos >= 50),
        'mornos', count(*) filter (where plano_atual is null and pontos >= 25 and pontos < 50),
        'frios', count(*) filter (where plano_atual is null and pontos < 25),
        'sem_acesso_30d', count(*) filter (where plano_atual is null and (ultimo_acesso is null or ultimo_acesso < v_30)))
      from pont),
    'funil', (select jsonb_build_object(
        'preenchendo', count(*) filter (where pr.status = 'rascunho'),
        'em_analise', count(*) filter (where pr.status = 'em_analise'),
        'aprovados', count(*) filter (where pr.status = 'aprovado'),
        'clientes', (select count(*) from public.perfis c where c.e_cliente and c.excluido_em is null and not coalesce(c.e_admin, false)))
      from public.profissionais pr join public.perfis pe on pe.id = pr.id and pe.excluido_em is null),
    'por_profissao', coalesce((select jsonb_agg(x order by x.nao_assinantes desc, x.nome) from (
        select pf.id, pf.nome,
          count(distinct b.id) aprovados,
          count(distinct b.id) filter (where b.plano_atual is not null) assinantes,
          count(distinct b.id) filter (where b.plano_atual is null) nao_assinantes,
          count(distinct b.id) filter (where b.plano_atual is null and b.pontos >= 50) quentes,
          (select count(*) from public.buscas s where s.profissao_id = pf.id and s.criada_em >= v_30) buscas_30d,
          (select count(*) from public.buscas s where s.profissao_id = pf.id and s.criada_em >= v_30 and s.resultados = 0) sem_resultado_30d
        from public.profissoes pf
        left join public.profissional_profissoes pp on pp.profissao_id = pf.id
        left join pont b on b.id = pp.profissional_id
        where pf.ativa
        group by pf.id, pf.nome) x), '[]'::jsonb),
    'por_regiao', coalesce((select jsonb_agg(x order by x.ordem) from (
        select r.id, r.nome, r.ordem,
          count(b.id) aprovados,
          count(b.id) filter (where b.plano_atual is not null) assinantes,
          count(b.id) filter (where b.plano_atual is null) nao_assinantes,
          count(b.id) filter (where b.plano_atual is null and b.pontos >= 50) quentes,
          (select count(*) from public.buscas s where s.regiao_id = r.id and s.criada_em >= v_30) buscas_30d,
          (select count(*) from public.buscas s where s.regiao_id = r.id and s.criada_em >= v_30 and s.resultados = 0) sem_resultado_30d
        from public.regioes r
        left join pont b on b.regiao_id = r.id
        group by r.id, r.nome, r.ordem) x), '[]'::jsonb),
    'oportunidades', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'nome', b.nome, 'email', b.email, 'telefone', b.telefone, 'foto_url', b.foto_url,
        'profissoes', b.profissoes, 'regiao', b.regiao, 'nota', b.nota_media, 'avaliacoes', b.total_avaliacoes,
        'servicos', b.servicos_concluidos,
        'aceite', case when b.pedidos_recebidos > 0 then round(100.0 * b.pedidos_aceitos / b.pedidos_recebidos) end,
        'pedidos_30d', b.pedidos_30d, 'concluidos_30d', b.concluidos_30d, 'ganhos_30d', b.ganhos_30d, 'buscas_30d', b.buscas_30d,
        'disponivel', b.disponivel, 'verificado', b.verificado, 'atende_24h', b.atende_24h, 'raio_km', b.area_raio_km,
        'aprovado_em', b.aprovado_em, 'cadastro_em', b.cadastro_em, 'ultimo_acesso', b.ultimo_acesso,
        'ex_assinante_ate', b.ex_assinante_ate, 'pontos', b.pontos,
        'prioridade', case when b.pontos >= 50 then 'quente' when b.pontos >= 25 then 'morno' else 'frio' end,
        'plano_sugerido', case when b.area_raio_km > 20 or b.pedidos_30d >= 8 or b.buscas_30d >= 15 then 'premium' else 'vip' end,
        'argumento', concat_ws(' ',
          case when b.ex_assinante_ate is not null then 'Já foi assinante: oferecer a volta.' end,
          case when b.pedidos_30d >= 3 then b.pedidos_30d || ' pedidos em 30 dias: com mais alcance, recebe mais.' end,
          case when b.buscas_30d >= 5 then b.buscas_30d || ' buscas na profissão e região dele em 30 dias.' end,
          case when b.total_avaliacoes >= 3 and b.nota_media >= 4.5 then 'Nota alta: aparece no topo para mais clientes.' end,
          case when b.ganhos_30d > 0 then 'Faturou R$ ' || replace(to_char(b.ganhos_30d, 'FM9999990.00'), '.', ',') || ' em 30 dias pela plataforma.' end,
          case when b.ultimo_acesso is null or b.ultimo_acesso < v_30 then 'Sem entrar há mais de 30 dias: reativar antes de vender.' end,
          case when b.pedidos_30d = 0 and b.buscas_30d < 5 then 'Pouco movimento: mostrar o alcance maior das assinaturas.' end))
      order by b.pontos desc, b.pedidos_30d desc, b.nome)
      from pont b where b.plano_atual is null), '[]'::jsonb)
  )
  from (select 1) um);
end;
$$;
revoke all on function public.admin_comercial() from public, anon;
grant execute on function public.admin_comercial() to authenticated;

-- Quem abriu a lista com contatos fica no Registro (um por dia por pessoa).
create or replace function public.admin_comercial_registrar(p_acao text, p_profissional uuid default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('comercial');
  if p_acao not in ('baixar_lista', 'contato') then perform public.erro('acao_invalida', 'Ação desconhecida.'); end if;
  perform public.registrar_acao('comercial_' || p_acao, p_profissional::text, '{}'::jsonb);
end;
$$;
revoke all on function public.admin_comercial_registrar(text, uuid) from public, anon;
grant execute on function public.admin_comercial_registrar(text, uuid) to authenticated;
