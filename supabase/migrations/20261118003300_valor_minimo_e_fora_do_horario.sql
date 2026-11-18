-- Valor mínimo por profissão e região + acréscimo fora do horário comercial.
--
-- 1. Valor mínimo: o profissional continua definindo o próprio preço, mas não
--    pode salvar um valor abaixo do mínimo da profissão na região dele. Assim
--    ninguém derruba o preço para ganhar visibilidade (o preço também não conta
--    na ordem das recomendações). Só a equipe muda os mínimos, pelo painel.
--    Valores aprovados em 18/11/2026: cerca de 30% abaixo do preço médio de
--    referência (70% do preco_base), ajustados pela faixa da região. Cada região
--    (cidade, estado) pode ganhar um mínimo próprio, que vale antes do da faixa.
--
-- 2. Fora do horário comercial (seg–sex 8h–18h, sáb 8h–12h; domingo e feriados
--    sempre fora): acréscimo de 20% sobre o preço do profissional, definido pela
--    plataforma. Soma com a taxa de urgência e fica sempre visível ao cliente.

-- ---------------------------------------------------------------------------
-- 1. Valor mínimo
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao) values
  ('piso_preco_percentual', '0.7'::jsonb,
   'Valor mínimo de uma profissão nova = preço base × este número (0,7 = 30% abaixo), ajustado pela faixa da região. Os mínimos já criados ficam na tela Preços do painel.')
on conflict (chave) do nothing;

create table if not exists public.precos_minimos (
  id bigint generated always as identity primary key,
  profissao_id text not null references public.profissoes (id) on delete cascade,
  faixa smallint check (faixa between 1 and 5),
  regiao_id text references public.regioes (id) on delete cascade,
  valor numeric(10, 2) not null check (valor > 0),   -- na forma de cobrança comum da profissão
  atualizado_por uuid references auth.users (id) on delete set null,
  atualizado_em timestamptz not null default now(),
  check ((faixa is null) <> (regiao_id is null))
);
create unique index if not exists precos_minimos_faixa on public.precos_minimos (profissao_id, faixa) where faixa is not null;
create unique index if not exists precos_minimos_regiao on public.precos_minimos (profissao_id, regiao_id) where regiao_id is not null;
alter table public.precos_minimos enable row level security;
revoke all on public.precos_minimos from anon, authenticated;
-- Os mínimos são públicos (os apps mostram); só as funções do painel escrevem.
grant select on public.precos_minimos to anon, authenticated;
drop policy if exists "precos_minimos: leitura" on public.precos_minimos;
create policy "precos_minimos: leitura" on public.precos_minimos for select using (true);

-- Mínimo calculado pela regra aprovada (base × 70%, ajustado pela faixa), em múltiplos de R$ 5.
create or replace function public.piso_calculado(p_profissao text, p_faixa smallint)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select greatest(5, round(
    round(f.preco_base * public.cfg_num('piso_preco_percentual', 0.7) / 5) * 5
    * coalesce((public.cfg('fator_faixa_preco') ->> p_faixa::text)::numeric, 1)
    / coalesce(nullif((public.cfg('fator_faixa_preco') ->> '1')::numeric, 0), 1) / 5) * 5)
  from public.profissoes f where f.id = p_profissao
$$;
revoke all on function public.piso_calculado(text, smallint) from public, anon, authenticated;

