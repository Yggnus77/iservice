-- iService: regras de negócio no banco.
-- Toda mudança de estado de pedido passa por estas funções: os apps não
-- escrevem direto na tabela de pedidos.

-- ---------------------------------------------------------------------------
-- Utilitários
-- ---------------------------------------------------------------------------
create or replace function public.cfg(p_chave text)
returns jsonb
language sql stable
set search_path = public
as $$ select valor from public.app_config where chave = p_chave $$;

create or replace function public.cfg_num(p_chave text, p_padrao numeric)
returns numeric
language sql stable
set search_path = public
as $$ select coalesce((select (valor #>> '{}')::numeric from public.app_config where chave = p_chave), p_padrao) $$;

create or replace function public.cfg_bool(p_chave text, p_padrao boolean)
returns boolean
language sql stable
set search_path = public
as $$ select coalesce((select (valor #>> '{}')::boolean from public.app_config where chave = p_chave), p_padrao) $$;

create or replace function public.ponto(p_lat double precision, p_lng double precision)
returns extensions.geography
language sql immutable
set search_path = public, extensions
as $$ select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography $$;

-- Dígitos verificadores do CPF.
create or replace function public.cpf_valido(p_cpf text)
returns boolean
language plpgsql immutable
set search_path = public
as $$
declare
  d int[];
  s int;
  dv1 int;
  dv2 int;
begin
  if p_cpf is null or p_cpf !~ '^\d{11}$' or p_cpf ~ '^(\d)\1{10}$' then
    return false;
  end if;
  d := regexp_split_to_array(p_cpf, '')::int[];
  s := 0;
  for i in 1..9 loop s := s + d[i] * (11 - i); end loop;
  dv1 := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  s := 0;
  for i in 1..10 loop s := s + coalesce(case when i = 10 then dv1 else d[i] end, 0) * (12 - i); end loop;
  dv2 := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  return d[10] = dv1 and d[11] = dv2;
end;
$$;

alter table public.perfis add constraint perfis_cpf_valido check (cpf is null or public.cpf_valido(cpf));

create or replace function public.e_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$ select coalesce((select e_admin from public.perfis where id = auth.uid()), false) $$;

create or replace function public.erro(p_codigo text, p_mensagem text)
returns void
language plpgsql
as $$
begin
  -- O código vai em DETAIL para os apps traduzirem; a mensagem já é legível.
  raise exception using errcode = 'P0001', message = p_mensagem, detail = p_codigo;
end;
$$;

create or replace function public.notificar(p_usuario uuid, p_tipo text, p_titulo text, p_corpo text, p_dados jsonb default '{}')
returns void
language sql
set search_path = public
as $$ insert into public.notificacoes (usuario_id, tipo, titulo, corpo, dados) values (p_usuario, p_tipo, p_titulo, p_corpo, p_dados) $$;

create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'reclamacoes' then
    new.atualizada_em := now();
  else
    new.atualizado_em := now();
  end if;
  return new;
end;
$$;

create trigger perfis_atualizado before update on public.perfis for each row execute function public.tocar_atualizado_em();
create trigger profissionais_atualizado before update on public.profissionais for each row execute function public.tocar_atualizado_em();
create trigger reclamacoes_atualizada before update on public.reclamacoes for each row execute function public.tocar_atualizado_em();

-- ---------------------------------------------------------------------------
-- Conta: perfil criado junto com o usuário de autenticação
-- ---------------------------------------------------------------------------
create or replace function public.novo_usuario()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_app text := coalesce(new.raw_user_meta_data ->> 'app', 'cliente');
  v_indicador uuid;
begin
  insert into public.perfis (id, nome, email, telefone, codigo_indicacao, e_cliente, e_profissional)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'nome', ''),
    new.email,
    nullif(regexp_replace(coalesce(to_jsonb(new) ->> 'phone', ''), '\D', '', 'g'), ''),
    upper(substr(md5(new.id::text), 1, 7)),
    false,
    false
  );

  if v_app = 'profissional' then
    insert into public.profissionais (id) values (new.id);
  end if;

  select id into v_indicador from public.perfis
  where codigo_indicacao = upper(new.raw_user_meta_data ->> 'indicacao') and id <> new.id;
  if v_indicador is not null then
    insert into public.indicacoes (indicado_id, indicador_id) values (new.id, v_indicador);
  end if;
  return new;
end;
$$;

create trigger ao_criar_usuario after insert on auth.users for each row execute function public.novo_usuario();

-- Dados completos do próprio usuário (CPF e afins não são legíveis por outros).
create or replace function public.meu_perfil()
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'perfil', to_jsonb(p.*),
    'enderecos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'rotulo', e.rotulo, 'regiao_id', e.regiao_id, 'logradouro', e.logradouro, 'bloco', e.bloco,
        'numero', e.numero, 'complemento', e.complemento, 'referencia', e.referencia, 'cep', e.cep,
        'cidade', e.cidade, 'uf', e.uf, 'principal', e.principal,
        'lat', extensions.st_y(e.localizacao::extensions.geometry), 'lng', extensions.st_x(e.localizacao::extensions.geometry)
      ) order by e.principal desc, e.id)
      from public.enderecos e where e.usuario_id = p.id), '[]'::jsonb),
    'profissional', (
      select to_jsonb(pr.*) - 'area_centro' || jsonb_build_object(
        'area_lat', extensions.st_y(pr.area_centro::extensions.geometry),
        'area_lng', extensions.st_x(pr.area_centro::extensions.geometry))
      from public.profissionais pr where pr.id = p.id),
    'pontos', coalesce((select sum(pontos) from public.pontos where usuario_id = p.id), 0)
  )
  from public.perfis p
  where p.id = auth.uid()
$$;

