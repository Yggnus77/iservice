-- Tempo de trabalho (pedido do usuário em 14/11/2026).
-- O relógio do serviço começa quando o profissional aceita um pedido para agora/hoje. Nos pedidos
-- marcados para outro dia (até 7 dias), começa quando ele toca em "Estou a caminho" (senão contaria
-- os dias de espera). Para ao tocar em "Concluir". Cada pedido guarda os minutos, e o profissional
-- soma as horas trabalhadas, que aparecem no perfil público. Limite de 16 h por pedido para que um
-- esquecimento de concluir não infle o total.

alter table public.pedidos add column if not exists minutos_trabalhados integer;
alter table public.profissionais add column if not exists minutos_trabalhados integer not null default 0;

create or replace function public.inicio_do_trabalho(p public.pedidos)
returns timestamptz
language sql immutable
as $$
  select case when p.quando = 'combinado' then coalesce(p.a_caminho_em, p.iniciado_em, p.aceito_em)
              else coalesce(p.aceito_em, p.a_caminho_em, p.iniciado_em) end
$$;

create or replace function public.contar_tempo_de_trabalho()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_inicio timestamptz;
begin
  if new.status = 'concluido' and old.status is distinct from 'concluido' and new.concluido_em is not null then
    v_inicio := public.inicio_do_trabalho(new);
    if v_inicio is not null then
      new.minutos_trabalhados := least(960, greatest(1, ceil(extract(epoch from (new.concluido_em - v_inicio)) / 60)::int));
      update public.profissionais set minutos_trabalhados = minutos_trabalhados + new.minutos_trabalhados
      where id = new.profissional_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists contar_tempo_de_trabalho on public.pedidos;
create trigger contar_tempo_de_trabalho before update of status on public.pedidos
  for each row execute function public.contar_tempo_de_trabalho();

-- Pedidos já concluídos antes desta mudança.
update public.pedidos p set minutos_trabalhados = least(960, greatest(1, ceil(extract(epoch from (p.concluido_em - public.inicio_do_trabalho(p))) / 60)::int))
where p.status = 'concluido' and p.minutos_trabalhados is null and p.concluido_em is not null and public.inicio_do_trabalho(p) is not null;
update public.profissionais pr set minutos_trabalhados = coalesce((
  select sum(p.minutos_trabalhados) from public.pedidos p where p.profissional_id = pr.id and p.status = 'concluido'), 0);

-- Perfil público passa a mostrar as horas trabalhadas.
create or replace function public.perfil_profissional(p_id uuid)
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'id', pr.id,
    'nome', pe.nome,
    'foto_url', pe.foto_url,
    'bio', pr.bio,
    'anos_experiencia', pr.anos_experiencia,
    'verificado', pr.verificado,
    'disponivel', pr.disponivel and not public.em_atendimento(pr.id),
    'nota_media', pr.nota_media,
    'total_avaliacoes', pr.total_avaliacoes,
    'servicos_concluidos', pr.servicos_concluidos,
    'minutos_trabalhados', pr.minutos_trabalhados,
    -- "Costuma responder em X min": só com respostas suficientes para ser justo.
    'tempo_resposta_seg', case when pr.respostas_medidas >= public.cfg_num('min_respostas_tempo', 3) then pr.tempo_resposta_seg end,
    'novo', pr.total_avaliacoes < public.cfg_num('min_avaliacoes_ranking', 5),
    'regiao', (select r.nome from public.regioes r where r.id = pr.regiao_id),
    'membro_desde', pr.aprovado_em,
    'favorito', exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    'profissoes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'nome', f.nome, 'icone', f.icone,
        'especialidades', coalesce((
          select jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'preco', x.preco, 'cobranca', x.cobranca) order by e.ordem, e.nome)
          from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
          where x.profissional_id = pr.id and e.profissao_id = f.id), '[]'::jsonb)
      ) order by pp.principal desc, f.ordem)
      from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
      where pp.profissional_id = pr.id), '[]'::jsonb),
    'certificacoes', coalesce((
      select jsonb_agg(jsonb_build_object('nome', c.nome, 'instituicao', c.instituicao, 'profissao_id', c.profissao_id))
      from public.certificacoes c where c.profissional_id = pr.id and c.status = 'aprovado'), '[]'::jsonb),
    'portfolio', coalesce((
      select jsonb_agg(jsonb_build_object('id', po.id, 'descricao', po.descricao, 'antes_path', po.antes_path, 'depois_path', po.depois_path) order by po.ordem, po.id)
      from public.portfolio po where po.profissional_id = pr.id), '[]'::jsonb),
    'avaliacoes_recentes', coalesce((
      select jsonb_agg(a) from (
        select jsonb_build_object('pedido_id', av.pedido_id, 'nota', av.nota, 'comentario', av.comentario, 'fotos', av.fotos, 'resposta', av.resposta,
          'criada_em', av.criada_em, 'cliente_nome', split_part(c.nome, ' ', 1), 'cliente_foto', c.foto_url) as a
        from public.avaliacoes av join public.perfis c on c.id = av.cliente_id
        where av.profissional_id = pr.id and not av.oculta order by av.criada_em desc limit 10) s), '[]'::jsonb),
    'distribuicao_notas', (
      select jsonb_build_object('5', count(*) filter (where nota = 5), '4', count(*) filter (where nota = 4),
        '3', count(*) filter (where nota = 3), '2', count(*) filter (where nota = 2), '1', count(*) filter (where nota = 1))
      from public.avaliacoes where profissional_id = pr.id and not oculta)
  )
  from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where pr.id = p_id and (pr.status = 'aprovado' or pr.id = auth.uid() or public.e_admin())
