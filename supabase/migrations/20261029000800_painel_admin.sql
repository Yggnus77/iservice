-- Painel administrativo (29/10/2026): requisitos A01 a A09.
--  A01/A02  Fila de cadastros, revisão de cada documento, pedir nova foto, aprovar ou recusar.
--  A03      Suspender e reativar profissional ou cliente (bloqueia o login).
--  A04      Denúncias e avaliações suspeitas (a equipe pode ocultar uma avaliação).
--  A05      Ligar e desligar profissões, especialidades e regiões.
--  A06/A07  Registro das buscas para os números do dia e o mapa de buscas sem resultado.
--  A08      Comunicado para um grupo de profissionais.
--  A09      Tabela de preço de referência, com ajuste manual pela equipe.
--  Também: mediação da garantia iService, emergências e o registro de tudo o que a equipe faz.
--
-- Tudo o que o painel faz passa por funções que conferem e_admin(). Para virar admin:
--   update public.perfis set e_admin = true where email = 'seu-email@exemplo.com';
--
-- ATENÇÃO para migrações futuras: buscar_profissionais agora é só um invólucro que
-- registra a busca. A lógica da busca está em buscar_profissionais_base; mude aquela.

-- ---------------------------------------------------------------------------
-- 0. Base: conferência de admin e registro das ações da equipe
-- ---------------------------------------------------------------------------
create table if not exists public.admin_acoes (
  id bigint generated always as identity primary key,
  admin_id uuid references public.perfis (id) on delete set null,
  acao text not null,
  alvo text,
  dados jsonb not null default '{}',
  criada_em timestamptz not null default now()
);
create index if not exists admin_acoes_criada_idx on public.admin_acoes (criada_em desc);
alter table public.admin_acoes enable row level security;
revoke all on public.admin_acoes from anon, authenticated;
grant select on public.admin_acoes to authenticated;
drop policy if exists "admin_acoes: admin lê" on public.admin_acoes;
create policy "admin_acoes: admin lê" on public.admin_acoes for select to authenticated using (public.e_admin());

create or replace function public.exigir_admin()
returns void
language plpgsql stable
set search_path = public
as $$
begin
  if not public.e_admin() then perform public.erro('sem_permissao', 'Apenas a equipe iService pode fazer isso.'); end if;
end;
$$;

create or replace function public.registrar_acao(p_acao text, p_alvo text, p_dados jsonb default '{}')
returns void
language sql security definer
set search_path = public
as $$ insert into public.admin_acoes (admin_id, acao, alvo, dados) values (auth.uid(), p_acao, p_alvo, coalesce(p_dados, '{}')) $$;

revoke all on function public.exigir_admin(), public.registrar_acao(text, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Colunas novas
-- ---------------------------------------------------------------------------
alter table public.perfis add column if not exists suspenso_em timestamptz;
alter table public.perfis add column if not exists motivo_suspensao text;
alter table public.regioes add column if not exists ativa boolean not null default true;
alter table public.avaliacoes add column if not exists oculta boolean not null default false;
alter table public.avaliacoes add column if not exists motivo_ocultacao text;
alter table public.emergencias add column if not exists atendida_por uuid references public.perfis (id) on delete set null;
alter table public.emergencias add column if not exists nota_atendimento text;

-- ---------------------------------------------------------------------------
-- 2. Catálogo editável pela equipe (A05): profissões, especialidades, regiões e configuração
-- ---------------------------------------------------------------------------
grant insert, update on public.profissoes, public.especialidades, public.regioes, public.app_config, public.certificacoes_sugeridas to authenticated;
grant delete on public.certificacoes_sugeridas to authenticated;

drop policy if exists "profissoes: admin escreve" on public.profissoes;
create policy "profissoes: admin escreve" on public.profissoes for insert to authenticated with check (public.e_admin());
drop policy if exists "profissoes: admin altera" on public.profissoes;
create policy "profissoes: admin altera" on public.profissoes for update to authenticated using (public.e_admin()) with check (public.e_admin());
drop policy if exists "especialidades: admin escreve" on public.especialidades;
create policy "especialidades: admin escreve" on public.especialidades for insert to authenticated with check (public.e_admin());
drop policy if exists "especialidades: admin altera" on public.especialidades;
create policy "especialidades: admin altera" on public.especialidades for update to authenticated using (public.e_admin()) with check (public.e_admin());
drop policy if exists "regioes: admin escreve" on public.regioes;
create policy "regioes: admin escreve" on public.regioes for insert to authenticated with check (public.e_admin());
drop policy if exists "regioes: admin altera" on public.regioes;
create policy "regioes: admin altera" on public.regioes for update to authenticated using (public.e_admin()) with check (public.e_admin());
drop policy if exists "config: admin escreve" on public.app_config;
create policy "config: admin escreve" on public.app_config for insert to authenticated with check (public.e_admin());
drop policy if exists "config: admin altera" on public.app_config;
create policy "config: admin altera" on public.app_config for update to authenticated using (public.e_admin()) with check (public.e_admin());
drop policy if exists "cert sugeridas: admin escreve" on public.certificacoes_sugeridas;
create policy "cert sugeridas: admin escreve" on public.certificacoes_sugeridas for all to authenticated using (public.e_admin()) with check (public.e_admin());

-- Cada alteração do catálogo fica registrada.
create or replace function public.registrar_catalogo()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if public.e_admin() then
    perform public.registrar_acao(lower(tg_op) || '_' || tg_table_name,
      coalesce(to_jsonb(new) ->> 'id', to_jsonb(new) ->> 'chave'),
      jsonb_build_object('antes', case when tg_op = 'UPDATE' then to_jsonb(old) end, 'depois', to_jsonb(new)));
  end if;
  return null;
end;
$$;
revoke all on function public.registrar_catalogo() from public, anon, authenticated;
do $$
declare t text;
begin
  foreach t in array array['profissoes', 'especialidades', 'regioes', 'app_config'] loop
    execute format('drop trigger if exists registrar_catalogo on public.%I', t);
    execute format('create trigger registrar_catalogo after insert or update on public.%I for each row execute function public.registrar_catalogo()', t);
  end loop;
end;
$$;

-- Pedido em região desligada, ou de cliente suspenso, não entra.
create or replace function public.conferir_novo_pedido()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.perfis where id = new.cliente_id and suspenso_em is not null) then
    perform public.erro('conta_suspensa', 'Sua conta está suspensa. Fale com o suporte iService.');
  end if;
  if new.regiao_id is not null and exists (select 1 from public.regioes where id = new.regiao_id and not ativa) then
    perform public.erro('regiao_inativa', 'O iService ainda não atende nessa região.');
  end if;
  if not exists (select 1 from public.profissoes where id = new.profissao_id and ativa) then
    perform public.erro('profissao_inativa', 'Essa profissão está indisponível no momento.');
  end if;
  return new;
end;
$$;
revoke all on function public.conferir_novo_pedido() from public, anon, authenticated;
drop trigger if exists conferir_novo_pedido on public.pedidos;
create trigger conferir_novo_pedido before insert on public.pedidos for each row execute function public.conferir_novo_pedido();

create or replace function public.bloquear_mensagem_suspenso()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.perfis where id = new.autor_id and suspenso_em is not null) then
    perform public.erro('conta_suspensa', 'Sua conta está suspensa. Fale com o suporte iService.');
  end if;
  return new;
end;
$$;
revoke all on function public.bloquear_mensagem_suspenso() from public, anon, authenticated;
drop trigger if exists bloquear_mensagem_suspenso on public.mensagens;
create trigger bloquear_mensagem_suspenso before insert on public.mensagens for each row execute function public.bloquear_mensagem_suspenso();

-- ---------------------------------------------------------------------------
-- 3. Registro das buscas (A06 e A07)
-- ---------------------------------------------------------------------------
-- O local é arredondado (~1 km) para não guardar o endereço exato de quem buscou.
create table if not exists public.buscas (
  id bigint generated always as identity primary key,
  usuario_id uuid references public.perfis (id) on delete set null,
  profissao_id text references public.profissoes (id),
  especialidade_id bigint references public.especialidades (id) on delete set null,
  regiao_id text references public.regioes (id),
  lat numeric(6, 3) not null,
  lng numeric(6, 3) not null,
  resultados integer not null,
  criada_em timestamptz not null default now()
);
create index if not exists buscas_criada_idx on public.buscas (criada_em desc);
alter table public.buscas enable row level security;
revoke all on public.buscas from anon, authenticated;