-- Valores aprovados em 18/11/2026 (faixas 1 a 5, na forma de cobrança comum da profissão).
insert into public.precos_minimos (profissao_id, faixa, valor)
select t.id, fx.f::smallint, t.v[fx.f]
from (values
  ('eletricista', array[55, 50, 45, 40, 35]),
  ('encanador', array[55, 50, 45, 40, 35]),
  ('chaveiro', array[40, 35, 30, 30, 25]),
  ('chaveiro-auto', array[85, 75, 65, 60, 55]),
  ('baba', array[105, 90, 80, 75, 65]),
  ('faxineira', array[125, 110, 100, 90, 80]),
  ('pintor', array[175, 155, 135, 125, 110]),
  ('marido', array[50, 45, 40, 35, 30]),
  ('jardinagem', array[85, 75, 65, 60, 55]),
  ('pedreiro', array[175, 155, 135, 125, 110]),
  ('pets', array[30, 25, 25, 20, 20]),
  ('ar', array[245, 215, 190, 175, 155]),
  ('fretes', array[105, 90, 80, 75, 65]),
  ('montador', array[65, 55, 50, 45, 40]),
  ('estofados', array[105, 90, 80, 75, 65]),
  ('maquiadora', array[85, 75, 65, 60, 55]),
  ('dedetizador', array[125, 110, 100, 90, 80]),
  ('barbeiro', array[40, 35, 30, 30, 25]),
  ('borracheiro', array[35, 30, 25, 25, 20]),
  ('promotor', array[105, 90, 80, 75, 65])
) t(id, v)
join public.profissoes f on f.id = t.id
cross join generate_series(1, 5) fx(f)
on conflict do nothing;
-- Outra profissão que exista no banco recebe o valor pela mesma regra.
insert into public.precos_minimos (profissao_id, faixa, valor)
select f.id, fx.f::smallint, public.piso_calculado(f.id, fx.f::smallint)
from public.profissoes f cross join generate_series(1, 5) fx(f)
on conflict do nothing;

-- Profissão nova já nasce com os mínimos das 5 faixas.
create or replace function public.criar_minimos_profissao()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.precos_minimos (profissao_id, faixa, valor)
  select new.id, fx.f::smallint, public.piso_calculado(new.id, fx.f::smallint) from generate_series(1, 5) fx(f)
  on conflict do nothing;
  return new;
end;
$$;
revoke all on function public.criar_minimos_profissao() from public, anon, authenticated;
drop trigger if exists criar_minimos on public.profissoes;
create trigger criar_minimos after insert on public.profissoes
  for each row execute function public.criar_minimos_profissao();

-- Mínimo de uma profissão numa região e forma de cobrança.
-- Ordem: mínimo próprio da região; senão, o da faixa da região; senão, o cálculo.
-- Sem região (cadastro ainda sem endereço) vale a faixa mais barata, para não barrar ninguém por engano;
-- quando o endereço entra, a pendência de preço confere de novo.
create or replace function public.preco_minimo_profissao(p_profissao text, p_regiao text,
  p_cobranca public.forma_cobranca default null)
returns numeric
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_faixa smallint := coalesce((select faixa_preco from public.regioes where id = p_regiao), 5);
  v_padrao public.forma_cobranca;
  v_valor numeric;
  v_conv numeric;
begin
  select cobranca_padrao into v_padrao from public.profissoes where id = p_profissao;
  if v_padrao is null then return null; end if;
  select m.valor into v_valor from public.precos_minimos m where m.profissao_id = p_profissao and m.regiao_id = p_regiao;
  if v_valor is null then
    select m.valor into v_valor from public.precos_minimos m where m.profissao_id = p_profissao and m.faixa = v_faixa;
  end if;
  v_valor := coalesce(v_valor, public.piso_calculado(p_profissao, v_faixa));
  if p_cobranca is null or p_cobranca = v_padrao then return v_valor; end if;
  v_conv := coalesce((public.cfg('fator_cobranca') ->> p_cobranca::text)::numeric, 1)
    / coalesce(nullif((public.cfg('fator_cobranca') ->> v_padrao::text)::numeric, 0), 1);
  return greatest(5, round(v_valor * v_conv / 5) * 5);
end;
$$;

create or replace function public.preco_minimo(p_especialidade bigint, p_regiao text,
  p_cobranca public.forma_cobranca default 'servico')
returns numeric
language sql stable security definer
set search_path = public
as $$
  select public.preco_minimo_profissao(e.profissao_id, p_regiao, p_cobranca)
  from public.especialidades e where e.id = p_especialidade
