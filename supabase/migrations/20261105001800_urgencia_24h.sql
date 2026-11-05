-- Urgência 24h (brief do MVP, 05/11/2026).
-- O profissional marca "Atendo 24h" no app. O botão "Chamar urgência 24h" do
-- app Cliente busca só quem marcou, pela mesma regra da busca normal (aprovado,
-- verificado, disponível, fora de atendimento, dentro do raio, mais bem
-- avaliados primeiro). O filtro é feito aqui no servidor, nunca só no app.

alter table public.profissionais add column if not exists atende_24h boolean not null default false;

-- O próprio profissional liga e desliga (a política "editar o próprio" já limita à linha dele).
grant update (atende_24h) on public.profissionais to authenticated;

create or replace function public.buscar_urgencia_24h(
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
language sql volatile security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
  select b.profissional_id, b.nome, b.foto_url, b.nota_media, b.total_avaliacoes, b.servicos_concluidos,
    b.anos_experiencia, b.verificado, b.distancia_km, b.novo, b.preco_a_partir, b.especialidades, b.favorito,
    b.fase_lancamento, (row_number() over (order by b.posicao))::int
  from public.buscar_profissionais(p_profissao, p_lat, p_lng, p_especialidade, p_ordem, p_rodizio, 500) b
  join public.profissionais pr on pr.id = b.profissional_id
  where pr.atende_24h
  order by b.posicao
  limit p_limite
$$;

revoke all on function public.buscar_urgencia_24h(text, double precision, double precision, bigint, text, integer, integer) from public, anon;
grant execute on function public.buscar_urgencia_24h(text, double precision, double precision, bigint, text, integer, integer) to authenticated;