create or replace function public.regiao_mais_proxima(p_lat double precision, p_lng double precision)
returns text
language sql stable
set search_path = public, extensions
as $$
  select r.id from public.regioes r where r.centro is not null
  order by extensions.st_distance(r.centro, public.ponto(p_lat, p_lng)) limit 1
$$;

create or replace function public.registrar_busca(p_profissao text, p_especialidade bigint, p_lat double precision, p_lng double precision, p_resultados integer)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if p_lat is null or p_lng is null then return; end if;
  -- Várias buscas iguais seguidas (rolar a lista, voltar à tela) contam uma vez.
  if exists (select 1 from public.buscas where usuario_id = auth.uid() and profissao_id = p_profissao
             and especialidade_id is not distinct from p_especialidade and criada_em > now() - interval '2 minutes') then
    return;
  end if;
  insert into public.buscas (usuario_id, profissao_id, especialidade_id, regiao_id, lat, lng, resultados)
  values (auth.uid(), p_profissao, p_especialidade, public.regiao_mais_proxima(p_lat, p_lng), round(p_lat::numeric, 2), round(p_lng::numeric, 2), p_resultados);
end;
$$;
revoke all on function public.regiao_mais_proxima(double precision, double precision), public.registrar_busca(text, bigint, double precision, double precision, integer)
  from public, anon, authenticated;

-- A busca de verdade passa a se chamar buscar_profissionais_base; o nome antigo
-- vira um invólucro que devolve o mesmo resultado e registra a busca.
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'buscar_profissionais_base' and pronamespace = 'public'::regnamespace) then
    alter function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) rename to buscar_profissionais_base;
  end if;
end;
$$;
revoke all on function public.buscar_profissionais_base(text, double precision, double precision, bigint, text, integer, integer) from public, anon, authenticated;

create or replace function public.buscar_profissionais(
  p_profissao text,
  p_lat double precision,
  p_lng double precision,
  p_especialidade bigint default null,
  p_ordem text default 'qualidade',
  p_rodizio integer default 0,
  p_limite integer default 50
)
returns table (
  profissional_id uuid,
  nome text,
  foto_url text,
  nota_media numeric,
  total_avaliacoes integer,
  servicos_concluidos integer,
  anos_experiencia smallint,
  verificado boolean,
  distancia_km numeric,
  novo boolean,
  preco_a_partir numeric,
  especialidades text[],
  favorito boolean,
  fase_lancamento boolean,
  posicao integer
)
language plpgsql volatile security definer
set search_path = public, extensions
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_n integer;
begin
  return query select * from public.buscar_profissionais_base(p_profissao, p_lat, p_lng, p_especialidade, p_ordem, p_rodizio, p_limite);
  get diagnostics v_n = row_count;
  begin
    perform public.registrar_busca(p_profissao, p_especialidade, p_lat, p_lng, v_n);
  exception when others then
    null; -- o registro nunca pode quebrar a busca
  end;
end;
$$;
revoke all on function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) from public, anon;
grant execute on function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Avaliações ocultas pela equipe não contam na nota nem aparecem no perfil (A04)
-- ---------------------------------------------------------------------------
create or replace function public.recalcular_nota()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_pro uuid := coalesce(new.profissional_id, old.profissional_id);
begin
  update public.profissionais set
    nota_media = coalesce((select round(avg(nota)::numeric, 2) from public.avaliacoes where profissional_id = v_pro and not oculta), 0),
    total_avaliacoes = (select count(*) from public.avaliacoes where profissional_id = v_pro and not oculta)
  where id = v_pro;
  if tg_op = 'INSERT' then
    perform public.notificar(v_pro, 'avaliacao_nova', 'Você recebeu uma avaliação de ' || new.nota || ' estrelas', coalesce(new.comentario, ''),
      jsonb_build_object('pedido_id', new.pedido_id));
  end if;
  return null;
end;
$$;
drop trigger if exists recalcular_nota on public.avaliacoes;
create trigger recalcular_nota after insert or update of nota, oculta or delete on public.avaliacoes for each row execute function public.recalcular_nota();

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
    'novo', pr.total_avaliacoes < public.cfg_num('min_avaliacoes_ranking', 5),
    'regiao', (select r.nome from public.regioes r where r.id = pr.regiao_id),
    'membro_desde', pr.aprovado_em,
    'favorito', exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    'profissoes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'nome', f.nome, 'icone', f.icone,
        'especialidades', coalesce((
          select jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'preco', x.preco) order by e.ordem, e.nome)
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
-- 5. Denúncias (A04). Os apps chamam denunciar(); a equipe trata no painel.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'status_denuncia') then
    create type public.status_denuncia as enum ('aberta', 'em_analise', 'procedente', 'improcedente');
  end if;
end;
$$;

create table if not exists public.denuncias (
  id bigint generated always as identity primary key,
  autor_id uuid references public.perfis (id) on delete set null,
  alvo_id uuid not null references public.perfis (id) on delete cascade,
  pedido_id uuid references public.pedidos (id) on delete set null,
  motivo text not null,
  descricao text not null default '',
  status public.status_denuncia not null default 'aberta',
  resolucao text,
  resolvida_por uuid references public.perfis (id) on delete set null,
  criada_em timestamptz not null default now(),
  resolvida_em timestamptz
);
create index if not exists denuncias_status_idx on public.denuncias (status, criada_em desc);
alter table public.denuncias enable row level security;
revoke all on public.denuncias from anon, authenticated;
grant select on public.denuncias to authenticated;
drop policy if exists "denuncias: autor e admin leem" on public.denuncias;
create policy "denuncias: autor e admin leem" on public.denuncias for select to authenticated using (autor_id = auth.uid() or public.e_admin());

create or replace function public.denunciar(p_alvo uuid, p_motivo text, p_descricao text default '', p_pedido uuid default null)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if p_alvo = auth.uid() then perform public.erro('denuncia_invalida', 'Não é possível denunciar a própria conta.'); end if;
  if coalesce(trim(p_motivo), '') = '' then perform public.erro('denuncia_invalida', 'Conte o motivo da denúncia.'); end if;
  if p_pedido is not null and not exists (
    select 1 from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id) and p_alvo in (cliente_id, profissional_id)) then
    perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.');
  end if;
  if (select count(*) from public.denuncias where autor_id = auth.uid() and criada_em > now() - interval '1 day') >= 10 then
    perform public.erro('limite_denuncias', 'Você já enviou muitas denúncias hoje. Fale com o suporte.');
  end if;
  insert into public.denuncias (autor_id, alvo_id, pedido_id, motivo, descricao)
  values (auth.uid(), p_alvo, p_pedido, left(trim(p_motivo), 120), left(coalesce(p_descricao, ''), 2000)) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.denunciar(uuid, text, text, uuid) from public, anon;