create or replace function public.salvar_endereco(
  p_logradouro text, p_lat double precision, p_lng double precision,
  p_regiao_id text default null, p_bloco text default null, p_numero text default null,
  p_complemento text default null, p_referencia text default null, p_cep text default null,
  p_cidade text default 'Brasília', p_uf text default 'DF', p_rotulo text default 'Casa',
  p_principal boolean default true, p_id bigint default null
)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if p_principal then
    update public.enderecos set principal = false where usuario_id = auth.uid() and principal and id is distinct from p_id;
  end if;
  if p_id is null then
    insert into public.enderecos (usuario_id, rotulo, regiao_id, logradouro, bloco, numero, complemento, referencia, cep, cidade, uf, localizacao, principal)
    values (auth.uid(), p_rotulo, p_regiao_id, p_logradouro, p_bloco, p_numero, p_complemento, p_referencia,
            nullif(regexp_replace(coalesce(p_cep, ''), '\D', '', 'g'), ''), p_cidade, p_uf, public.ponto(p_lat, p_lng), p_principal)
    returning id into v_id;
  else
    update public.enderecos set rotulo = p_rotulo, regiao_id = p_regiao_id, logradouro = p_logradouro, bloco = p_bloco,
      numero = p_numero, complemento = p_complemento, referencia = p_referencia,
      cep = nullif(regexp_replace(coalesce(p_cep, ''), '\D', '', 'g'), ''), cidade = p_cidade, uf = p_uf,
      localizacao = public.ponto(p_lat, p_lng), principal = p_principal
    where id = p_id and usuario_id = auth.uid()
    returning id into v_id;
    if v_id is null then perform public.erro('endereco_invalido', 'Endereço não encontrado.'); end if;
  end if;
  return v_id;
end;
$$;

-- Confere o que é comum aos dois cadastros: foto, nome, nascimento (18+), CPF, telefone e endereço.
create or replace function public.pendencias_basicas(p_id uuid)
returns text[]
language sql stable
set search_path = public
as $$
  select array_remove(array[
    case when coalesce(p.foto_url, '') = '' then 'foto' end,
    case when length(trim(p.nome)) < 3 or position(' ' in trim(p.nome)) = 0 then 'nome' end,
    case when p.nascimento is null or p.nascimento > (current_date - interval '18 years') then 'nascimento' end,
    case when not public.cpf_valido(p.cpf) then 'cpf' end,
    case when p.telefone is null then 'telefone' end,
    case when not exists (select 1 from public.enderecos e where e.usuario_id = p.id) then 'endereco' end
  ], null)
  from public.perfis p where p.id = p_id
$$;

create or replace function public.concluir_cadastro_cliente()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_pend text[] := public.pendencias_basicas(auth.uid());
begin
  if v_pend is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if cardinality(v_pend) > 0 then
    return jsonb_build_object('ok', false, 'pendencias', to_jsonb(v_pend));
  end if;
  update public.perfis set e_cliente = true where id = auth.uid();
  return jsonb_build_object('ok', true, 'pendencias', '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Cadastro do profissional
-- ---------------------------------------------------------------------------
create or replace function public.limitar_profissoes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (select count(*) from public.profissional_profissoes where profissional_id = new.profissional_id) >= public.cfg_num('max_profissoes', 3) then
    perform public.erro('limite_profissoes', 'Você pode escolher até 3 profissões.');
  end if;
  return new;
end;
$$;
create trigger limitar_profissoes before insert on public.profissional_profissoes for each row execute function public.limitar_profissoes();

-- Profissional sugere uma especialidade que não está na lista: entra já marcada,
-- visível no perfil dele, e o admin decide se vira sugestão para todos.
create or replace function public.sugerir_especialidade(p_profissao text, p_nome text)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_nome text := initcap(trim(p_nome));
begin
  if not exists (select 1 from public.profissional_profissoes where profissional_id = auth.uid() and profissao_id = p_profissao) then
    perform public.erro('profissao_nao_marcada', 'Marque a profissão antes de sugerir uma especialidade.');
  end if;
  if length(v_nome) < 3 then perform public.erro('nome_curto', 'Escreva o nome da especialidade.'); end if;
  select id into v_id from public.especialidades where profissao_id = p_profissao and lower(extensions.unaccent(nome)) = lower(extensions.unaccent(v_nome));
  if v_id is null then
    insert into public.especialidades (profissao_id, nome, sugerida, aprovada, criada_por, ordem)
    values (p_profissao, v_nome, false, false, auth.uid(), 99) returning id into v_id;
  end if;
  insert into public.profissional_especialidades (profissional_id, especialidade_id) values (auth.uid(), v_id) on conflict do nothing;
  return v_id;
end;
$$;

create or replace function public.pendencias_profissional(p_id uuid)
returns text[]
language sql stable
set search_path = public
as $$
  select coalesce(public.pendencias_basicas(p_id), '{}') || array_remove(array[
    case when pr.area_centro is null then 'area_atendimento' end,
    case when not exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = p_id) then 'profissao' end,
    case when exists (
      select 1 from public.profissional_profissoes pp
      where pp.profissional_id = p_id and not exists (
        select 1 from public.profissional_especialidades pe join public.especialidades e on e.id = pe.especialidade_id
        where pe.profissional_id = p_id and e.profissao_id = pp.profissao_id and pe.preco is not null)
    ) then 'especialidades_e_precos' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'documento_frente' and d.status <> 'recusado') then 'documento' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'selfie_documento' and d.status <> 'recusado') then 'selfie' end,
    case when exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = p_id and f.exige_antecedentes)
      and not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'antecedentes' and d.status <> 'recusado') then 'antecedentes' end
  ], null)
  from public.profissionais pr where pr.id = p_id
$$;

