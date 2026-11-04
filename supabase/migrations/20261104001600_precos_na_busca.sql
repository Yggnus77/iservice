-- Preço e forma de cobrança na lista de profissionais, e a região mais próxima
-- de um ponto (para mostrar a faixa comum quando o cliente usa o GPS).

-- Preço de cada profissional na busca: o da especialidade escolhida ou o
-- menor da profissão, com a forma de cobrança dele.
create or replace function public.precos_busca(p_ids uuid[], p_profissao text, p_especialidade bigint default null)
returns table (profissional_id uuid, preco numeric, cobranca public.forma_cobranca)
language sql stable security definer
set search_path = public
as $$
  select distinct on (x.profissional_id) x.profissional_id, x.preco, x.cobranca
  from public.profissional_especialidades x
  join public.especialidades e on e.id = x.especialidade_id
  join public.profissionais pr on pr.id = x.profissional_id and pr.status = 'aprovado'
  where x.profissional_id = any(p_ids) and e.profissao_id = p_profissao and x.preco is not null
    and (p_especialidade is null or e.id = p_especialidade)
  order by x.profissional_id, x.preco
$$;
revoke all on function public.precos_busca(uuid[], text, bigint) from public, anon;
grant execute on function public.precos_busca(uuid[], text, bigint) to authenticated;

create or replace function public.regiao_proxima(p_lat double precision, p_lng double precision)
returns text
language sql stable security definer
set search_path = public, extensions
as $$
  select r.id from public.regioes r
  where r.ativa and r.centro is not null
  order by extensions.st_distance(r.centro, public.ponto(p_lat, p_lng))
  limit 1
$$;
revoke all on function public.regiao_proxima(double precision, double precision) from public;
grant execute on function public.regiao_proxima(double precision, double precision) to anon, authenticated;
