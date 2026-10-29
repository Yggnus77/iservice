-- Profissão Dedetizador (pedido do usuário em 29/10/2026; o piloto passa a 17 profissões).
insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem) values
  ('dedetizador', 'Dedetizador', 'pest_control', '#8bc34a', '#4e8a1e', 180, false,
   array['barata', 'cupim', 'rato', 'escorpião', 'formiga', 'inseto', 'praga', 'dedetização', 'pulga', 'mosquito']::text[], 16)
on conflict (id) do update set nome = excluded.nome, icone = excluded.icone, cor_inicio = excluded.cor_inicio, cor_fim = excluded.cor_fim, preco_base = excluded.preco_base, exige_antecedentes = excluded.exige_antecedentes, palavras_chave = excluded.palavras_chave, ordem = excluded.ordem;
insert into public.especialidades (profissao_id, nome, ordem) values
  ('dedetizador', 'Baratas e formigas', 0),
  ('dedetizador', 'Cupins', 1),
  ('dedetizador', 'Ratos', 2),
  ('dedetizador', 'Escorpiões', 3),
  ('dedetizador', 'Pulgas e carrapatos', 4),
  ('dedetizador', 'Mosquitos e pernilongos', 5),
  ('dedetizador', 'Percevejos', 6),
  ('dedetizador', 'Pombos e morcegos', 7)
on conflict (profissao_id, nome) do update set ordem = excluded.ordem;
insert into public.certificacoes_sugeridas (profissao_id, nome, obrigatoria) values
  ('dedetizador', 'Licença da Vigilância Sanitária', false),
  ('dedetizador', 'Curso de controle de pragas', false)
on conflict (profissao_id, nome) do update set obrigatoria = excluded.obrigatoria;