create or replace function public.ativar_profissional()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  insert into public.profissionais (id) values (auth.uid()) on conflict do nothing;
end;
$$;

create or replace function public.definir_area_atendimento(p_lat double precision, p_lng double precision, p_raio_km numeric, p_regiao_id text default null)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  update public.profissionais
  set area_centro = public.ponto(p_lat, p_lng), area_raio_km = least(greatest(p_raio_km, 1), 50), regiao_id = coalesce(p_regiao_id, regiao_id)
  where id = auth.uid();
  if not found then perform public.erro('nao_profissional', 'Cadastro de profissional não encontrado.'); end if;
end;
$$;

create or replace function public.enviar_cadastro_profissional()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_pend text[];
  v_status public.status_cadastro;
begin
  select status into v_status from public.profissionais where id = auth.uid();
  if v_status is null then perform public.erro('nao_profissional', 'Cadastro de profissional não encontrado.'); end if;
  if v_status not in ('rascunho', 'recusado') then
    return jsonb_build_object('ok', true, 'status', v_status, 'pendencias', '[]'::jsonb);
  end if;
  v_pend := public.pendencias_profissional(auth.uid());
  if cardinality(v_pend) > 0 then
    return jsonb_build_object('ok', false, 'status', v_status, 'pendencias', to_jsonb(v_pend));
  end if;
  update public.profissionais set status = 'em_analise', motivo_status = null where id = auth.uid();
  update public.perfis set e_profissional = true where id = auth.uid();
  return jsonb_build_object('ok', true, 'status', 'em_analise', 'pendencias', '[]'::jsonb);
end;
$$;