$$;

-- ---------------------------------------------------------------------------
-- O profissional também avalia o cliente (pedido do usuário em 14/11/2026).
-- Nota de 1 a 5 estrelas e um comentário que só a equipe vê. A média vira a "nota como cliente",
-- que o profissional vê antes de atender e o próprio cliente vê no perfil dele.
-- ---------------------------------------------------------------------------
alter table public.perfis add column if not exists nota_cliente numeric(3, 2) not null default 0;
alter table public.perfis add column if not exists avaliacoes_cliente integer not null default 0;

create table if not exists public.avaliacoes_cliente (
  pedido_id uuid primary key references public.pedidos (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  cliente_id uuid not null references public.perfis (id) on delete cascade,
  nota smallint not null check (nota between 1 and 5),
  comentario text check (char_length(comentario) <= 1000),
  criada_em timestamptz not null default now()
);
create index if not exists avaliacoes_cliente_cliente_idx on public.avaliacoes_cliente (cliente_id, criada_em desc);
alter table public.avaliacoes_cliente enable row level security;
revoke all on public.avaliacoes_cliente from anon, authenticated;
grant select on public.avaliacoes_cliente to authenticated;
drop policy if exists "avaliacoes_cliente: autor e equipe leem" on public.avaliacoes_cliente;
create policy "avaliacoes_cliente: autor e equipe leem" on public.avaliacoes_cliente for select to authenticated
  using (profissional_id = auth.uid() or public.e_admin());

create or replace function public.avaliar_cliente(p_pedido uuid, p_nota smallint, p_comentario text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
begin
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid();
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status <> 'concluido' then perform public.erro('nao_concluido', 'Só é possível avaliar serviços concluídos.'); end if;
  if v_ped.concluido_em < now() - interval '30 days' then perform public.erro('prazo_avaliacao', 'O prazo para avaliar este cliente acabou.'); end if;
  if p_nota is null or p_nota not between 1 and 5 then perform public.erro('nota_invalida', 'Escolha de 1 a 5 estrelas.'); end if;
  insert into public.avaliacoes_cliente (pedido_id, profissional_id, cliente_id, nota, comentario)
  values (p_pedido, auth.uid(), v_ped.cliente_id, p_nota, nullif(left(trim(p_comentario), 1000), ''))
  on conflict (pedido_id) do update set nota = excluded.nota, comentario = excluded.comentario;
end;
$$;
revoke all on function public.avaliar_cliente(uuid, smallint, text) from public, anon;
grant execute on function public.avaliar_cliente(uuid, smallint, text) to authenticated;

create or replace function public.recalcular_nota_cliente()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_cli uuid := coalesce(new.cliente_id, old.cliente_id);
begin
  update public.perfis set
    nota_cliente = coalesce((select round(avg(nota)::numeric, 2) from public.avaliacoes_cliente where cliente_id = v_cli), 0),
    avaliacoes_cliente = (select count(*) from public.avaliacoes_cliente where cliente_id = v_cli)
  where id = v_cli;
  return null;
end;
$$;
drop trigger if exists recalcular_nota_cliente on public.avaliacoes_cliente;
create trigger recalcular_nota_cliente after insert or update of nota or delete on public.avaliacoes_cliente
  for each row execute function public.recalcular_nota_cliente();

-- Resumo do cliente de um pedido, para o profissional daquele pedido: nota como cliente e se ele já avaliou.
create or replace function public.resumo_cliente_do_pedido(p_pedido uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'nota_cliente', c.nota_cliente,
    'avaliacoes_cliente', c.avaliacoes_cliente,
    'ja_avaliei', exists (select 1 from public.avaliacoes_cliente a where a.pedido_id = p.id),
    'minha_nota', (select a.nota from public.avaliacoes_cliente a where a.pedido_id = p.id))
  from public.pedidos p join public.perfis c on c.id = p.cliente_id
  where p.id = p_pedido and (p.profissional_id = auth.uid() or public.e_admin())
$$;
revoke all on function public.resumo_cliente_do_pedido(uuid) from public, anon;
grant execute on function public.resumo_cliente_do_pedido(uuid) to authenticated;

-- A nota do próprio cliente, para o perfil dele.
create or replace function public.minha_nota_cliente()
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object('nota_cliente', nota_cliente, 'avaliacoes_cliente', avaliacoes_cliente)
  from public.perfis where id = auth.uid()
$$;
revoke all on function public.minha_nota_cliente() from public, anon;
grant execute on function public.minha_nota_cliente() to authenticated;


-- ---------------------------------------------------------------------------
-- Painel: avaliações nos dois sentidos, com os melhores e os piores avaliados.
-- ---------------------------------------------------------------------------
create or replace function public.admin_ranking_avaliacoes(p_tipo text default 'profissionais', p_ordem text default 'melhores',
  p_min_avaliacoes integer default 1, p_texto text default null, p_limite integer default 50)
returns table (id uuid, nome text, foto_url text, nota numeric, total integer, notas_baixas integer, cinco_estrelas integer,
  servicos integer, minutos_trabalhados integer, ultima_avaliacao timestamptz, situacao text)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if p_tipo = 'clientes' then
    return query
    select pe.id, pe.nome, pe.foto_url, pe.nota_cliente, pe.avaliacoes_cliente,
      (select count(*)::int from public.avaliacoes_cliente a where a.cliente_id = pe.id and a.nota <= 2),
      (select count(*)::int from public.avaliacoes_cliente a where a.cliente_id = pe.id and a.nota = 5),
      (select count(*)::int from public.pedidos p where p.cliente_id = pe.id and p.status = 'concluido'),
      null::int,
      (select max(a.criada_em) from public.avaliacoes_cliente a where a.cliente_id = pe.id),
      null::text
    from public.perfis pe
    where pe.avaliacoes_cliente >= greatest(1, coalesce(p_min_avaliacoes, 1))
      and (p_texto is null or pe.nome ilike '%' || p_texto || '%')
    order by case when p_ordem = 'piores' then pe.nota_cliente end asc,
             case when p_ordem <> 'piores' then pe.nota_cliente end desc,
             pe.avaliacoes_cliente desc
    limit least(coalesce(p_limite, 50), 200);
  else
    return query
    select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes,
      (select count(*)::int from public.avaliacoes a where a.profissional_id = pr.id and a.nota <= 2 and not a.oculta),
      (select count(*)::int from public.avaliacoes a where a.profissional_id = pr.id and a.nota = 5 and not a.oculta),
      pr.servicos_concluidos, pr.minutos_trabalhados,
      (select max(a.criada_em) from public.avaliacoes a where a.profissional_id = pr.id),
      pr.status::text
    from public.profissionais pr join public.perfis pe on pe.id = pr.id
    where pr.total_avaliacoes >= greatest(1, coalesce(p_min_avaliacoes, 1))
      and (p_texto is null or pe.nome ilike '%' || p_texto || '%')
    order by case when p_ordem = 'piores' then pr.nota_media end asc,
             case when p_ordem <> 'piores' then pr.nota_media end desc,
             pr.total_avaliacoes desc
    limit least(coalesce(p_limite, 50), 200);
  end if;
end;
$$;
revoke all on function public.admin_ranking_avaliacoes(text, text, integer, text, integer) from public, anon;
grant execute on function public.admin_ranking_avaliacoes(text, text, integer, text, integer) to authenticated;

-- Avaliações recentes nos dois sentidos: cliente avalia profissional e profissional avalia cliente.
create or replace function public.admin_avaliacoes_recentes(p_direcao text default 'todas', p_so_baixas boolean default false,
  p_dias integer default 30, p_limite integer default 100)
returns table (direcao text, pedido_id uuid, codigo text, nota smallint, comentario text, autor_id uuid, autor text, autor_foto text,
  avaliado_id uuid, avaliado text, avaliado_foto text, minutos_trabalhados integer, oculta boolean, criada_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select * from (
    select 'cliente_avalia'::text, a.pedido_id, p.codigo, a.nota, a.comentario, a.cliente_id, c.nome, c.foto_url,
      a.profissional_id, pf.nome, pf.foto_url, p.minutos_trabalhados, a.oculta, a.criada_em
    from public.avaliacoes a join public.pedidos p on p.id = a.pedido_id
      join public.perfis c on c.id = a.cliente_id join public.perfis pf on pf.id = a.profissional_id
    where coalesce(p_direcao, 'todas') in ('todas', 'cliente_avalia')
    union all
    select 'profissional_avalia'::text, a.pedido_id, p.codigo, a.nota, a.comentario, a.profissional_id, pf.nome, pf.foto_url,
      a.cliente_id, c.nome, c.foto_url, p.minutos_trabalhados, false, a.criada_em
    from public.avaliacoes_cliente a join public.pedidos p on p.id = a.pedido_id
      join public.perfis c on c.id = a.cliente_id join public.perfis pf on pf.id = a.profissional_id
    where coalesce(p_direcao, 'todas') in ('todas', 'profissional_avalia')
  ) x (direcao, pedido_id, codigo, nota, comentario, autor_id, autor, autor_foto, avaliado_id, avaliado, avaliado_foto, minutos_trabalhados, oculta, criada_em)
  where x.criada_em > now() - make_interval(days => coalesce(p_dias, 30))
    and (not coalesce(p_so_baixas, false) or x.nota <= 2)
  order by x.criada_em desc
  limit least(coalesce(p_limite, 100), 300);
end;
$$;
revoke all on function public.admin_avaliacoes_recentes(text, boolean, integer, integer) from public, anon;
grant execute on function public.admin_avaliacoes_recentes(text, boolean, integer, integer) to authenticated;

-- Resumo do painel: médias gerais para os cartões da tela de avaliações.
create or replace function public.admin_resumo_avaliacoes(p_dias integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return jsonb_build_object(
    'media_profissionais', (select round(avg(nota)::numeric, 2) from public.avaliacoes where not oculta and criada_em > now() - make_interval(days => p_dias)),
    'total_profissionais', (select count(*) from public.avaliacoes where not oculta and criada_em > now() - make_interval(days => p_dias)),
    'media_clientes', (select round(avg(nota)::numeric, 2) from public.avaliacoes_cliente where criada_em > now() - make_interval(days => p_dias)),
    'total_clientes', (select count(*) from public.avaliacoes_cliente where criada_em > now() - make_interval(days => p_dias)),
    'baixas', (select count(*) from public.avaliacoes where nota <= 2 and not oculta and criada_em > now() - make_interval(days => p_dias))
            + (select count(*) from public.avaliacoes_cliente where nota <= 2 and criada_em > now() - make_interval(days => p_dias)),
    'horas_trabalhadas', (select coalesce(sum(minutos_trabalhados), 0) / 60 from public.pedidos where status = 'concluido' and concluido_em > now() - make_interval(days => p_dias)),
    'sem_avaliacao', (select count(*) from public.pedidos p where p.status = 'concluido' and p.concluido_em > now() - make_interval(days => p_dias)
                      and not exists (select 1 from public.avaliacoes a where a.pedido_id = p.id))
  );
end;
$$;
revoke all on function public.admin_resumo_avaliacoes(integer) from public, anon;
grant execute on function public.admin_resumo_avaliacoes(integer) to authenticated;