grant execute on function public.denunciar(uuid, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Garantia iService: histórico da mediação
-- ---------------------------------------------------------------------------
create table if not exists public.reclamacao_historico (
  id bigint generated always as identity primary key,
  reclamacao_id bigint not null references public.reclamacoes (id) on delete cascade,
  autor_id uuid references public.perfis (id) on delete set null,
  status public.status_reclamacao,
  texto text not null default '',
  interno boolean not null default true,   -- false = enviado às duas partes
  criado_em timestamptz not null default now()
);
create index if not exists reclamacao_historico_idx on public.reclamacao_historico (reclamacao_id, criado_em);
alter table public.reclamacao_historico enable row level security;
revoke all on public.reclamacao_historico from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Comunicados para grupos de profissionais (A08)
-- ---------------------------------------------------------------------------
create table if not exists public.comunicados (
  id bigint generated always as identity primary key,
  admin_id uuid references public.perfis (id) on delete set null,
  profissao_id text references public.profissoes (id),
  regiao_id text references public.regioes (id),
  publico text not null,
  titulo text not null,
  corpo text not null,
  destinatarios integer not null,
  criado_em timestamptz not null default now()
);
alter table public.comunicados enable row level security;
revoke all on public.comunicados from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Preço de referência ajustável (A09)
-- ---------------------------------------------------------------------------
create table if not exists public.precos_referencia (
  especialidade_id bigint not null references public.especialidades (id) on delete cascade,
  faixa smallint not null check (faixa between 1 and 5),
  minimo numeric(10, 2) not null check (minimo > 0),
  maximo numeric(10, 2) not null,
  atualizado_por uuid references public.perfis (id) on delete set null,
  atualizado_em timestamptz not null default now(),
  primary key (especialidade_id, faixa),
  check (maximo >= minimo)
);
alter table public.precos_referencia enable row level security;
revoke all on public.precos_referencia from anon, authenticated;

-- Faixa calculada pelos preços reais (ou pela base), sem o ajuste da equipe.
create or replace function public.faixa_preco_calculada(p_especialidade bigint, p_faixa smallint)
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_n int;
  v_p25 numeric;
  v_p75 numeric;
  v_base numeric;
  v_fator numeric;
begin
  select count(*), percentile_cont(0.25) within group (order by x.preco), percentile_cont(0.75) within group (order by x.preco)
  into v_n, v_p25, v_p75
  from public.profissional_especialidades x
  join public.profissionais pr on pr.id = x.profissional_id and pr.status = 'aprovado'
  join public.regioes r on r.id = pr.regiao_id and r.faixa_preco = p_faixa
  where x.especialidade_id = p_especialidade and x.preco is not null;

  if v_n >= public.cfg_num('min_amostras_preco', 5) then
    return query select round(v_p25 / 5) * 5, round(v_p75 / 5) * 5, v_n, false;
    return;
  end if;

  select f.preco_base + greatest(e.ordem, 0) * 20 into v_base
  from public.especialidades e join public.profissoes f on f.id = e.profissao_id where e.id = p_especialidade;
  v_fator := coalesce((public.cfg('fator_faixa_preco') ->> p_faixa::text)::numeric, 1);
  return query select round(v_base * v_fator * 0.9 / 5) * 5, round(v_base * v_fator * 1.8 / 5) * 5, coalesce(v_n, 0), true;
end;
$$;
revoke all on function public.faixa_preco_calculada(bigint, smallint) from public, anon, authenticated;

-- O que os apps mostram: o ajuste da equipe, quando existe; senão, a faixa calculada.
create or replace function public.faixa_preco(p_especialidade bigint, p_regiao text)
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_faixa smallint := coalesce((select faixa_preco from public.regioes where id = p_regiao), 2);
  v_aj public.precos_referencia;
  v_calc record;
begin
  select * into v_calc from public.faixa_preco_calculada(p_especialidade, v_faixa);
  select * into v_aj from public.precos_referencia where especialidade_id = p_especialidade and faixa = v_faixa;
  if v_aj.especialidade_id is not null then
    return query select v_aj.minimo, v_aj.maximo, v_calc.amostras, false;
    return;
  end if;
  return query select v_calc.minimo, v_calc.maximo, v_calc.amostras, v_calc.estimada;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Fotos do pedido: a equipe vê quando há reclamação, denúncia ou emergência
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'objects') then
    execute 'drop policy if exists "admin lê arquivos de pedidos" on storage.objects';
    execute $p$create policy "admin lê arquivos de pedidos" on storage.objects for select to authenticated
      using (bucket_id = 'pedidos' and public.e_admin())$p$;
  end if;
end;
$$;

-- ===========================================================================
-- Funções do painel. Todas conferem e_admin().
-- ===========================================================================

-- Painel de entrada (A06): números do dia e o que precisa de atenção.
create or replace function public.admin_resumo(p_dia date default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_dia date := coalesce(p_dia, current_date);
  v_ini timestamptz := v_dia::timestamptz;
  v_fim timestamptz := (v_dia + 1)::timestamptz;
  v jsonb;
begin
  perform public.exigir_admin();
  select jsonb_build_object(
    'dia', v_dia,
    'cadastros_em_analise', (select count(*) from public.profissionais where status = 'em_analise'),
    'reclamacoes_abertas', (select count(*) from public.reclamacoes where status in ('aberta', 'em_mediacao')),
    'denuncias_abertas', (select count(*) from public.denuncias where status in ('aberta', 'em_analise')),
    'emergencias_abertas', (select count(*) from public.emergencias where atendida_em is null),
    'especialidades_sugeridas', (select count(*) from public.especialidades where not aprovada),
    'profissionais_aprovados', (select count(*) from public.profissionais where status = 'aprovado'),
    'profissionais_disponiveis', (select count(*) from public.profissionais where status = 'aprovado' and disponivel),
    'clientes', (select count(*) from public.perfis where e_cliente and excluido_em is null),
    'buscas', (select count(*) from public.buscas where criada_em >= v_ini and criada_em < v_fim),
    'buscas_sem_resultado', (select count(*) from public.buscas where resultados = 0 and criada_em >= v_ini and criada_em < v_fim),
    'pedidos', (select count(*) from public.pedidos where criado_em >= v_ini and criado_em < v_fim),
    'pedidos_por_status', coalesce((select jsonb_object_agg(status, n) from (
        select status, count(*) n from public.pedidos where criado_em >= v_ini and criado_em < v_fim group by status) s), '{}'::jsonb),
    'pedidos_em_andamento', (select count(*) from public.pedidos where status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento')),
    'concluidos', (select count(*) from public.pedidos where concluido_em >= v_ini and concluido_em < v_fim),
    'cadastros_novos_clientes', (select count(*) from public.perfis p where p.criado_em >= v_ini and p.criado_em < v_fim
        and not exists (select 1 from public.profissionais pr where pr.id = p.id)),
    'cadastros_novos_profissionais', (select count(*) from public.profissionais where criado_em >= v_ini and criado_em < v_fim),
    'avaliacoes', (select count(*) from public.avaliacoes where criada_em >= v_ini and criada_em < v_fim),
    'nota_media_dia', (select round(avg(nota)::numeric, 2) from public.avaliacoes where criada_em >= v_ini and criada_em < v_fim),
    'ultimos_7_dias', coalesce((select jsonb_agg(jsonb_build_object('dia', d::date,
        'buscas', (select count(*) from public.buscas where criada_em >= d and criada_em < d + interval '1 day'),
        'sem_resultado', (select count(*) from public.buscas where resultados = 0 and criada_em >= d and criada_em < d + interval '1 day'),
        'pedidos', (select count(*) from public.pedidos where criado_em >= d and criado_em < d + interval '1 day'),
        'concluidos', (select count(*) from public.pedidos where concluido_em >= d and concluido_em < d + interval '1 day'),
        'cadastros', (select count(*) from public.perfis where criado_em >= d and criado_em < d + interval '1 day')) order by d)
      from generate_series(v_ini - interval '6 days', v_ini, interval '1 day') d), '[]'::jsonb),
    'profissionais_por_profissao', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'ativa', f.ativa,
        'aprovados', (select count(*) from public.profissional_profissoes pp join public.profissionais pr on pr.id = pp.profissional_id
                      where pp.profissao_id = f.id and pr.status = 'aprovado'),
        'em_analise', (select count(*) from public.profissional_profissoes pp join public.profissionais pr on pr.id = pp.profissional_id
                      where pp.profissao_id = f.id and pr.status = 'em_analise')) order by f.ordem)
      from public.profissoes f), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- Buscas por região e profissão (A06)
create or replace function public.admin_buscas_por_regiao(p_inicio date default null, p_fim date default null)
returns table (regiao_id text, regiao text, profissao_id text, profissao text, buscas bigint, sem_resultado bigint)
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
begin
  perform public.exigir_admin();
  return query
  select b.regiao_id, r.nome, b.profissao_id, f.nome, count(*), count(*) filter (where b.resultados = 0)
  from public.buscas b
  left join public.regioes r on r.id = b.regiao_id
  left join public.profissoes f on f.id = b.profissao_id
  where b.criada_em >= coalesce(p_inicio, current_date - 6)::timestamptz and b.criada_em < (coalesce(p_fim, current_date) + 1)::timestamptz
  group by b.regiao_id, r.nome, b.profissao_id, f.nome
  order by count(*) filter (where b.resultados = 0) desc, count(*) desc;
end;
$$;