create or replace function public.admin_decidir_cadastro(p_profissional uuid, p_aprovar boolean, p_motivo text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.e_admin() then perform public.erro('sem_permissao', 'Apenas a equipe iService pode fazer isso.'); end if;
  if p_aprovar then
    update public.documentos set status = 'aprovado', revisado_em = now(), revisado_por = auth.uid()
    where profissional_id = p_profissional and status = 'pendente';
    update public.profissionais set status = 'aprovado', verificado = true, motivo_status = null, aprovado_em = coalesce(aprovado_em, now())
    where id = p_profissional;
    perform public.notificar(p_profissional, 'cadastro_aprovado', 'Cadastro aprovado!', 'Ative o modo disponível para começar a receber pedidos.');
  else
    update public.profissionais set status = 'recusado', motivo_status = p_motivo where id = p_profissional;
    perform public.notificar(p_profissional, 'cadastro_recusado', 'Seu cadastro precisa de ajustes', coalesce(p_motivo, 'Confira os documentos enviados.'));
  end if;
end;
$$;

create or replace function public.definir_disponivel(p_disponivel boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_status public.status_cadastro;
begin
  select status into v_status from public.profissionais where id = auth.uid();
  if v_status is distinct from 'aprovado' and p_disponivel then
    perform public.erro('cadastro_nao_aprovado', 'Seu cadastro ainda está em análise.');
  end if;
  update public.profissionais set disponivel = p_disponivel where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- Busca, alcance e ordenação justa
-- ---------------------------------------------------------------------------
-- Em atendimento = do aceite até concluir. Some de todas as buscas, em todas
-- as profissões. Um horário combinado aceito só conta a partir do "a caminho".
create or replace function public.em_atendimento(p_profissional uuid)
returns boolean
language sql stable
set search_path = public
as $$
  select exists (
    select 1 from public.pedidos
    where profissional_id = p_profissional
      and (status in ('a_caminho', 'em_atendimento') or (status = 'aceito' and quando <> 'combinado'))
  )
$$;

-- Alcance em km. O plano só muda o alcance, nunca a ordem. Com a cobrança
-- desligada (fase grátis) vale o raio escolhido pelo profissional.
create or replace function public.alcance_km(p_raio numeric, p_plano public.plano_profissional, p_valido_ate timestamptz)
returns numeric
language sql stable
set search_path = public
as $$
  select case
    when not public.cfg_bool('cobranca_ativa', false) then p_raio
    when p_plano <> 'gratis' and coalesce(p_valido_ate, 'infinity') > now()
      then least(p_raio, public.cfg_num('alcance_' || p_plano::text || '_km', case p_plano when 'vip' then 20 else 50 end))
    else least(p_raio, public.cfg_num('alcance_gratis_km', 10))
  end
$$;

-- Lista de profissionais para um pedido. Regras:
--  * só aprovados, disponíveis, livres e que alcançam o local do pedido;
--  * ordem padrão pela qualidade: nota, nº de avaliações, serviços, distância;
--  * quem tem menos de 5 avaliações é "novo" e entra intercalado (1 a cada 2);
--  * fase de lançamento (menos de 3 com 5+ avaliações): todos em rodízio, mesma visibilidade;
--  * p_rodizio muda a cada busca para girar o rodízio.
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
as $$
declare
  v_local extensions.geography := public.ponto(p_lat, p_lng);
  v_min_aval int := public.cfg_num('min_avaliacoes_ranking', 5);
  v_min_top int := public.cfg_num('min_profissionais_ranking', 3);
  v_ntop int;
  v_lanc boolean;
begin
  create temporary table if not exists _cand (
    profissional_id uuid, nome text, foto_url text, nota_media numeric, total_avaliacoes integer,
    servicos_concluidos integer, anos_experiencia smallint, verificado boolean, distancia_km numeric,
    novo boolean, preco_a_partir numeric, especialidades text[], favorito boolean, sorteio text
  ) on commit drop;
  truncate _cand;

  insert into _cand
  select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos, pr.anos_experiencia, pr.verificado,
    round((extensions.st_distance(pr.area_centro, v_local) / 1000)::numeric, 1),
    pr.total_avaliacoes < v_min_aval,
    (select min(x.preco) from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao and (p_especialidade is null or e.id = p_especialidade)),
    array(select e.nome from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
      where x.profissional_id = pr.id and e.profissao_id = p_profissao order by e.ordem, e.nome),
    exists (select 1 from public.favoritos f where f.cliente_id = auth.uid() and f.profissional_id = pr.id),
    md5(pr.id::text || p_rodizio::text || current_date::text)
  from public.profissionais pr
  join public.perfis pe on pe.id = pr.id
  join public.profissional_profissoes pp on pp.profissional_id = pr.id and pp.profissao_id = p_profissao
  where pr.status = 'aprovado'
    and pr.disponivel
    and pr.area_centro is not null
    and pr.id is distinct from auth.uid()
    and extensions.st_dwithin(pr.area_centro, v_local, public.alcance_km(pr.area_raio_km, pr.plano, pr.plano_valido_ate) * 1000)
    and (p_especialidade is null or exists (
      select 1 from public.profissional_especialidades x where x.profissional_id = pr.id and x.especialidade_id = p_especialidade))
    and not public.em_atendimento(pr.id);

  select count(*) filter (where not c.novo) into v_ntop from _cand c;
  v_lanc := v_ntop < v_min_top;

  return query
  with ordenado as (
    select c.*,
      -- posição de cada um dentro do seu grupo (com 5+ avaliações ou novo)
      row_number() over (partition by c.novo order by c.nota_media desc, c.total_avaliacoes desc, c.servicos_concluidos desc, c.distancia_km) - 1 as k_top,
      row_number() over (partition by c.novo order by c.sorteio) - 1 as k_rodizio,
      row_number() over (order by c.sorteio) as k_lanc
    from _cand c
  ),
  chave as (
    select o.*,
      case
        when p_ordem = 'distancia' then o.distancia_km * 1000
        when v_lanc then o.k_lanc
        -- dois bem avaliados, um novo, dois bem avaliados, um novo...
        when not o.novo then o.k_top + floor(o.k_top / 2.0)
        when o.k_rodizio < floor(v_ntop / 2.0) then o.k_rodizio * 3 + 2
        else 1000000 + o.k_rodizio
      end as ordem_final
    from ordenado o
  )
  select ch.profissional_id, ch.nome, ch.foto_url, ch.nota_media, ch.total_avaliacoes, ch.servicos_concluidos, ch.anos_experiencia,
    ch.verificado, ch.distancia_km, ch.novo, ch.preco_a_partir, ch.especialidades, ch.favorito, v_lanc,
    (row_number() over (order by ch.ordem_final, ch.distancia_km))::int
  from chave ch
  order by ch.ordem_final, ch.distancia_km
  limit p_limite;
end;
$$;

-- "Top da sua região": melhores avaliados perto do cliente, uma vez cada,
-- em todas as profissões ou em uma só.
create or replace function public.top_regiao(
  p_lat double precision,
  p_lng double precision,
  p_profissao text default null,
  p_limite integer default 10,
  p_rodizio integer default 0
)
returns table (
  profissional_id uuid,
  nome text,
  foto_url text,
  profissao_id text,
  nota_media numeric,
  total_avaliacoes integer,
  servicos_concluidos integer,
  distancia_km numeric,
  fase_lancamento boolean,
  posicao integer
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_local extensions.geography := public.ponto(p_lat, p_lng);
  v_raio numeric := public.cfg_num('raio_top_regiao_km', 15);
  v_min_aval int := public.cfg_num('min_avaliacoes_ranking', 5);
  v_lanc boolean;
begin
  select count(*) < public.cfg_num('min_profissionais_ranking', 3) into v_lanc
  from public.profissionais pr
  where pr.status = 'aprovado' and pr.total_avaliacoes >= v_min_aval and pr.area_centro is not null
    and extensions.st_dwithin(pr.area_centro, v_local, v_raio * 1000)
    and (p_profissao is null or exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao));

  return query
  select t.id, t.nome, t.foto_url, t.profissao_id, t.nota_media, t.total_avaliacoes, t.servicos_concluidos, t.dist, v_lanc,
    (row_number() over (order by
      case when v_lanc then md5(t.id::text || p_rodizio::text || current_date::text) end,
      t.nota_media desc, t.servicos_concluidos desc, t.total_avaliacoes desc, t.dist))::int
  from (
    select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.servicos_concluidos,
      round((extensions.st_distance(pr.area_centro, v_local) / 1000)::numeric, 1) as dist,
      coalesce(
        (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao),
        (select pp.profissao_id from public.profissional_profissoes pp where pp.profissional_id = pr.id order by pp.principal desc, pp.profissao_id limit 1)
      ) as profissao_id
    from public.profissionais pr
    join public.perfis pe on pe.id = pr.id
    where pr.status = 'aprovado' and pr.disponivel and pr.area_centro is not null
      and extensions.st_dwithin(pr.area_centro, v_local, least(v_raio, public.alcance_km(pr.area_raio_km, pr.plano, pr.plano_valido_ate)) * 1000)
      and not public.em_atendimento(pr.id)
      and (v_lanc or pr.total_avaliacoes >= v_min_aval)
      and (p_profissao is null or exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = pr.id and pp.profissao_id = p_profissao))
  ) t
  order by 10
  limit p_limite;
end;
$$;

-- Perfil público do profissional, visto pelo cliente.
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
        where av.profissional_id = pr.id order by av.criada_em desc limit 10) s), '[]'::jsonb),
    'distribuicao_notas', (
      select jsonb_build_object('5', count(*) filter (where nota = 5), '4', count(*) filter (where nota = 4),
        '3', count(*) filter (where nota = 3), '2', count(*) filter (where nota = 2), '1', count(*) filter (where nota = 1))
      from public.avaliacoes where profissional_id = pr.id)
  )
  from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where pr.id = p_id and (pr.status = 'aprovado' or pr.id = auth.uid() or public.e_admin())
