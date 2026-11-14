-- Profissão Promotor de eventos (pedido do usuário em 14/11/2026; o piloto passa a 20 profissões).
-- Cobrança comum por diária. A faixa de preço de referência sai sozinha de preco_base + ordem da
-- especialidade e do fator da região; a equipe pode ajustar cada faixa no painel (Preços).
insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem) values
  ('promotor', 'Promotor de eventos', 'campaign', '#26c6da', '#00838f', 150, false,
   array['promotor', 'promotora', 'evento', 'festa', 'feira', 'degustação', 'recepção', 'recepcionista', 'hostess', 'panfletagem', 'panfleto', 'staff', 'pdv', 'supermercado', 'ativação', 'divulgação']::text[], 19)
on conflict (id) do update set nome = excluded.nome, icone = excluded.icone, cor_inicio = excluded.cor_inicio, cor_fim = excluded.cor_fim, preco_base = excluded.preco_base, exige_antecedentes = excluded.exige_antecedentes, palavras_chave = excluded.palavras_chave, ordem = excluded.ordem;
update public.profissoes set cobranca_padrao = 'diaria' where id = 'promotor';
insert into public.especialidades (profissao_id, nome, ordem) values
  ('promotor', 'Promoção em PDV e supermercado', 0),
  ('promotor', 'Degustação', 1),
  ('promotor', 'Recepção e hostess', 2),
  ('promotor', 'Panfletagem e divulgação', 3),
  ('promotor', 'Staff de eventos', 4),
  ('promotor', 'Demonstração de produtos', 5),
  ('promotor', 'Credenciamento e controle de acesso', 6),
  ('promotor', 'Feiras e exposições', 7)
on conflict (profissao_id, nome) do update set ordem = excluded.ordem;
insert into public.certificacoes_sugeridas (profissao_id, nome, obrigatoria) values
  ('promotor', 'Curso de atendimento ao cliente', false),
  ('promotor', 'Curso de promotor de vendas', false)
on conflict (profissao_id, nome) do update set obrigatoria = excluded.obrigatoria;