-- Pontos do mapa de calor (A07)
create or replace function public.admin_mapa_buscas(p_inicio date default null, p_fim date default null, p_profissao text default null, p_so_sem_resultado boolean default true)
returns table (lat numeric, lng numeric, total bigint, sem_resultado bigint)
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
begin
  perform public.exigir_admin();
  return query
  select b.lat, b.lng, count(*), count(*) filter (where b.resultados = 0)
  from public.buscas b
  where b.criada_em >= coalesce(p_inicio, current_date - 29)::timestamptz and b.criada_em < (coalesce(p_fim, current_date) + 1)::timestamptz
    and (p_profissao is null or b.profissao_id = p_profissao)
    and (not p_so_sem_resultado or b.resultados = 0)
  group by b.lat, b.lng;
end;
$$;

-- Lista de cadastros de profissionais (A01)
create or replace function public.admin_cadastros(p_status public.status_cadastro default 'em_analise', p_texto text default null, p_limite integer default 200)
returns table (
  id uuid, nome text, email text, telefone text, foto_url text, status public.status_cadastro, motivo_status text,
  profissoes text[], exige_antecedentes boolean, regiao text, documentos_pendentes bigint, documentos_recusados bigint,
  criado_em timestamptz, atualizado_em timestamptz, suspenso boolean
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select pr.id, pe.nome, pe.email, pe.telefone, pe.foto_url, pr.status, pr.motivo_status,
    array(select f.nome from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
          where pp.profissional_id = pr.id order by pp.principal desc, f.ordem),
    exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
            where pp.profissional_id = pr.id and f.exige_antecedentes),
    (select r.nome from public.regioes r where r.id = pr.regiao_id),
    (select count(*) from public.documentos d where d.profissional_id = pr.id and d.status = 'pendente'),
    (select count(*) from public.documentos d where d.profissional_id = pr.id and d.status = 'recusado'),
    pr.criado_em, pr.atualizado_em, pe.suspenso_em is not null
  from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where (p_status is null or pr.status = p_status)
    and pe.excluido_em is null
    and (p_texto is null or p_texto = '' or pe.nome ilike '%' || p_texto || '%' or pe.email ilike '%' || p_texto || '%'
         or pe.cpf like regexp_replace(p_texto, '\D', '', 'g') || '%' and regexp_replace(p_texto, '\D', '', 'g') <> '')
  -- Fila: quem enviou primeiro é atendido primeiro.
  order by case when pr.status = 'em_analise' then pr.atualizado_em end asc nulls last, pr.atualizado_em desc
  limit p_limite;
end;
$$;

-- Busca de pessoas (A03)
create or replace function public.admin_usuarios(p_texto text default null, p_filtro text default 'todos', p_limite integer default 50, p_pular integer default 0)
returns table (
  id uuid, nome text, email text, telefone text, foto_url text, e_cliente boolean, e_profissional boolean, e_admin boolean,
  status_profissional public.status_cadastro, suspenso boolean, exclusao_pendente boolean, pedidos bigint, criado_em timestamptz, total bigint
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_dig text := regexp_replace(coalesce(p_texto, ''), '\D', '', 'g');
begin
  perform public.exigir_admin();
  return query
  select pe.id, pe.nome, pe.email, pe.telefone, pe.foto_url, pe.e_cliente, pr.id is not null, pe.e_admin, pr.status,
    pe.suspenso_em is not null, pe.exclusao_solicitada_em is not null,
    (select count(*) from public.pedidos p where pe.id in (p.cliente_id, p.profissional_id)),
    pe.criado_em, count(*) over ()
  from public.perfis pe left join public.profissionais pr on pr.id = pe.id
  where pe.excluido_em is null
    and (coalesce(p_texto, '') = '' or pe.nome ilike '%' || p_texto || '%' or pe.email ilike '%' || p_texto || '%'
         or (v_dig <> '' and (pe.cpf like v_dig || '%' or pe.telefone like '%' || v_dig || '%')))
    and case p_filtro
      when 'clientes' then pr.id is null
      when 'profissionais' then pr.id is not null
      when 'suspensos' then pe.suspenso_em is not null
      when 'admins' then pe.e_admin
      else true end
  order by pe.criado_em desc
  limit p_limite offset p_pular;
end;
$$;

-- Ficha completa de uma pessoa (cliente e/ou profissional)
create or replace function public.admin_usuario(p_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v jsonb;
begin
  perform public.exigir_admin();
  select jsonb_build_object(
    'perfil', jsonb_build_object('id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'cpf', pe.cpf,
      'nascimento', pe.nascimento, 'foto_url', pe.foto_url, 'telefone_verificado', pe.telefone_verificado,
      'e_cliente', pe.e_cliente, 'e_profissional', pe.e_profissional, 'e_admin', pe.e_admin,
      'criado_em', pe.criado_em, 'suspenso_em', pe.suspenso_em, 'motivo_suspensao', pe.motivo_suspensao,
      'exclusao_solicitada_em', pe.exclusao_solicitada_em, 'codigo_indicacao', pe.codigo_indicacao),
    'enderecos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'rotulo', e.rotulo, 'logradouro', e.logradouro, 'bloco', e.bloco,
        'numero', e.numero, 'complemento', e.complemento, 'cidade', e.cidade, 'uf', e.uf, 'cep', e.cep,
        'regiao', (select r.nome from public.regioes r where r.id = e.regiao_id), 'principal', e.principal) order by e.principal desc, e.id)
      from public.enderecos e where e.usuario_id = pe.id), '[]'::jsonb),
    'profissional', (select jsonb_build_object(
        'status', pr.status, 'motivo_status', pr.motivo_status, 'verificado', pr.verificado, 'disponivel', pr.disponivel,
        'bio', pr.bio, 'anos_experiencia', pr.anos_experiencia, 'area_raio_km', pr.area_raio_km,
        'area_lat', extensions.st_y(pr.area_centro::extensions.geometry), 'area_lng', extensions.st_x(pr.area_centro::extensions.geometry),
        'regiao', (select r.nome from public.regioes r where r.id = pr.regiao_id), 'plano', pr.plano,
        'nota_media', pr.nota_media, 'total_avaliacoes', pr.total_avaliacoes, 'servicos_concluidos', pr.servicos_concluidos,
        'pedidos_recebidos', pr.pedidos_recebidos, 'pedidos_aceitos', pr.pedidos_aceitos, 'pedidos_perdidos', pr.pedidos_perdidos,
        'cancelados_pelo_profissional', pr.cancelados_pelo_profissional, 'aprovado_em', pr.aprovado_em, 'criado_em', pr.criado_em,
        'atualizado_em', pr.atualizado_em,
        'pendencias', to_jsonb(coalesce(public.pendencias_profissional(pr.id), '{}')),
        'profissoes', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'principal', pp.principal,
            'exige_antecedentes', f.exige_antecedentes,
            'especialidades', coalesce((select jsonb_agg(jsonb_build_object('id', es.id, 'nome', es.nome, 'preco', x.preco, 'aprovada', es.aprovada)
                order by es.ordem, es.nome)
              from public.profissional_especialidades x join public.especialidades es on es.id = x.especialidade_id
              where x.profissional_id = pr.id and es.profissao_id = f.id), '[]'::jsonb)) order by pp.principal desc, f.ordem)
          from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = pr.id), '[]'::jsonb),
        'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'arquivo_path', d.arquivo_path, 'status', d.status,
            'observacao', d.observacao, 'criado_em', d.criado_em, 'revisado_em', d.revisado_em) order by d.tipo, d.criado_em desc)
          from public.documentos d where d.profissional_id = pr.id), '[]'::jsonb),
        'certificacoes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'instituicao', c.instituicao,
            'profissao_id', c.profissao_id, 'arquivo_path', c.arquivo_path, 'status', c.status, 'criado_em', c.criado_em) order by c.criado_em)
          from public.certificacoes c where c.profissional_id = pr.id), '[]'::jsonb),
        'portfolio', coalesce((select jsonb_agg(jsonb_build_object('id', po.id, 'descricao', po.descricao, 'antes_path', po.antes_path,
            'depois_path', po.depois_path) order by po.ordem, po.id) from public.portfolio po where po.profissional_id = pr.id), '[]'::jsonb))
      from public.profissionais pr where pr.id = pe.id),
    'pedidos', coalesce((select jsonb_agg(x order by (x ->> 'criado_em') desc) from (
        select jsonb_build_object('id', p.id, 'codigo', p.codigo, 'status', p.status, 'criado_em', p.criado_em,
          'profissao', (select f.nome from public.profissoes f where f.id = p.profissao_id),
          'papel', case when p.cliente_id = pe.id then 'cliente' else 'profissional' end,
          'outra_parte', (select o.nome from public.perfis o where o.id = case when p.cliente_id = pe.id then p.profissional_id else p.cliente_id end),
          'valor', coalesce(p.valor_cobrado, p.preco_informado)) x
        from public.pedidos p where pe.id in (p.cliente_id, p.profissional_id) order by p.criado_em desc limit 30) s), '[]'::jsonb),
    'denuncias_recebidas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'motivo', d.motivo, 'status', d.status, 'criada_em', d.criada_em)
        order by d.criada_em desc) from public.denuncias d where d.alvo_id = pe.id), '[]'::jsonb),
    'reclamacoes', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'status', r.status, 'criada_em', r.criada_em)
        order by r.criada_em desc) from public.reclamacoes r join public.pedidos p on p.id = r.pedido_id
        where pe.id in (p.cliente_id, p.profissional_id)), '[]'::jsonb),
    'acoes', coalesce((select jsonb_agg(jsonb_build_object('acao', a.acao, 'dados', a.dados, 'criada_em', a.criada_em,
        'admin', (select ad.nome from public.perfis ad where ad.id = a.admin_id)) order by a.criada_em desc)
      from (select * from public.admin_acoes where alvo = pe.id::text order by criada_em desc limit 30) a), '[]'::jsonb)
  ) into v
  from public.perfis pe where pe.id = p_id;
  if v is null then perform public.erro('nao_encontrado', 'Pessoa não encontrada.'); end if;
  return v;
