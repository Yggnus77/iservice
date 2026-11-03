-- Profissão Borracheiro, com atendimento no local do carro (pedido do usuário em 03/11/2026; o piloto passa a 19 profissões).
-- A faixa de preço de referência sai sozinha de preco_base + ordem da especialidade e do fator da região;
-- a equipe pode ajustar cada faixa no painel (Preços).
insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem) values
  ('borracheiro', 'Borracheiro', 'tire_repair', '#607d8b', '#263238', 50, false,
   array['pneu', 'pneu furado', 'furo', 'estepe', 'roda', 'calibrar', 'borracharia', 'câmara de ar', 'socorro', 'moto']::text[], 18)
on conflict (id) do update set nome = excluded.nome, icone = excluded.icone, cor_inicio = excluded.cor_inicio, cor_fim = excluded.cor_fim, preco_base = excluded.preco_base, exige_antecedentes = excluded.exige_antecedentes, palavras_chave = excluded.palavras_chave, ordem = excluded.ordem;
insert into public.especialidades (profissao_id, nome, ordem) values
  ('borracheiro', 'Conserto de pneu furado', 0),
  ('borracheiro', 'Troca pelo estepe', 1),
  ('borracheiro', 'Calibragem e enchimento', 2),
  ('borracheiro', 'Pneu de moto', 3),
  ('borracheiro', 'Câmara de ar e válvula', 4),
  ('borracheiro', 'Socorro na rua ou na estrada', 5),
  ('borracheiro', 'Montagem e troca de pneus', 6),
  ('borracheiro', 'Pneu de caminhonete e utilitário', 7)
on conflict (profissao_id, nome) do update set ordem = excluded.ordem;
insert into public.certificacoes_sugeridas (profissao_id, nome, obrigatoria) values
  ('borracheiro', 'Curso de borracheiro', false)
on conflict (profissao_id, nome) do update set obrigatoria = excluded.obrigatoria;