$$;
revoke all on function public.preco_minimo_profissao(text, text, public.forma_cobranca), public.preco_minimo(bigint, text, public.forma_cobranca) from public;
grant execute on function public.preco_minimo_profissao(text, text, public.forma_cobranca), public.preco_minimo(bigint, text, public.forma_cobranca) to anon, authenticated;

-- Mínimo que vale para um profissional (pela região do cadastro dele).
create or replace function public.preco_minimo_do_profissional(p_profissional uuid, p_especialidade bigint, p_cobranca public.forma_cobranca)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select public.preco_minimo(p_especialidade, (select regiao_id from public.profissionais where id = p_profissional), p_cobranca)
$$;
revoke all on function public.preco_minimo_do_profissional(uuid, bigint, public.forma_cobranca) from public, anon, authenticated;

-- A trava: preço abaixo do mínimo não é salvo, venha de onde vier.
create or replace function public.conferir_preco_minimo()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_min numeric;
  v_nome text;
begin
  if new.preco is null then return new; end if;
  if tg_op = 'UPDATE' and new.preco is not distinct from old.preco and new.cobranca is not distinct from old.cobranca then
    return new;
  end if;
  v_min := public.preco_minimo_do_profissional(new.profissional_id, new.especialidade_id, new.cobranca);
  if v_min is not null and new.preco < v_min then
    select f.nome into v_nome from public.especialidades e join public.profissoes f on f.id = e.profissao_id where e.id = new.especialidade_id;
    perform public.erro('preco_abaixo_minimo', format(
      'O valor mínimo de %s na sua região é R$ %s %s. Informe um valor igual ou maior.',
      coalesce(v_nome, 'esta profissão'), to_char(v_min, 'FM999G990'),
      case new.cobranca when 'hora' then 'por hora' when 'diaria' then 'por diária' else 'por serviço' end));
  end if;
  return new;
end;
$$;
revoke all on function public.conferir_preco_minimo() from public, anon, authenticated;
drop trigger if exists conferir_preco_minimo on public.profissional_especialidades;
create trigger conferir_preco_minimo before insert or update of preco, cobranca on public.profissional_especialidades
  for each row execute function public.conferir_preco_minimo();

-- Pendência: preço que ficou abaixo do mínimo (ex.: a equipe subiu o mínimo ou o profissional mudou de região)
-- volta a ser "preço de cada especialidade" até ele corrigir.
create or replace function public.pendencias_profissional(p_id uuid)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.pendencias_basicas(p_id), '{}') || array_remove(array[
    case when pr.area_centro is null then 'area_atendimento' end,
    case when not exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = p_id) then 'profissao' end,
    case when exists (
      select 1 from public.profissional_profissoes pp
      where pp.profissional_id = p_id and not exists (
        select 1 from public.profissional_especialidades pe join public.especialidades e on e.id = pe.especialidade_id
        where pe.profissional_id = p_id and e.profissao_id = pp.profissao_id)
    ) or exists (
      select 1 from public.profissional_especialidades pe where pe.profissional_id = p_id
        and (pe.preco is null or pe.preco < coalesce(public.preco_minimo_do_profissional(p_id, pe.especialidade_id, pe.cobranca), 0))
    ) then 'especialidades_e_precos' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'documento_frente' and d.status <> 'recusado') then 'documento' end,
    case when not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'selfie_documento' and d.status <> 'recusado') then 'selfie' end,
    case when exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = p_id and f.exige_antecedentes)
      and not exists (select 1 from public.documentos d where d.profissional_id = p_id and d.tipo = 'antecedentes' and d.status <> 'recusado') then 'antecedentes' end
  ], null)
  from public.profissionais pr
  where pr.id = p_id and (p_id = auth.uid() or public.e_admin() or auth.uid() is null)
$$;