$$;

-- Faixa comum de preço (P25 a P75) de uma especialidade na faixa de região.
-- Com poucos preços reais usa a referência base ajustada pela região.
create or replace function public.faixa_preco(p_especialidade bigint, p_regiao text)
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_faixa smallint := coalesce((select faixa_preco from public.regioes where id = p_regiao), 2);
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
  join public.regioes r on r.id = pr.regiao_id and r.faixa_preco = v_faixa
  where x.especialidade_id = p_especialidade and x.preco is not null;

  if v_n >= public.cfg_num('min_amostras_preco', 5) then
    return query select round(v_p25 / 5) * 5, round(v_p75 / 5) * 5, v_n, false;
    return;
  end if;

  select f.preco_base + greatest(e.ordem, 0) * 20 into v_base
  from public.especialidades e join public.profissoes f on f.id = e.profissao_id where e.id = p_especialidade;
  v_fator := coalesce((public.cfg('fator_faixa_preco') ->> v_faixa::text)::numeric, 1);
  return query select round(v_base * v_fator * 0.9 / 5) * 5, round(v_base * v_fator * 1.8 / 5) * 5, coalesce(v_n, 0), true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pedidos
-- ---------------------------------------------------------------------------
create or replace function public.criar_pedido(
  p_profissional uuid,
  p_profissao text,
  p_endereco_id bigint,
  p_quando public.quando_pedido,
  p_especialidade bigint default null,
  p_descricao text default '',
  p_janela text default null,
  p_combinado_para timestamptz default null,
  p_fotos text[] default '{}'
)
returns public.pedidos
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_end public.enderecos;
  v_pro public.profissionais;
  v_ped public.pedidos;
  v_nome_cliente text;
  v_preco numeric;
  v_dist numeric;
begin
  if v_uid is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if not coalesce((select e_cliente from public.perfis where id = v_uid), false) then
    perform public.erro('cadastro_incompleto', 'Complete seu cadastro, com foto, para fazer pedidos.');
  end if;
  if v_uid = p_profissional then perform public.erro('pedido_proprio', 'Você não pode contratar a si mesmo.'); end if;

  select * into v_end from public.enderecos where id = p_endereco_id and usuario_id = v_uid;
  if v_end.id is null then perform public.erro('endereco_invalido', 'Escolha um endereço válido.'); end if;

  select * into v_pro from public.profissionais where id = p_profissional;
  if v_pro.id is null or v_pro.status <> 'aprovado' then
    perform public.erro('profissional_indisponivel', 'Este profissional não está disponível.');
  end if;
  if not exists (select 1 from public.profissional_profissoes where profissional_id = p_profissional and profissao_id = p_profissao) then
    perform public.erro('profissao_invalida', 'Este profissional não atende essa profissão.');
  end if;
  if p_especialidade is not null then
    select x.preco into v_preco from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
    where x.profissional_id = p_profissional and x.especialidade_id = p_especialidade and e.profissao_id = p_profissao;
    if not found then perform public.erro('especialidade_invalida', 'Este profissional não oferece essa especialidade.'); end if;
  end if;

  v_dist := round((extensions.st_distance(v_pro.area_centro, v_end.localizacao) / 1000)::numeric, 2);
  if v_pro.area_centro is null or v_dist > public.alcance_km(v_pro.area_raio_km, v_pro.plano, v_pro.plano_valido_ate) then
    perform public.erro('fora_da_area', 'Este profissional não atende o seu endereço.');
  end if;

  if p_quando in ('agora', 'hoje') then
    if not v_pro.disponivel or public.em_atendimento(p_profissional) then
      perform public.erro('profissional_ocupado', 'Este profissional acabou de ficar indisponível. Escolha outro.');
    end if;
  else
    if p_combinado_para < now() + interval '30 minutes' or p_combinado_para > now() + make_interval(days => public.cfg_num('dias_max_combinado', 7)::int) then
      perform public.erro('horario_invalido', 'Escolha um horário entre daqui a 30 minutos e os próximos 7 dias.');
    end if;
  end if;

  if exists (select 1 from public.pedidos where cliente_id = v_uid and status = 'solicitado' and responder_ate > now()) then
    perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando resposta.');
  end if;

  insert into public.pedidos (
    cliente_id, profissional_id, profissao_id, especialidade_id, descricao, fotos, quando, janela, combinado_para,
    endereco_id, endereco_texto, regiao_id, localizacao, distancia_km, preco_informado, taxa_urgencia, responder_ate
  ) values (
    v_uid, p_profissional, p_profissao, p_especialidade, coalesce(p_descricao, ''), coalesce(p_fotos, '{}'), p_quando,
    case when p_quando = 'hoje' then coalesce(p_janela, 'Hoje') else p_janela end,
    case when p_quando = 'combinado' then p_combinado_para end,
    v_end.id,
    concat_ws(', ', v_end.logradouro, v_end.bloco, v_end.numero, v_end.complemento, v_end.cidade || '/' || v_end.uf),
    v_end.regiao_id, v_end.localizacao, v_dist, v_preco,
    case when p_quando = 'agora' then public.cfg_num('taxa_urgencia', 15) else 0 end,
    now() + make_interval(mins => public.cfg_num('prazo_resposta_min', 10)::int)
  ) returning * into v_ped;

  update public.profissionais set pedidos_recebidos = pedidos_recebidos + 1 where id = p_profissional;
  select split_part(nome, ' ', 1) into v_nome_cliente from public.perfis where id = v_uid;
  perform public.notificar(p_profissional, 'pedido_novo', 'Novo pedido de ' || v_nome_cliente,
    'Você tem ' || public.cfg_num('prazo_resposta_min', 10) || ' minutos para responder.', jsonb_build_object('pedido_id', v_ped.id));
  return v_ped;
