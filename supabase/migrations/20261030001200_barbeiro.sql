-- Profissão Barbeiro, com atendimento em casa (pedido do usuário em 30/10/2026; o piloto passa a 18 profissões).
insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem) values
  ('barbeiro', 'Barbeiro', 'content_cut', '#8d6e63', '#5d4037', 60, false,
   array['cabelo', 'barba', 'corte', 'barbearia', 'cabeleireiro', 'domicílio', 'bigode']::text[], 17)
on conflict (id) do update set nome = excluded.nome, icone = excluded.icone, cor_inicio = excluded.cor_inicio, cor_fim = excluded.cor_fim, preco_base = excluded.preco_base, exige_antecedentes = excluded.exige_antecedentes, palavras_chave = excluded.palavras_chave, ordem = excluded.ordem;
insert into public.especialidades (profissao_id, nome, ordem) values
  ('barbeiro', 'Corte masculino', 0),
  ('barbeiro', 'Barba', 1),
  ('barbeiro', 'Corte e barba', 2),
  ('barbeiro', 'Corte infantil', 3),
  ('barbeiro', 'Pezinho e acabamento', 4),
  ('barbeiro', 'Sobrancelha', 5),
  ('barbeiro', 'Pigmentação', 6),
  ('barbeiro', 'Atendimento para idosos e acamados', 7)
on conflict (profissao_id, nome) do update set ordem = excluded.ordem;
insert into public.certificacoes_sugeridas (profissao_id, nome, obrigatoria) values
  ('barbeiro', 'Curso de barbeiro', false)
on conflict (profissao_id, nome) do update set obrigatoria = excluded.obrigatoria;
