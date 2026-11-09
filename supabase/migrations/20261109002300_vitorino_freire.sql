-- Vitorino Freire (MA): cidade onde começam os testes com pessoas reais.
-- Entra no topo da lista de cidades e na faixa 5 do preço de referência
-- (a mais barata, a mesma do Entorno) até haver preços reais da cidade.
insert into public.regioes (id, nome, uf, faixa_preco, centro, ordem) values
  ('vitorino-freire', 'Vitorino Freire', 'MA', 5, public.ponto(-4.28, -45.25), -1)
on conflict (id) do update set nome = excluded.nome, uf = excluded.uf, faixa_preco = excluded.faixa_preco, centro = excluded.centro, ordem = excluded.ordem;