end;
$$;

-- Encerra pedidos sem resposta no prazo. Roda a cada minuto (pg_cron) e
-- também antes de qualquer resposta, para nunca aceitar fora do prazo.
create or replace function public.expirar_pedidos()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    update public.pedidos set status = 'expirado', encerrado_em = now(), motivo = 'Sem resposta no prazo'
    where status = 'solicitado' and responder_ate <= now()
    returning id, cliente_id, profissional_id
  loop
    n := n + 1;
    update public.profissionais set pedidos_perdidos = pedidos_perdidos + 1 where id = r.profissional_id;
    perform public.notificar(r.cliente_id, 'pedido_expirado', 'O profissional não respondeu a tempo',
      'Escolha outro profissional recomendado para o seu serviço.', jsonb_build_object('pedido_id', r.id));
    perform public.notificar(r.profissional_id, 'pedido_expirado', 'Pedido expirado',
      'O prazo de resposta acabou e o pedido foi encerrado.', jsonb_build_object('pedido_id', r.id));
  end loop;
  return n;
end;
$$;

create or replace function public.responder_pedido(p_pedido uuid, p_aceitar boolean, p_motivo text default null)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  perform public.expirar_pedidos();
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  -- Fora do prazo não aceita: devolve o pedido já expirado (sem erro, para a expiração ficar gravada).
  if v_ped.status = 'expirado' then return v_ped; end if;
  if v_ped.status <> 'solicitado' then perform public.erro('pedido_ja_respondido', 'Este pedido já foi respondido.'); end if;
  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();

  if p_aceitar then
    if v_ped.quando <> 'combinado' and public.em_atendimento(auth.uid()) then
      perform public.erro('em_atendimento', 'Conclua o atendimento atual antes de aceitar outro pedido agora.');
    end if;
    update public.pedidos set status = 'aceito', aceito_em = now() where id = p_pedido returning * into v_ped;
    update public.profissionais set pedidos_aceitos = pedidos_aceitos + 1 where id = auth.uid();
    perform public.notificar(v_ped.cliente_id, 'pedido_aceito', v_nome || ' aceitou seu pedido',
      case when v_ped.quando = 'combinado' then 'Horário confirmado.' else 'Acompanhe pelo app.' end, jsonb_build_object('pedido_id', v_ped.id));
  else
    update public.pedidos set status = 'recusado', encerrado_em = now(), motivo = p_motivo where id = p_pedido returning * into v_ped;
    update public.profissionais set pedidos_perdidos = pedidos_perdidos + 1 where id = auth.uid();
    perform public.notificar(v_ped.cliente_id, 'pedido_recusado', v_nome || ' não pode atender agora',
      'Escolha outro profissional recomendado para o seu serviço.', jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;

-- Profissional avança: aceito -> a caminho -> em atendimento -> concluído (com o valor cobrado).
create or replace function public.avancar_pedido(p_pedido uuid, p_status public.status_pedido, p_valor numeric default null, p_forma_pagamento text default null)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
  v_indicador uuid;
begin
  select * into v_ped from public.pedidos where id = p_pedido and profissional_id = auth.uid() for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if not (
    (v_ped.status = 'aceito' and p_status in ('a_caminho', 'em_atendimento'))
    or (v_ped.status = 'a_caminho' and p_status = 'em_atendimento')
    or (v_ped.status = 'em_atendimento' and p_status = 'concluido')
  ) then
    perform public.erro('transicao_invalida', 'Não é possível mudar o pedido para essa etapa agora.');
  end if;
  -- Um atendimento por vez: não sai para outro local enquanto atende alguém.
  if v_ped.status = 'aceito' and exists (
    select 1 from public.pedidos o
    where o.profissional_id = auth.uid() and o.id <> p_pedido
      and (o.status in ('a_caminho', 'em_atendimento') or (o.status = 'aceito' and o.quando <> 'combinado'))
  ) then
    perform public.erro('em_atendimento', 'Conclua o atendimento atual antes de iniciar outro.');
  end if;
  if p_status = 'concluido' and (p_valor is null or p_valor < 0) then
    perform public.erro('valor_obrigatorio', 'Informe o valor cobrado para concluir.');
  end if;

  update public.pedidos set
    status = p_status,
    a_caminho_em = case when p_status = 'a_caminho' then now() else a_caminho_em end,
    iniciado_em = case when p_status = 'em_atendimento' then now() else iniciado_em end,
    concluido_em = case when p_status = 'concluido' then now() else concluido_em end,
    valor_cobrado = case when p_status = 'concluido' then p_valor else valor_cobrado end,
    forma_pagamento = coalesce(p_forma_pagamento, forma_pagamento)
  where id = p_pedido returning * into v_ped;

  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = auth.uid();
  if p_status = 'a_caminho' then
    perform public.notificar(v_ped.cliente_id, 'pedido_a_caminho', v_nome || ' está a caminho', 'Acompanhe pelo mapa.', jsonb_build_object('pedido_id', v_ped.id));
  elsif p_status = 'em_atendimento' then
    perform public.notificar(v_ped.cliente_id, 'pedido_em_atendimento', v_nome || ' chegou', 'O atendimento começou.', jsonb_build_object('pedido_id', v_ped.id));
  else
    update public.profissionais set servicos_concluidos = servicos_concluidos + 1 where id = auth.uid();
    insert into public.pontos (usuario_id, pontos, motivo, pedido_id)
    values (v_ped.cliente_id, public.cfg_num('pontos_por_servico', 10)::int, 'Serviço concluído', v_ped.id);
    perform public.notificar(v_ped.cliente_id, 'pedido_concluido', 'Serviço concluído!', 'Conte como foi e avalie ' || v_nome || '.', jsonb_build_object('pedido_id', v_ped.id));
    -- Indicação: na primeira contratação concluída do indicado, o indicador ganha pontos.
    update public.indicacoes set recompensado = true where indicado_id = v_ped.cliente_id and not recompensado
    returning indicador_id into v_indicador;
    if v_indicador is not null then
      insert into public.pontos (usuario_id, pontos, motivo) values (v_indicador, public.cfg_num('pontos_indicacao', 50)::int, 'Indicação de amigo');
    end if;
  end if;
  return v_ped;
end;
$$;

create or replace function public.cancelar_pedido(p_pedido uuid, p_motivo text default null)
returns public.pedidos
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_pelo_pro boolean;
begin
  select * into v_ped from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id) for update;
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  v_pelo_pro := v_ped.profissional_id = auth.uid();
  if v_ped.status not in ('solicitado', 'aceito', 'a_caminho') or (v_pelo_pro and v_ped.status = 'solicitado') then
    perform public.erro('nao_cancelavel', 'Este pedido não pode mais ser cancelado.');
  end if;
  update public.pedidos set status = 'cancelado', encerrado_em = now(), motivo = p_motivo, cancelado_por = auth.uid()
  where id = p_pedido returning * into v_ped;
  if v_pelo_pro then
    update public.profissionais set cancelados_pelo_profissional = cancelados_pelo_profissional + 1 where id = auth.uid();
    perform public.notificar(v_ped.cliente_id, 'pedido_cancelado', 'O profissional cancelou o atendimento',
      'Escolha outro profissional recomendado. Sentimos muito pelo transtorno.', jsonb_build_object('pedido_id', v_ped.id));
  else
    perform public.notificar(v_ped.profissional_id, 'pedido_cancelado', 'O cliente cancelou o pedido',
      coalesce(p_motivo, 'O pedido foi cancelado.'), jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;

-- Lista de pedidos do usuário, já com o nome e a foto da outra parte.
create or replace function public.meus_pedidos(p_papel text default 'cliente', p_grupo text default 'todos', p_limite integer default 50)
returns table (
  id uuid, codigo text, status public.status_pedido, quando public.quando_pedido, janela text, combinado_para timestamptz,
  profissao_id text, especialidade text, descricao text, endereco_texto text, distancia_km numeric,
  preco_informado numeric, taxa_urgencia numeric, valor_cobrado numeric, responder_ate timestamptz, criado_em timestamptz,
  concluido_em timestamptz, outra_parte_id uuid, outra_parte_nome text, outra_parte_foto text, avaliado boolean, nao_lidas integer
)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.codigo, p.status, p.quando, p.janela, p.combinado_para, p.profissao_id, e.nome, p.descricao, p.endereco_texto,
    p.distancia_km, p.preco_informado, p.taxa_urgencia, p.valor_cobrado, p.responder_ate, p.criado_em, p.concluido_em,
    o.id, o.nome, o.foto_url,
    exists (select 1 from public.avaliacoes a where a.pedido_id = p.id),
    (select count(*) from public.mensagens m where m.pedido_id = p.id and m.autor_id <> auth.uid() and m.lida_em is null)::int
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

-- ---------------------------------------------------------------------------
-- Avaliações (atualizam a nota do profissional)
-- ---------------------------------------------------------------------------
create or replace function public.avaliar_pedido(p_pedido uuid, p_nota smallint, p_comentario text default null, p_fotos text[] default '{}')
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
begin
  select * into v_ped from public.pedidos where id = p_pedido and cliente_id = auth.uid();
  if v_ped.id is null then perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.'); end if;
  if v_ped.status <> 'concluido' then perform public.erro('nao_concluido', 'Só é possível avaliar serviços concluídos.'); end if;
  if v_ped.concluido_em < now() - interval '30 days' then perform public.erro('prazo_avaliacao', 'O prazo para avaliar este serviço acabou.'); end if;
  insert into public.avaliacoes (pedido_id, cliente_id, profissional_id, nota, comentario, fotos)
  values (p_pedido, auth.uid(), v_ped.profissional_id, p_nota, nullif(trim(p_comentario), ''), coalesce(p_fotos, '{}'))
  on conflict (pedido_id) do update set nota = excluded.nota, comentario = excluded.comentario, fotos = excluded.fotos;
end;
$$;

create or replace function public.recalcular_nota()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_pro uuid := coalesce(new.profissional_id, old.profissional_id);
begin
  update public.profissionais set
    nota_media = coalesce((select round(avg(nota)::numeric, 2) from public.avaliacoes where profissional_id = v_pro), 0),
    total_avaliacoes = (select count(*) from public.avaliacoes where profissional_id = v_pro)
  where id = v_pro;
  if tg_op = 'INSERT' then
    perform public.notificar(v_pro, 'avaliacao_nova', 'Você recebeu uma avaliação de ' || new.nota || ' estrelas', coalesce(new.comentario, ''),
      jsonb_build_object('pedido_id', new.pedido_id));
  end if;
  return null;
end;
$$;
create trigger recalcular_nota after insert or update of nota or delete on public.avaliacoes for each row execute function public.recalcular_nota();

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create or replace function public.participa_do_pedido(p_pedido uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$ select exists (select 1 from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id)) $$;

create or replace function public.ao_enviar_mensagem()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_ped public.pedidos;
  v_nome text;
begin
  select * into v_ped from public.pedidos where id = new.pedido_id;
  if v_ped.status in ('recusado', 'expirado', 'cancelado') or (v_ped.status = 'concluido' and v_ped.concluido_em < now() - interval '7 days') then
    perform public.erro('chat_encerrado', 'A conversa deste pedido foi encerrada.');
  end if;
  select split_part(nome, ' ', 1) into v_nome from public.perfis where id = new.autor_id;
  perform public.notificar(case when new.autor_id = v_ped.cliente_id then v_ped.profissional_id else v_ped.cliente_id end,
    'mensagem', v_nome, left(new.texto, 140), jsonb_build_object('pedido_id', new.pedido_id));
  return new;
end;
$$;
create trigger ao_enviar_mensagem before insert on public.mensagens for each row execute function public.ao_enviar_mensagem();

create or replace function public.marcar_mensagens_lidas(p_pedido uuid)
returns void
language sql security definer
set search_path = public
as $$
  update public.mensagens set lida_em = now()
  where pedido_id = p_pedido and autor_id <> auth.uid() and lida_em is null and public.participa_do_pedido(p_pedido)
$$;

-- ---------------------------------------------------------------------------
-- Segurança e garantia
-- ---------------------------------------------------------------------------
create or replace function public.acionar_emergencia(p_pedido uuid default null, p_lat double precision default null, p_lng double precision default null)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id bigint;
begin
  if p_pedido is not null and not public.participa_do_pedido(p_pedido) then
    perform public.erro('pedido_nao_encontrado', 'Pedido não encontrado.');
  end if;
  insert into public.emergencias (pedido_id, usuario_id, localizacao)
  values (p_pedido, auth.uid(), case when p_lat is not null then public.ponto(p_lat, p_lng) end)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.compartilhar_acompanhamento(p_pedido uuid)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if not exists (select 1 from public.pedidos where id = p_pedido and cliente_id = auth.uid() and status in ('aceito', 'a_caminho', 'em_atendimento')) then
    perform public.erro('nao_compartilhavel', 'Só é possível compartilhar um atendimento em andamento.');
  end if;
  insert into public.compartilhamentos (pedido_id, criado_por) values (p_pedido, auth.uid()) returning token into v_token;
  return v_token;
end;
$$;

-- Página pública de acompanhamento (sem login), aberta pelo link compartilhado.
create or replace function public.acompanhamento_publico(p_token text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object('status', p.status, 'profissional', pe.nome, 'foto', pe.foto_url, 'profissao', f.nome,
    'aceito_em', p.aceito_em, 'a_caminho_em', p.a_caminho_em, 'iniciado_em', p.iniciado_em, 'concluido_em', p.concluido_em)
  from public.compartilhamentos c
  join public.pedidos p on p.id = c.pedido_id
  join public.perfis pe on pe.id = p.profissional_id
  join public.profissoes f on f.id = p.profissao_id
  where c.token = p_token and c.expira_em > now()
$$;

create or replace function public.abrir_reclamacao(p_pedido uuid, p_motivo text, p_descricao text, p_fotos text[] default '{}')
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not exists (select 1 from public.pedidos where id = p_pedido and auth.uid() in (cliente_id, profissional_id)
                 and (status <> 'concluido' or concluido_em > now() - make_interval(days => public.cfg_num('dias_garantia', 30)::int))) then
    perform public.erro('fora_da_garantia', 'Este pedido não está mais na garantia iService.');
  end if;
  insert into public.reclamacoes (pedido_id, autor_id, motivo, descricao, fotos)
  values (p_pedido, auth.uid(), p_motivo, p_descricao, coalesce(p_fotos, '{}')) returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Painel do profissional: ganhos, metas e relatório MEI
-- ---------------------------------------------------------------------------
create or replace function public.resumo_ganhos(p_inicio date default date_trunc('month', current_date)::date, p_fim date default current_date)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'hoje', coalesce(sum(valor_cobrado) filter (where concluido_em::date = current_date), 0),
    'periodo', coalesce(sum(valor_cobrado), 0),
    'servicos', count(*),
    'ticket_medio', coalesce(round(avg(valor_cobrado), 2), 0),
    'por_dia', coalesce((
      select jsonb_agg(jsonb_build_object('dia', d, 'valor', v) order by d)
      from (select concluido_em::date d, sum(valor_cobrado) v from public.pedidos
            where profissional_id = auth.uid() and status = 'concluido' and concluido_em::date between p_inicio and p_fim group by 1) s), '[]'::jsonb),
    'por_profissao', coalesce((
      select jsonb_object_agg(profissao_id, v)
      from (select profissao_id, sum(valor_cobrado) v from public.pedidos
            where profissional_id = auth.uid() and status = 'concluido' and concluido_em::date between p_inicio and p_fim group by 1) s), '{}'::jsonb),
    -- Limite anual do MEI (configurável) para o profissional acompanhar.
    'ano', (select coalesce(sum(valor_cobrado), 0) from public.pedidos
            where profissional_id = auth.uid() and status = 'concluido' and date_part('year', concluido_em) = date_part('year', current_date)),
    'limite_mei', public.cfg_num('limite_anual_mei', 81000)
  )
  from public.pedidos
  where profissional_id = auth.uid() and status = 'concluido' and concluido_em::date between p_inicio and p_fim
$$;

-- ---------------------------------------------------------------------------
-- Tarefas periódicas
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('iservice-expirar-pedidos', '* * * * *', 'select public.expirar_pedidos()');
  end if;
end;
$$;

-- "Hoje" e os dias do relatório seguem o horário de Brasília, não o UTC do servidor.
alter function public.resumo_ganhos(date, date) set timezone = 'America/Sao_Paulo';
alter function public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer) set timezone = 'America/Sao_Paulo';
alter function public.top_regiao(double precision, double precision, text, integer, integer) set timezone = 'America/Sao_Paulo';