end;
$$;

-- Revisão de um documento (A02). Recusar = pedir nova foto: o cadastro volta
-- para o profissional com o motivo, e ele reenvia pelo app.
create or replace function public.admin_revisar_documento(p_documento bigint, p_aprovar boolean, p_observacao text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_doc public.documentos;
  v_nome text;
begin
  perform public.exigir_admin();
  select * into v_doc from public.documentos where id = p_documento;
  if v_doc.id is null then perform public.erro('nao_encontrado', 'Documento não encontrado.'); end if;
  if not p_aprovar and coalesce(trim(p_observacao), '') = '' then
    perform public.erro('motivo_obrigatorio', 'Diga ao profissional o que precisa mudar na foto.');
  end if;
  update public.documentos set status = case when p_aprovar then 'aprovado' else 'recusado' end::public.status_documento,
    observacao = nullif(trim(p_observacao), ''), revisado_em = now(), revisado_por = auth.uid()
  where id = p_documento;
  v_nome := case v_doc.tipo when 'documento_frente' then 'a frente do documento' when 'documento_verso' then 'o verso do documento'
    when 'selfie_documento' then 'a selfie com o documento' when 'antecedentes' then 'a certidão de antecedentes'
    else 'o comprovante de endereço' end;
  if not p_aprovar then
    update public.profissionais set status = 'recusado', motivo_status = 'Envie de novo ' || v_nome || ': ' || trim(p_observacao)
    where id = v_doc.profissional_id and status = 'em_analise';
    perform public.notificar(v_doc.profissional_id, 'documento_recusado', 'Envie uma nova foto',
      'Precisamos que você envie de novo ' || v_nome || '. ' || trim(p_observacao), jsonb_build_object('documento_id', p_documento));
  elsif v_doc.tipo = 'antecedentes' and exists (select 1 from public.profissionais where id = v_doc.profissional_id and status = 'aprovado') then
    perform public.notificar(v_doc.profissional_id, 'antecedentes_aprovados', 'Certidão aprovada',
      'Agora você já pode atender nas profissões que exigem certidão de antecedentes.');
  end if;
  perform public.registrar_acao(case when p_aprovar then 'aprovar_documento' else 'recusar_documento' end, v_doc.profissional_id::text,
    jsonb_build_object('documento_id', p_documento, 'tipo', v_doc.tipo, 'observacao', p_observacao));
end;
$$;

create or replace function public.admin_revisar_certificacao(p_certificacao bigint, p_aprovar boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pro uuid;
begin
  perform public.exigir_admin();
  update public.certificacoes set status = case when p_aprovar then 'aprovado' else 'recusado' end::public.status_documento
  where id = p_certificacao returning profissional_id into v_pro;
  if v_pro is null then perform public.erro('nao_encontrado', 'Certificação não encontrada.'); end if;
  perform public.registrar_acao(case when p_aprovar then 'aprovar_certificacao' else 'recusar_certificacao' end, v_pro::text,
    jsonb_build_object('certificacao_id', p_certificacao));
end;
$$;

-- Decisão do cadastro (A02). Mesma assinatura de antes; agora confere pendências,
-- pede motivo na recusa e registra a ação.
create or replace function public.admin_decidir_cadastro(p_profissional uuid, p_aprovar boolean, p_motivo text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pend text[];
begin
  perform public.exigir_admin();
  if not exists (select 1 from public.profissionais where id = p_profissional) then
    perform public.erro('nao_encontrado', 'Cadastro não encontrado.');
  end if;
  if p_aprovar then
    v_pend := public.pendencias_profissional(p_profissional);
    if cardinality(v_pend) > 0 then
      perform public.erro('cadastro_incompleto', 'O cadastro ainda tem pendências: ' || array_to_string(v_pend, ', ') || '.');
    end if;
    update public.documentos set status = 'aprovado', revisado_em = now(), revisado_por = auth.uid()
    where profissional_id = p_profissional and status = 'pendente';
    update public.profissionais set status = 'aprovado', verificado = true, motivo_status = null, aprovado_em = coalesce(aprovado_em, now())
    where id = p_profissional;
    update public.perfis set e_profissional = true where id = p_profissional;
    perform public.notificar(p_profissional, 'cadastro_aprovado', 'Cadastro aprovado!', 'Ative o modo disponível para começar a receber pedidos.');
  else
    if coalesce(trim(p_motivo), '') = '' then perform public.erro('motivo_obrigatorio', 'Escreva o motivo da recusa para o profissional.'); end if;
    update public.profissionais set status = 'recusado', disponivel = false, motivo_status = trim(p_motivo) where id = p_profissional;
    perform public.notificar(p_profissional, 'cadastro_recusado', 'Seu cadastro precisa de ajustes', trim(p_motivo));
  end if;
  perform public.registrar_acao(case when p_aprovar then 'aprovar_cadastro' else 'recusar_cadastro' end, p_profissional::text,
    jsonb_build_object('motivo', p_motivo));
end;
$$;

-- Suspender ou reativar (A03). Bloqueia o login e some das buscas.
create or replace function public.admin_suspender(p_usuario uuid, p_suspender boolean, p_motivo text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if p_usuario = auth.uid() then perform public.erro('sem_permissao', 'Você não pode suspender a própria conta.'); end if;
  if not exists (select 1 from public.perfis where id = p_usuario and excluido_em is null) then
    perform public.erro('nao_encontrado', 'Pessoa não encontrada.');
  end if;
  if p_suspender then
    if coalesce(trim(p_motivo), '') = '' then perform public.erro('motivo_obrigatorio', 'Escreva o motivo da suspensão.'); end if;
    update public.perfis set suspenso_em = coalesce(suspenso_em, now()), motivo_suspensao = trim(p_motivo) where id = p_usuario;
    update public.profissionais set status = 'suspenso', disponivel = false, motivo_status = trim(p_motivo) where id = p_usuario;
    -- Pedidos que ainda nem foram aceitos são cancelados; os em andamento ficam para a equipe acompanhar.
    update public.pedidos set status = 'cancelado', motivo = 'Conta suspensa pela equipe iService', cancelado_por = auth.uid(), encerrado_em = now()
    where status = 'solicitado' and p_usuario in (cliente_id, profissional_id);
    begin
      update auth.users set banned_until = 'infinity' where id = p_usuario;
    exception when others then null;
    end;
  else
    update public.perfis set suspenso_em = null, motivo_suspensao = null where id = p_usuario;
    update public.profissionais set status = case when aprovado_em is not null then 'aprovado' else 'em_analise' end::public.status_cadastro,
      motivo_status = null
    where id = p_usuario and status = 'suspenso';
    begin
      update auth.users set banned_until = null where id = p_usuario;
    exception when others then null;
    end;
    perform public.notificar(p_usuario, 'conta_reativada', 'Sua conta foi reativada', 'Você já pode usar o iService normalmente.');
  end if;
  perform public.registrar_acao(case when p_suspender then 'suspender' else 'reativar' end, p_usuario::text, jsonb_build_object('motivo', p_motivo));
end;
$$;

-- Lista de pedidos
create or replace function public.admin_pedidos(
  p_status text default null,        -- um status, 'andamento' ou null para todos
  p_texto text default null,         -- código do pedido ou nome de uma das partes
  p_inicio date default null,
  p_fim date default null,
  p_limite integer default 50,
  p_pular integer default 0
)
returns table (
  id uuid, codigo text, status public.status_pedido, quando public.quando_pedido, criado_em timestamptz,
  cliente_id uuid, cliente text, profissional_id uuid, profissional text, profissao text, especialidade text,
  regiao text, valor numeric, tem_reclamacao boolean, tem_emergencia boolean, total bigint
)
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
begin
  perform public.exigir_admin();
  return query
  select p.id, p.codigo, p.status, p.quando, p.criado_em, p.cliente_id, c.nome, p.profissional_id, pf.nome, f.nome, es.nome, r.nome,
    coalesce(p.valor_cobrado, p.preco_informado),
    exists (select 1 from public.reclamacoes x where x.pedido_id = p.id),
    exists (select 1 from public.emergencias x where x.pedido_id = p.id),
    count(*) over ()
  from public.pedidos p
  join public.perfis c on c.id = p.cliente_id
  join public.perfis pf on pf.id = p.profissional_id
  join public.profissoes f on f.id = p.profissao_id
  left join public.especialidades es on es.id = p.especialidade_id
  left join public.regioes r on r.id = p.regiao_id
  where (p_status is null or p_status = '' or (p_status = 'andamento' and p.status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento'))
         or p.status::text = p_status)
    and (coalesce(p_texto, '') = '' or p.codigo ilike p_texto || '%' or c.nome ilike '%' || p_texto || '%' or pf.nome ilike '%' || p_texto || '%')
    and (p_inicio is null or p.criado_em >= p_inicio::timestamptz)
    and (p_fim is null or p.criado_em < (p_fim + 1)::timestamptz)
  order by p.criado_em desc
  limit p_limite offset p_pular;
end;
$$;

-- Detalhe do pedido. A conversa só é mostrada quando há reclamação, denúncia
-- ou emergência no pedido (privacidade de cliente e profissional).
create or replace function public.admin_pedido(p_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v jsonb;
  v_motivo boolean;
begin
  perform public.exigir_admin();
  v_motivo := exists (select 1 from public.reclamacoes where pedido_id = p_id)
    or exists (select 1 from public.denuncias where pedido_id = p_id)
    or exists (select 1 from public.emergencias where pedido_id = p_id);
  select jsonb_build_object(
    'pedido', to_jsonb(p) - 'localizacao' || jsonb_build_object(
      'lat', round(extensions.st_y(p.localizacao::extensions.geometry)::numeric, 5),
      'lng', round(extensions.st_x(p.localizacao::extensions.geometry)::numeric, 5),
      'profissao', (select f.nome from public.profissoes f where f.id = p.profissao_id),
      'especialidade', (select es.nome from public.especialidades es where es.id = p.especialidade_id),
      'regiao', (select r.nome from public.regioes r where r.id = p.regiao_id)),
    'cliente', (select jsonb_build_object('id', c.id, 'nome', c.nome, 'telefone', c.telefone, 'email', c.email, 'foto_url', c.foto_url)
      from public.perfis c where c.id = p.cliente_id),
    'profissional', (select jsonb_build_object('id', c.id, 'nome', c.nome, 'telefone', c.telefone, 'email', c.email, 'foto_url', c.foto_url)
      from public.perfis c where c.id = p.profissional_id),
    'avaliacao', (select to_jsonb(a) from public.avaliacoes a where a.pedido_id = p.id),
    'reclamacoes', coalesce((select jsonb_agg(to_jsonb(r) order by r.criada_em) from public.reclamacoes r where r.pedido_id = p.id), '[]'::jsonb),
    'emergencias', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'usuario_id', e.usuario_id, 'criada_em', e.criada_em,
        'atendida_em', e.atendida_em, 'nota_atendimento', e.nota_atendimento)) from public.emergencias e where e.pedido_id = p.id), '[]'::jsonb),
    'denuncias', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'motivo', d.motivo, 'status', d.status, 'criada_em', d.criada_em))
      from public.denuncias d where d.pedido_id = p.id), '[]'::jsonb),
    'conversa_liberada', v_motivo,
    'mensagens', case when v_motivo then coalesce((select jsonb_agg(jsonb_build_object('autor_id', m.autor_id, 'texto', m.texto, 'criada_em', m.criada_em)
        order by m.criada_em) from public.mensagens m where m.pedido_id = p.id), '[]'::jsonb) end,
    'total_mensagens', (select count(*) from public.mensagens m where m.pedido_id = p.id)
  ) into v
  from public.pedidos p where p.id = p_id;
  if v is null then perform public.erro('nao_encontrado', 'Pedido não encontrado.'); end if;
  return v;
