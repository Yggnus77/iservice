-- Deslocamento pela distância e taxa de serviço do cliente (decisões do usuário em 19/11/2026).
--
-- 1. Deslocamento: todo pedido soma R$ 20 + R$ 1,50 por km entre o profissional e o
--    endereço do cliente (20 km = R$ 50). O cliente vê um valor só, já com o
--    deslocamento; o valor vai todo para o profissional. Editável no painel.
-- 2. Taxa de serviço: 10% pagos pelo cliente sobre o valor do serviço. Fica pronta,
--    mas desligada (taxa_servico_ativa = false) até o pagamento pelo app existir,
--    porque hoje o cliente paga direto ao profissional.

insert into public.app_config (chave, valor, descricao) values
  ('deslocamento_base', '20'::jsonb, 'Parte fixa do deslocamento, em reais, somada a todo pedido. 0 junto com deslocamento_por_km desliga.'),
  ('deslocamento_por_km', '1.5'::jsonb, 'Reais por km entre o profissional e o endereço do cliente, somados ao deslocamento.'),
  ('taxa_servico', '0.1'::jsonb, 'Taxa de serviço paga pelo cliente sobre o valor do serviço (0,1 = 10%).'),
  ('taxa_servico_ativa', 'false'::jsonb, 'Liga a cobrança da taxa de serviço. Só ligar quando o pagamento pelo app estiver funcionando.')
on conflict (chave) do nothing;

alter table public.pedidos add column if not exists deslocamento numeric(10, 2) not null default 0;
alter table public.pedidos add column if not exists taxa_servico numeric(10, 2) not null default 0;

-- Valor do deslocamento para uma distância em km (arredondado a R$ 1).
create or replace function public.valor_deslocamento(p_km numeric)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select case when p_km is null or p_km < 0 then 0
    else round(public.cfg_num('deslocamento_base', 20) + p_km * public.cfg_num('deslocamento_por_km', 1.5)) end
$$;

-- Taxa de serviço sobre um valor (0 enquanto estiver desligada).
create or replace function public.valor_taxa_servico(p_valor numeric)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select case when p_valor is null or p_valor <= 0
      or coalesce((public.cfg('taxa_servico_ativa'))::text, 'false') <> 'true' then 0
    else round(p_valor * public.cfg_num('taxa_servico', 0.1), 2) end
$$;
revoke all on function public.valor_deslocamento(numeric), public.valor_taxa_servico(numeric) from public;
grant execute on function public.valor_deslocamento(numeric), public.valor_taxa_servico(numeric) to anon, authenticated;

-- Deslocamento previsto antes de pedir: distância do profissional até um endereço do cliente.
create or replace function public.deslocamento_previsto(p_profissional uuid, p_endereco_id bigint)
returns numeric
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_km numeric;
begin
  select round((extensions.st_distance(public.centro_publico(pr.area_centro), e.localizacao) / 1000)::numeric, 2) into v_km
  from public.profissionais pr, public.enderecos e
  where pr.id = p_profissional and e.id = p_endereco_id and e.usuario_id = auth.uid() and pr.area_centro is not null;
  return public.valor_deslocamento(v_km);
end;
$$;
revoke all on function public.deslocamento_previsto(uuid, bigint) from public, anon;
grant execute on function public.deslocamento_previsto(uuid, bigint) to authenticated;

-- O banco calcula o deslocamento ao criar o pedido (pela distância gravada nele).
create or replace function public.calcular_deslocamento()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  new.deslocamento := public.valor_deslocamento(new.distancia_km);
  return new;
end;
$$;
revoke all on function public.calcular_deslocamento() from public, anon, authenticated;
drop trigger if exists calcular_deslocamento on public.pedidos;
create trigger calcular_deslocamento before insert on public.pedidos
  for each row execute function public.calcular_deslocamento();

-- Taxa de serviço: sobre o preço com deslocamento e acréscimos. Roda depois dos
-- outros cálculos (os gatilhos rodam em ordem alfabética: "totalizar" vem por último).
create or replace function public.totalizar_taxa_servico()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.preco_informado is null then
    new.taxa_servico := 0;
  else
    new.taxa_servico := public.valor_taxa_servico(new.preco_informado + new.deslocamento + new.taxa_urgencia + new.taxa_fora_horario);
  end if;
  return new;
end;
$$;
revoke all on function public.totalizar_taxa_servico() from public, anon, authenticated;
drop trigger if exists totalizar_taxa_servico on public.pedidos;
create trigger totalizar_taxa_servico before insert or update of quando, janela, combinado_para, preco_informado on public.pedidos
  for each row execute function public.totalizar_taxa_servico();

-- Lista de pedidos: leva o deslocamento e a taxa de serviço também.
drop function if exists public.meus_pedidos(text, text, integer);
create function public.meus_pedidos(p_papel text default 'cliente', p_grupo text default 'todos', p_limite integer default 50)
returns table (
  id uuid, codigo text, status public.status_pedido, quando public.quando_pedido, janela text, combinado_para timestamptz,
  profissao_id text, especialidade text, descricao text, endereco_texto text, distancia_km numeric,
  preco_informado numeric, taxa_urgencia numeric, valor_cobrado numeric, responder_ate timestamptz, criado_em timestamptz,
  concluido_em timestamptz, outra_parte_id uuid, outra_parte_nome text, outra_parte_foto text, avaliado boolean, nao_lidas integer,
  proposta_para timestamptz, taxa_fora_horario numeric, deslocamento numeric, taxa_servico numeric
)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.codigo, p.status, p.quando, p.janela, p.combinado_para, p.profissao_id, e.nome, p.descricao, p.endereco_texto,
    p.distancia_km, p.preco_informado, p.taxa_urgencia, p.valor_cobrado, p.responder_ate, p.criado_em, p.concluido_em,
    o.id, o.nome, o.foto_url,
    exists (select 1 from public.avaliacoes a where a.pedido_id = p.id),
    (select count(*) from public.mensagens m where m.pedido_id = p.id and m.autor_id <> auth.uid() and m.lida_em is null)::int,
    p.proposta_para, p.taxa_fora_horario, p.deslocamento,
    case when p_papel = 'profissional' then 0 else p.taxa_servico end
  from public.pedidos p
  left join public.especialidades e on e.id = p.especialidade_id
  join public.perfis o on o.id = case when p_papel = 'profissional' then p.cliente_id else p.profissional_id end
  where (case when p_papel = 'profissional' then p.profissional_id else p.cliente_id end) = auth.uid()
    and case p_grupo
      when 'andamento' then p.status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento')
      when 'concluidos' then p.status = 'concluido'
      when 'cancelados' then p.status in ('cancelado', 'recusado', 'expirado')
      else true end
  order by p.criado_em desc
  limit p_limite
$$;
revoke all on function public.meus_pedidos(text, text, integer) from public, anon;
grant execute on function public.meus_pedidos(text, text, integer) to authenticated;
