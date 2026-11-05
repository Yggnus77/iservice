-- Busca no mapa do app Cliente (04/11/2026): posição aproximada de cada
-- profissional da lista, para desenhar os pins.
--
-- Privacidade: devolve só o centro público da área de atendimento
-- (centro_publico, arredondado numa grade de ~1 km), nunca o endereço nem o
-- GPS do profissional. Só para quem está aprovado e disponível, e no máximo
-- 50 por chamada (o mesmo limite da busca).
create or replace function public.posicoes_mapa(p_ids uuid[])
returns table (profissional_id uuid, lat double precision, lng double precision)
language sql stable security definer
set search_path = public, extensions
as $$
  select pr.id,
    extensions.st_y(public.centro_publico(pr.area_centro)::extensions.geometry),
    extensions.st_x(public.centro_publico(pr.area_centro)::extensions.geometry)
  from public.profissionais pr
  where pr.id = any(p_ids[1:50])
    and pr.status = 'aprovado' and pr.disponivel and pr.area_centro is not null
$$;
revoke all on function public.posicoes_mapa(uuid[]) from public, anon;
grant execute on function public.posicoes_mapa(uuid[]) to authenticated;