-- A faixa "comum na região" nunca fica abaixo do mínimo.
create or replace function public.faixa_preco(p_especialidade bigint, p_regiao text, p_cobranca public.forma_cobranca default 'servico')
returns table (minimo numeric, maximo numeric, amostras integer, estimada boolean)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_faixa smallint := coalesce((select faixa_preco from public.regioes where id = p_regiao), 2);
  v_aj public.precos_referencia;
  v_calc record;
  v_piso numeric := coalesce(public.preco_minimo(p_especialidade, p_regiao, p_cobranca), 0);
begin
  select * into v_calc from public.faixa_preco_calculada(p_especialidade, v_faixa, p_cobranca, p_regiao);
  select * into v_aj from public.precos_referencia
  where especialidade_id = p_especialidade and faixa = v_faixa and cobranca = p_cobranca;
  if v_aj.especialidade_id is not null then
    return query select greatest(v_aj.minimo, v_piso), greatest(v_aj.maximo, v_piso), v_calc.amostras, false;
    return;
  end if;
  return query select greatest(v_calc.minimo, v_piso), greatest(v_calc.maximo, v_piso), v_calc.amostras, v_calc.estimada;
end;
$$;

-- Painel: tabela de mínimos (por faixa e os próprios de cada região).
create or replace function public.admin_tabela_minimos()
returns table (profissao_id text, profissao text, cobranca public.forma_cobranca, faixa smallint, regiao_id text, regiao text,
  valor numeric, calculado numeric, abaixo integer, atualizado_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('precos');
  return query
  select f.id, f.nome, f.cobranca_padrao, coalesce(m.faixa, r.faixa_preco), m.regiao_id, r.nome, m.valor,
    public.piso_calculado(f.id, coalesce(m.faixa, r.faixa_preco)),
    (select count(*)::int from public.profissional_especialidades x
      join public.especialidades e on e.id = x.especialidade_id and e.profissao_id = f.id
      join public.profissionais pr on pr.id = x.profissional_id
      left join public.regioes rr on rr.id = pr.regiao_id
      where x.preco is not null
        and (case when m.regiao_id is not null then pr.regiao_id = m.regiao_id
                  else coalesce(rr.faixa_preco, 5) = m.faixa
                    and not exists (select 1 from public.precos_minimos m2 where m2.profissao_id = f.id and m2.regiao_id = pr.regiao_id) end)
        and x.preco < public.preco_minimo_do_profissional(pr.id, x.especialidade_id, x.cobranca)),
    m.atualizado_em
  from public.precos_minimos m
  join public.profissoes f on f.id = m.profissao_id
  left join public.regioes r on r.id = m.regiao_id
  order by f.ordem, f.nome, m.regiao_id nulls first, m.faixa, r.nome;
end;
$$;

-- Muda o mínimo de uma faixa (p_valor nulo volta ao cálculo) ou de uma região (p_valor nulo remove o próprio).
create or replace function public.admin_definir_minimo(p_profissao text, p_faixa smallint default null,
  p_regiao text default null, p_valor numeric default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('precos');
  if (p_faixa is null) = (p_regiao is null) then
    perform public.erro('minimo_invalido', 'Escolha uma faixa ou uma região.');
  end if;
  if p_valor is not null and p_valor <= 0 then
    perform public.erro('minimo_invalido', 'O valor mínimo precisa ser maior que zero.');
  end if;
  if p_faixa is not null then
    insert into public.precos_minimos (profissao_id, faixa, valor, atualizado_por)
    values (p_profissao, p_faixa, coalesce(p_valor, public.piso_calculado(p_profissao, p_faixa)), auth.uid())
    on conflict (profissao_id, faixa) where faixa is not null do update
      set valor = excluded.valor, atualizado_por = excluded.atualizado_por, atualizado_em = now();
  elsif p_valor is null then
    delete from public.precos_minimos where profissao_id = p_profissao and regiao_id = p_regiao;
  else
    insert into public.precos_minimos (profissao_id, regiao_id, valor, atualizado_por)
    values (p_profissao, p_regiao, p_valor, auth.uid())
    on conflict (profissao_id, regiao_id) where regiao_id is not null do update
      set valor = excluded.valor, atualizado_por = excluded.atualizado_por, atualizado_em = now();
  end if;
  perform public.registrar_acao('definir_minimo', p_profissao,
    jsonb_build_object('faixa', p_faixa, 'regiao', p_regiao, 'valor', p_valor));
end;
$$;
revoke all on function public.admin_tabela_minimos(), public.admin_definir_minimo(text, smallint, text, numeric) from public, anon;
grant execute on function public.admin_tabela_minimos(), public.admin_definir_minimo(text, smallint, text, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Acréscimo fora do horário comercial
-- ---------------------------------------------------------------------------
insert into public.app_config (chave, valor, descricao) values
  ('acrescimo_fora_horario', '0.2'::jsonb,
   'Acréscimo sobre o preço do profissional para serviço fora do horário comercial (0,2 = 20%). 0 desliga.'),
  ('horario_comercial', '{"semana": ["08:00", "18:00"], "sabado": ["08:00", "12:00"], "domingo": null}'::jsonb,
   'Horário comercial (Brasília). Fora dele, e em domingos e feriados, entra o acréscimo. null = dia todo fora.')
on conflict (chave) do nothing;

create table if not exists public.feriados (
  data date primary key,
  nome text not null
);
alter table public.feriados enable row level security;
revoke all on public.feriados from anon, authenticated;
grant select on public.feriados to anon, authenticated;
drop policy if exists "feriados: leitura" on public.feriados;
create policy "feriados: leitura" on public.feriados for select using (true);
drop policy if exists "feriados: admin escreve" on public.feriados;
create policy "feriados: admin escreve" on public.feriados for all to authenticated
  using ((public.e_admin() and public.pode('configuracoes'))) with check ((public.e_admin() and public.pode('configuracoes')));
grant insert, update, delete on public.feriados to authenticated;

-- Feriados nacionais e do DF (Brasília). A equipe acrescenta os de outras cidades pelo painel.
insert into public.feriados (data, nome) values
  ('2026-11-20', 'Dia da Consciência Negra'),
  ('2026-11-30', 'Dia do Evangélico (DF)'),
  ('2026-12-25', 'Natal'),
  ('2027-01-01', 'Confraternização Universal'),
  ('2027-03-26', 'Sexta-feira Santa'),
  ('2027-04-21', 'Tiradentes e aniversário de Brasília'),
  ('2027-05-01', 'Dia do Trabalho'),
  ('2027-09-07', 'Independência do Brasil'),
  ('2027-10-12', 'Nossa Senhora Aparecida'),
  ('2027-11-02', 'Finados'),
  ('2027-11-15', 'Proclamação da República'),
  ('2027-11-20', 'Dia da Consciência Negra'),
  ('2027-11-30', 'Dia do Evangélico (DF)'),
  ('2027-12-25', 'Natal')
on conflict (data) do nothing;

-- O momento está fora do horário comercial? (hora de Brasília)
create or replace function public.fora_do_horario(p_momento timestamptz)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_local timestamp := p_momento at time zone 'America/Sao_Paulo';
  v_cfg jsonb := coalesce(public.cfg('horario_comercial'), '{}'::jsonb);
  v_dia jsonb;
  v_hora time := v_local::time;
begin
  if p_momento is null then return false; end if;
  if exists (select 1 from public.feriados where data = v_local::date) then return true; end if;
  v_dia := case extract(isodow from v_local) when 7 then v_cfg -> 'domingo' when 6 then v_cfg -> 'sabado' else v_cfg -> 'semana' end;
  if v_dia is null or jsonb_typeof(v_dia) <> 'array' then return true; end if;
  return not (v_hora >= (v_dia ->> 0)::time and v_hora < (v_dia ->> 1)::time);
end;
$$;

-- Quanto o cliente paga a mais por um serviço com este preço neste momento.
create or replace function public.taxa_fora_horario(p_preco numeric, p_momento timestamptz)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select case when p_preco is null or p_preco <= 0 or not public.fora_do_horario(p_momento) then 0
    else round(p_preco * public.cfg_num('acrescimo_fora_horario', 0.2)) end
$$;
revoke all on function public.fora_do_horario(timestamptz), public.taxa_fora_horario(numeric, timestamptz) from public;
grant execute on function public.fora_do_horario(timestamptz), public.taxa_fora_horario(numeric, timestamptz) to anon, authenticated;

alter table public.pedidos add column if not exists taxa_fora_horario numeric(10, 2) not null default 0;

-- Quando o serviço acontece: agendado no horário marcado; "Hoje" no início da janela; "Agora" já.
create or replace function public.momento_do_servico(p_quando public.quando_pedido, p_janela text, p_combinado timestamptz, p_criado timestamptz)
returns timestamptz
language sql stable
set search_path = public
as $$
  select case
    when p_quando = 'combinado' and p_combinado is not null then p_combinado
    when p_quando = 'hoje' and p_janela ~ '^\d{1,2}:\d{2}' then
      ((coalesce(p_criado, now()) at time zone 'America/Sao_Paulo')::date + substring(p_janela from '^\d{1,2}:\d{2}')::time)
        at time zone 'America/Sao_Paulo'
    else coalesce(p_criado, now()) end
$$;

-- O banco calcula o acréscimo sozinho ao criar o pedido e quando o horário muda.
create or replace function public.calcular_taxa_fora_horario()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.quando is not distinct from old.quando and new.janela is not distinct from old.janela
    and new.combinado_para is not distinct from old.combinado_para and new.preco_informado is not distinct from old.preco_informado then
    return new;
  end if;
  new.taxa_fora_horario := public.taxa_fora_horario(new.preco_informado,
    public.momento_do_servico(new.quando, new.janela, new.combinado_para, case when tg_op = 'INSERT' then now() else new.criado_em end));
  return new;
end;
$$;
revoke all on function public.calcular_taxa_fora_horario() from public, anon, authenticated;
drop trigger if exists calcular_taxa_fora_horario on public.pedidos;
create trigger calcular_taxa_fora_horario before insert or update of quando, janela, combinado_para, preco_informado on public.pedidos
  for each row execute function public.calcular_taxa_fora_horario();

-- Lista de pedidos: leva o acréscimo também.
drop function if exists public.meus_pedidos(text, text, integer);
create function public.meus_pedidos(p_papel text default 'cliente', p_grupo text default 'todos', p_limite integer default 50)
returns table (
  id uuid, codigo text, status public.status_pedido, quando public.quando_pedido, janela text, combinado_para timestamptz,
  profissao_id text, especialidade text, descricao text, endereco_texto text, distancia_km numeric,
  preco_informado numeric, taxa_urgencia numeric, valor_cobrado numeric, responder_ate timestamptz, criado_em timestamptz,
  concluido_em timestamptz, outra_parte_id uuid, outra_parte_nome text, outra_parte_foto text, avaliado boolean, nao_lidas integer,
  proposta_para timestamptz, taxa_fora_horario numeric
)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.codigo, p.status, p.quando, p.janela, p.combinado_para, p.profissao_id, e.nome, p.descricao, p.endereco_texto,
    p.distancia_km, p.preco_informado, p.taxa_urgencia, p.valor_cobrado, p.responder_ate, p.criado_em, p.concluido_em,
    o.id, o.nome, o.foto_url,
    exists (select 1 from public.avaliacoes a where a.pedido_id = p.id),
    (select count(*) from public.mensagens m where m.pedido_id = p.id and m.autor_id <> auth.uid() and m.lida_em is null)::int,
    p.proposta_para, p.taxa_fora_horario
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