end;
$$;

-- Garantia iService: fila de reclamações
create or replace function public.admin_reclamacoes(p_status text default 'abertas')
returns table (
  id bigint, pedido_id uuid, codigo text, motivo text, descricao text, fotos text[], status public.status_reclamacao, resolucao text,
  autor_id uuid, autor text, autor_papel text, cliente text, profissional text, profissao text, valor numeric,
  criada_em timestamptz, atualizada_em timestamptz
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select r.id, r.pedido_id, p.codigo, r.motivo, r.descricao, r.fotos, r.status, r.resolucao, r.autor_id, a.nome,
    case when r.autor_id = p.cliente_id then 'cliente' else 'profissional' end,
    c.nome, pf.nome, f.nome, coalesce(p.valor_cobrado, p.preco_informado), r.criada_em, r.atualizada_em
  from public.reclamacoes r
  join public.pedidos p on p.id = r.pedido_id
  join public.perfis a on a.id = r.autor_id
  join public.perfis c on c.id = p.cliente_id
  join public.perfis pf on pf.id = p.profissional_id
  join public.profissoes f on f.id = p.profissao_id
  where p_status is null or p_status = 'todas'
     or (p_status = 'abertas' and r.status in ('aberta', 'em_mediacao'))
     or r.status::text = p_status
  order by case r.status when 'aberta' then 0 when 'em_mediacao' then 1 else 2 end, r.criada_em;
end;
$$;

create or replace function public.admin_reclamacao_historico(p_reclamacao bigint)
returns table (id bigint, autor text, status public.status_reclamacao, texto text, interno boolean, criado_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select h.id, (select pe.nome from public.perfis pe where pe.id = h.autor_id), h.status, h.texto, h.interno, h.criado_em
  from public.reclamacao_historico h where h.reclamacao_id = p_reclamacao order by h.criado_em;
end;
$$;

-- Mediação: muda o status, anota e, se pedido, avisa cliente e profissional.
create or replace function public.admin_mediar_reclamacao(p_reclamacao bigint, p_status public.status_reclamacao default null,
  p_texto text default null, p_avisar_partes boolean default false)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_rec public.reclamacoes;
  v_ped public.pedidos;
  v_titulo text;
begin
  perform public.exigir_admin();
  select * into v_rec from public.reclamacoes where id = p_reclamacao;
  if v_rec.id is null then perform public.erro('nao_encontrado', 'Reclamação não encontrada.'); end if;
  if p_status in ('resolvida', 'encerrada') and coalesce(trim(p_texto), '') = '' and v_rec.resolucao is null then
    perform public.erro('motivo_obrigatorio', 'Escreva a resolução antes de fechar a reclamação.');
  end if;
  select * into v_ped from public.pedidos where id = v_rec.pedido_id;
  update public.reclamacoes set status = coalesce(p_status, status),
    resolucao = case when p_status in ('resolvida', 'encerrada') and coalesce(trim(p_texto), '') <> '' then trim(p_texto) else resolucao end
  where id = p_reclamacao;
  insert into public.reclamacao_historico (reclamacao_id, autor_id, status, texto, interno)
  values (p_reclamacao, auth.uid(), p_status, coalesce(trim(p_texto), ''), not p_avisar_partes);
  if p_avisar_partes then
    v_titulo := case coalesce(p_status, v_rec.status)
      when 'em_mediacao' then 'Garantia iService: estamos mediando'
      when 'resolvida' then 'Garantia iService: reclamação resolvida'
      when 'encerrada' then 'Garantia iService: reclamação encerrada'
      else 'Garantia iService: atualização' end;
    perform public.notificar(v_ped.cliente_id, 'garantia', v_titulo, coalesce(trim(p_texto), ''),
      jsonb_build_object('pedido_id', v_ped.id, 'reclamacao_id', p_reclamacao));
    perform public.notificar(v_ped.profissional_id, 'garantia', v_titulo, coalesce(trim(p_texto), ''),
      jsonb_build_object('pedido_id', v_ped.id, 'reclamacao_id', p_reclamacao));
  end if;
  perform public.registrar_acao('mediar_reclamacao', v_rec.autor_id::text,
    jsonb_build_object('reclamacao_id', p_reclamacao, 'status', p_status, 'avisou', p_avisar_partes));
end;
$$;

-- Emergências
create or replace function public.admin_emergencias(p_abertas boolean default true)
returns table (id bigint, pedido_id uuid, codigo text, usuario_id uuid, usuario text, telefone text, papel text,
  lat numeric, lng numeric, criada_em timestamptz, atendida_em timestamptz, atendida_por text, nota_atendimento text)
language plpgsql stable security definer
set search_path = public, extensions
as $$
begin
  perform public.exigir_admin();
  return query
  select e.id, e.pedido_id, p.codigo, e.usuario_id, u.nome, u.telefone,
    case when p.id is null then null when e.usuario_id = p.cliente_id then 'cliente' else 'profissional' end,
    round(extensions.st_y(e.localizacao::extensions.geometry)::numeric, 5), round(extensions.st_x(e.localizacao::extensions.geometry)::numeric, 5),
    e.criada_em, e.atendida_em, (select a.nome from public.perfis a where a.id = e.atendida_por), e.nota_atendimento
  from public.emergencias e
  join public.perfis u on u.id = e.usuario_id
  left join public.pedidos p on p.id = e.pedido_id
  where not p_abertas or e.atendida_em is null
  order by e.atendida_em is not null, e.criada_em desc
  limit 200;
end;
$$;

create or replace function public.admin_atender_emergencia(p_emergencia bigint, p_nota text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_usuario uuid;
begin
  perform public.exigir_admin();
  update public.emergencias set atendida_em = coalesce(atendida_em, now()), atendida_por = auth.uid(), nota_atendimento = nullif(trim(p_nota), '')
  where id = p_emergencia returning usuario_id into v_usuario;
  if v_usuario is null then perform public.erro('nao_encontrado', 'Emergência não encontrada.'); end if;
  perform public.registrar_acao('atender_emergencia', v_usuario::text, jsonb_build_object('emergencia_id', p_emergencia, 'nota', p_nota));
end;
$$;

-- Denúncias
create or replace function public.admin_denuncias(p_status text default 'abertas')
returns table (id bigint, motivo text, descricao text, status public.status_denuncia, resolucao text, pedido_id uuid, codigo text,
  autor_id uuid, autor text, alvo_id uuid, alvo text, alvo_profissional boolean, denuncias_do_alvo bigint, criada_em timestamptz, resolvida_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select d.id, d.motivo, d.descricao, d.status, d.resolucao, d.pedido_id, p.codigo, d.autor_id, a.nome, d.alvo_id, t.nome,
    exists (select 1 from public.profissionais pr where pr.id = d.alvo_id),
    (select count(*) from public.denuncias x where x.alvo_id = d.alvo_id),
    d.criada_em, d.resolvida_em
  from public.denuncias d
  left join public.perfis a on a.id = d.autor_id
  join public.perfis t on t.id = d.alvo_id
  left join public.pedidos p on p.id = d.pedido_id
  where p_status is null or p_status = 'todas'
     or (p_status = 'abertas' and d.status in ('aberta', 'em_analise'))
     or d.status::text = p_status
  order by d.status in ('procedente', 'improcedente'), d.criada_em
  limit 300;
end;
$$;

create or replace function public.admin_resolver_denuncia(p_denuncia bigint, p_status public.status_denuncia, p_resolucao text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_alvo uuid;
begin
  perform public.exigir_admin();
  if p_status in ('procedente', 'improcedente') and coalesce(trim(p_resolucao), '') = '' then
    perform public.erro('motivo_obrigatorio', 'Escreva o que foi decidido.');
  end if;
  update public.denuncias set status = p_status, resolucao = coalesce(nullif(trim(p_resolucao), ''), resolucao),
    resolvida_por = case when p_status in ('procedente', 'improcedente') then auth.uid() end,
    resolvida_em = case when p_status in ('procedente', 'improcedente') then now() end
  where id = p_denuncia returning alvo_id into v_alvo;
  if v_alvo is null then perform public.erro('nao_encontrado', 'Denúncia não encontrada.'); end if;
  perform public.registrar_acao('resolver_denuncia', v_alvo::text, jsonb_build_object('denuncia_id', p_denuncia, 'status', p_status, 'resolucao', p_resolucao));
end;
$$;

-- Avaliações suspeitas (A04): sinais simples que valem uma olhada humana.
create or replace function public.admin_avaliacoes_suspeitas(p_dias integer default 30, p_incluir_ocultas boolean default false)
returns table (pedido_id uuid, codigo text, nota smallint, comentario text, fotos text[], oculta boolean, motivo_ocultacao text,
  cliente_id uuid, cliente text, profissional_id uuid, profissional text, criada_em timestamptz, sinais text[])
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  with base as (
    select a.*, p.codigo, p.aceito_em, p.iniciado_em, p.concluido_em, c.nome as cliente_nome, c.criado_em as cliente_desde, pf.nome as pro_nome,
      array_remove(array[
        case when a.nota <= 2 then 'Nota baixa (' || a.nota || ')' end,
        case when p.concluido_em - coalesce(p.iniciado_em, p.aceito_em) < interval '10 minutes' then 'Serviço concluído em menos de 10 min' end,
        case when (select count(*) from public.avaliacoes x where x.cliente_id = a.cliente_id and x.profissional_id = a.profissional_id
                   and x.criada_em > a.criada_em - interval '30 days' and x.criada_em <= a.criada_em) >= 3
          then 'Mesmo cliente avaliou este profissional 3+ vezes em 30 dias' end,
        case when (select count(*) from public.avaliacoes x where x.cliente_id = a.cliente_id
                   and x.criada_em between a.criada_em - interval '1 day' and a.criada_em) >= 4
          then 'Cliente fez 4+ avaliações em 24 h' end,
        case when a.criada_em - c.criado_em < interval '1 day' then 'Conta do cliente criada há menos de 1 dia' end,
        case when a.comentario ~* '(whats|zap|wpp|insta|@[a-z0-9_.]{3,}|https?://|www\.|\d{4}[ .-]?\d{4})' then 'Comentário com contato ou link' end,
        case when exists (select 1 from public.denuncias d where d.pedido_id = a.pedido_id) then 'Pedido com denúncia' end
      ], null) as s
    from public.avaliacoes a
    join public.pedidos p on p.id = a.pedido_id
    join public.perfis c on c.id = a.cliente_id
    join public.perfis pf on pf.id = a.profissional_id
    where a.criada_em > now() - make_interval(days => p_dias)
  )
  select b.pedido_id, b.codigo, b.nota, b.comentario, b.fotos, b.oculta, b.motivo_ocultacao, b.cliente_id, b.cliente_nome,
    b.profissional_id, b.pro_nome, b.criada_em, b.s
  from base b
  where (cardinality(b.s) > 0 and (p_incluir_ocultas or not b.oculta)) or (p_incluir_ocultas and b.oculta)
  order by b.oculta, cardinality(b.s) desc, b.criada_em desc
  limit 300;
end;
$$;

create or replace function public.admin_ocultar_avaliacao(p_pedido uuid, p_ocultar boolean, p_motivo text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pro uuid;
begin
  perform public.exigir_admin();
  if p_ocultar and coalesce(trim(p_motivo), '') = '' then perform public.erro('motivo_obrigatorio', 'Escreva o motivo para ocultar.'); end if;
  update public.avaliacoes set oculta = p_ocultar, motivo_ocultacao = case when p_ocultar then trim(p_motivo) end
  where pedido_id = p_pedido returning profissional_id into v_pro;
  if v_pro is null then perform public.erro('nao_encontrado', 'Avaliação não encontrada.'); end if;
  perform public.registrar_acao(case when p_ocultar then 'ocultar_avaliacao' else 'mostrar_avaliacao' end, v_pro::text,
    jsonb_build_object('pedido_id', p_pedido, 'motivo', p_motivo));
end;
$$;

-- Comunicado para um grupo (A08)
create or replace function public.admin_publico_comunicado(p_profissao text, p_regiao text, p_publico text)
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select pr.id from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where pe.excluido_em is null and pe.suspenso_em is null
    and case coalesce(p_publico, 'aprovados')
      when 'aprovados' then pr.status = 'aprovado'
      when 'disponiveis' then pr.status = 'aprovado' and pr.disponivel
      when 'em_analise' then pr.status in ('em_analise', 'rascunho', 'recusado')
      else pr.status <> 'suspenso' end
    and (p_profissao is null or p_profissao = '' or exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao))
    and (p_regiao is null or p_regiao = '' or pr.regiao_id = p_regiao)
$$;
revoke all on function public.admin_publico_comunicado(text, text, text) from public, anon, authenticated;

create or replace function public.admin_contar_publico(p_profissao text default null, p_regiao text default null, p_publico text default 'aprovados')
returns integer
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return (select count(*) from public.admin_publico_comunicado(p_profissao, p_regiao, p_publico));
end;
$$;

create or replace function public.admin_enviar_comunicado(p_titulo text, p_corpo text, p_profissao text default null,
  p_regiao text default null, p_publico text default 'aprovados')
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  perform public.exigir_admin();
  if coalesce(trim(p_titulo), '') = '' or coalesce(trim(p_corpo), '') = '' then
    perform public.erro('campos_obrigatorios', 'Escreva o título e a mensagem.');
  end if;
  insert into public.notificacoes (usuario_id, tipo, titulo, corpo, dados)
  select id, 'comunicado', left(trim(p_titulo), 120), left(trim(p_corpo), 1000), '{}'::jsonb
  from public.admin_publico_comunicado(p_profissao, p_regiao, p_publico) id;
  get diagnostics v_n = row_count;
  insert into public.comunicados (admin_id, profissao_id, regiao_id, publico, titulo, corpo, destinatarios)
  values (auth.uid(), nullif(p_profissao, ''), nullif(p_regiao, ''), coalesce(p_publico, 'aprovados'), trim(p_titulo), trim(p_corpo), v_n);
  perform public.registrar_acao('enviar_comunicado', null, jsonb_build_object('titulo', p_titulo, 'profissao', p_profissao, 'regiao', p_regiao,
    'publico', p_publico, 'destinatarios', v_n));
  return v_n;
end;
$$;

create or replace function public.admin_comunicados()
returns table (id bigint, titulo text, corpo text, profissao text, regiao text, publico text, destinatarios integer, admin text, criado_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select c.id, c.titulo, c.corpo, f.nome, r.nome, c.publico, c.destinatarios, a.nome, c.criado_em
  from public.comunicados c
  left join public.profissoes f on f.id = c.profissao_id
  left join public.regioes r on r.id = c.regiao_id
  left join public.perfis a on a.id = c.admin_id
  order by c.criado_em desc limit 100;
end;
$$;

-- Tabela de preços de referência (A09)
create or replace function public.admin_tabela_precos(p_profissao text)
returns table (especialidade_id bigint, especialidade text, faixa smallint, minimo numeric, maximo numeric, amostras integer,
  estimada boolean, ajuste_minimo numeric, ajuste_maximo numeric, ajustado_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select e.id, e.nome, fx.f::smallint, c.minimo, c.maximo, c.amostras, c.estimada, aj.minimo, aj.maximo, aj.atualizado_em
  from public.especialidades e
  cross join generate_series(1, 5) fx(f)
  cross join lateral public.faixa_preco_calculada(e.id, fx.f::smallint) c
  left join public.precos_referencia aj on aj.especialidade_id = e.id and aj.faixa = fx.f
  where e.profissao_id = p_profissao and e.aprovada
  order by e.ordem, e.nome, fx.f;
end;
$$;

create or replace function public.admin_ajustar_preco(p_especialidade bigint, p_faixa smallint, p_minimo numeric default null, p_maximo numeric default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if p_minimo is null and p_maximo is null then
    delete from public.precos_referencia where especialidade_id = p_especialidade and faixa = p_faixa;
  else
    if p_minimo is null or p_maximo is null or p_minimo <= 0 or p_maximo < p_minimo then
      perform public.erro('faixa_invalida', 'Informe um valor mínimo e um máximo, com o máximo maior ou igual ao mínimo.');
    end if;
    insert into public.precos_referencia (especialidade_id, faixa, minimo, maximo, atualizado_por)
    values (p_especialidade, p_faixa, p_minimo, p_maximo, auth.uid())
    on conflict (especialidade_id, faixa) do update set minimo = excluded.minimo, maximo = excluded.maximo,
      atualizado_por = excluded.atualizado_por, atualizado_em = now();
  end if;
  perform public.registrar_acao('ajustar_preco', p_especialidade::text, jsonb_build_object('faixa', p_faixa, 'minimo', p_minimo, 'maximo', p_maximo));
end;
$$;

-- Especialidades sugeridas pelos profissionais (aguardando a equipe)
create or replace function public.admin_especialidades_sugeridas()
returns table (id bigint, nome text, profissao_id text, profissao text, criada_por uuid, profissional text, usando bigint)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select e.id, e.nome, e.profissao_id, f.nome, e.criada_por, pe.nome,
    (select count(*) from public.profissional_especialidades x where x.especialidade_id = e.id)
  from public.especialidades e
  join public.profissoes f on f.id = e.profissao_id
  left join public.perfis pe on pe.id = e.criada_por
  where not e.aprovada
  order by f.ordem, e.nome;
end;
$$;

-- Registro de ações da equipe
create or replace function public.admin_registro(p_limite integer default 100)
returns table (id bigint, admin text, acao text, alvo text, alvo_nome text, dados jsonb, criada_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  return query
  select a.id, (select pe.nome from public.perfis pe where pe.id = a.admin_id), a.acao, a.alvo,
    (select pe.nome from public.perfis pe where pe.id::text = a.alvo), a.dados, a.criada_em
  from public.admin_acoes a order by a.criada_em desc limit p_limite;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissões das funções do painel
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_resumo(date)',
    'public.admin_buscas_por_regiao(date, date)',
    'public.admin_mapa_buscas(date, date, text, boolean)',
    'public.admin_cadastros(public.status_cadastro, text, integer)',
    'public.admin_usuarios(text, text, integer, integer)',
    'public.admin_usuario(uuid)',
    'public.admin_revisar_documento(bigint, boolean, text)',
    'public.admin_revisar_certificacao(bigint, boolean)',
    'public.admin_decidir_cadastro(uuid, boolean, text)',
    'public.admin_suspender(uuid, boolean, text)',
    'public.admin_pedidos(text, text, date, date, integer, integer)',
    'public.admin_pedido(uuid)',
    'public.admin_reclamacoes(text)',
    'public.admin_reclamacao_historico(bigint)',
    'public.admin_mediar_reclamacao(bigint, public.status_reclamacao, text, boolean)',
    'public.admin_emergencias(boolean)',
    'public.admin_atender_emergencia(bigint, text)',
    'public.admin_denuncias(text)',
    'public.admin_resolver_denuncia(bigint, public.status_denuncia, text)',
    'public.admin_avaliacoes_suspeitas(integer, boolean)',
    'public.admin_ocultar_avaliacao(uuid, boolean, text)',
    'public.admin_contar_publico(text, text, text)',
    'public.admin_enviar_comunicado(text, text, text, text, text)',
    'public.admin_comunicados()',
    'public.admin_tabela_precos(text)',
    'public.admin_ajustar_preco(bigint, smallint, numeric, numeric)',
    'public.admin_especialidades_sugeridas()',
    'public.admin_registro(integer)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated';
  end loop;
end;
$$;
revoke all on function public.faixa_preco(bigint, text) from public;
grant execute on function public.faixa_preco(bigint, text) to anon, authenticated;
revoke all on function public.perfil_profissional(uuid) from public, anon;
grant execute on function public.perfil_profissional(uuid) to authenticated;
revoke all on function public.recalcular_nota() from public, anon, authenticated;
