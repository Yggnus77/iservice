"""gera a migração de catálogo com o catálogo do lançamento (profissões, especialidades,
regiões e configuração). Fonte: protótipo aprovado em 24/10/2026."""
import json, pathlib

PROFISSOES = [
  ('eletricista', 'Eletricista', 'bolt', 80, '#ffc531', '#ff9f00', ['Instalação elétrica', 'Tomadas e interruptores', 'Chuveiro elétrico', 'Quadro de luz e disjuntores', 'Iluminação e luminárias', 'Ventilador de teto', 'Curto-circuito e reparos', 'Padrão de energia'], ['tomada', 'luz', 'chuveiro', 'disjuntor', 'ventilador', 'fiação', 'energia']),
  ('encanador', 'Encanador', 'plumbing', 80, '#3d8bff', '#0052cc', ['Vazamentos', 'Desentupimento', 'Caixa d’água', 'Torneiras e registros', 'Vaso sanitário e descarga', 'Aquecedor a gás', 'Instalação hidráulica'], ['vazamento', 'cano', 'pia', 'descarga', 'torneira', 'entupido', 'esgoto']),
  ('chaveiro', 'Chaveiro', 'key', 60, '#ff9a3d', '#ff6a00', ['Abertura de portas', 'Troca de fechadura', 'Cópia de chaves', 'Fechadura digital', 'Portão e cadeado', 'Cofres'], ['chave', 'porta', 'fechadura', 'trancado', 'cadeado']),
  ('chaveiro-auto', 'Chaveiro automotivo', 'directions_car', 120, '#6b7bff', '#3a3fd9', ['Abertura de carro', 'Chave codificada', 'Cópia de chave', 'Chave canivete', 'Conserto de ignição', 'Chave de moto'], ['carro', 'chave do carro', 'moto', 'ignição']),
  ('baba', 'Babá', 'child_care', 150, '#ff9fc0', '#f2588a', ['Diária', 'Meio período', 'Noite', 'Recém-nascidos', 'Crianças com deficiência', 'Levar e buscar na escola'], ['criança', 'bebê', 'filho', 'escola']),
  ('faxineira', 'Faxineira', 'cleaning_services', 180, '#2ec4b6', '#0e8f84', ['Faxina completa', 'Limpeza pós-obra', 'Passadoria', 'Limpeza de vidros', 'Organização', 'Limpeza comercial'], ['faxina', 'limpeza', 'diarista', 'passar roupa']),
  ('pintor', 'Pintor', 'format_paint', 250, '#ff7b6b', '#e5483a', ['Parede interna', 'Fachada', 'Textura e grafiato', 'Massa corrida', 'Portas e grades', 'Impermeabilização'], ['parede', 'pintura', 'tinta', 'textura']),
  ('marido', 'Marido de aluguel', 'handyman', 70, '#4a90f0', '#1a5bc4', ['Prateleiras e quadros', 'Cortinas e persianas', 'Pequenos reparos', 'Instalação de TV', 'Troca de lâmpadas', 'Varal e suportes'], ['prateleira', 'cortina', 'conserto', 'reparo', 'furar', 'tv']),
  ('jardinagem', 'Jardinagem', 'potted_plant', 120, '#34d27b', '#0fa958', ['Poda', 'Corte de grama', 'Paisagismo', 'Limpeza de terreno', 'Plantio', 'Irrigação'], ['grama', 'jardim', 'poda', 'árvore', 'terreno']),
  ('pedreiro', 'Pedreiro', 'foundation', 250, '#b39083', '#7b5e54', ['Pisos e revestimentos', 'Banheiros', 'Reformas', 'Calçadas', 'Muros', 'Telhado e calhas', 'Contrapiso', 'Alvenaria'], ['obra', 'reforma', 'piso', 'muro', 'telhado', 'azulejo']),
  ('pets', 'Animais de estimação', 'pets', 40, '#ffbe55', '#f08c00', ['Passeio', 'Banho e tosa', 'Pet sitter', 'Hospedagem', 'Adestramento', 'Táxi pet'], ['cachorro', 'gato', 'pet', 'banho', 'tosa', 'passeio']),
  ('ar', 'Técnico de ar-condicionado', 'ac_unit', 350, '#5ccbf7', '#1e88e5', ['Instalação', 'Desinstalação', 'Manutenção', 'Limpeza e higienização', 'Recarga de gás', 'Reparos'], ['ar', 'ar-condicionado', 'split', 'climatização']),
  ('fretes', 'Fretes', 'local_shipping', 150, '#3b5bb8', '#1e3a8a', ['Mudança', 'Carreto', 'Entrega', 'Transporte de móveis', 'Retirada de entulho', 'Montagem na mudança'], ['mudança', 'frete', 'carreto', 'entulho', 'transporte']),
  ('montador', 'Montador de móveis', 'chair', 90, '#6f8695', '#45596a', ['Guarda-roupa', 'Cozinha planejada', 'Escritório', 'Cama e berço', 'Desmontagem', 'Painel de TV'], ['móvel', 'montar', 'guarda-roupa', 'armário']),
  ('estofados', 'Limpeza de estofados', 'weekend', 150, '#a678ff', '#7c4ddb', ['Sofá', 'Colchão', 'Cadeiras', 'Tapetes', 'Bancos de carro', 'Impermeabilização de estofado'], ['sofá', 'colchão', 'tapete', 'estofado']),
  ('maquiadora', 'Maquiadora', 'face_retouching_natural', 120, '#e46be8', '#b02db8', ['Social', 'Noiva', 'Formatura', 'Penteado', 'Debutante', 'Maquiagem artística'], ['maquiagem', 'noiva', 'penteado', 'festa']),
  ('dedetizador', 'Dedetizador', 'pest_control', 180, '#8bc34a', '#4e8a1e', ['Baratas e formigas', 'Cupins', 'Ratos', 'Escorpiões', 'Pulgas e carrapatos', 'Mosquitos e pernilongos', 'Percevejos', 'Pombos e morcegos'], ['barata', 'cupim', 'rato', 'escorpião', 'formiga', 'inseto', 'praga', 'dedetização', 'pulga', 'mosquito']),
]
EXIGE_ANTECEDENTES = {'baba'}
CERTIFICACOES = {
  'eletricista': ['NR-10', 'NR-35 (trabalho em altura)', 'Curso SENAI'],
  'encanador': ['Curso SENAI de instalações hidráulicas'],
  'chaveiro-auto': ['Curso de codificação de chaves'],
  'baba': ['Primeiros socorros infantis', '*Certidão de antecedentes criminais'],
  'ar': ['Curso de refrigeração e climatização', 'NR-35 (trabalho em altura)'],
  'fretes': ['CNH categoria B ou C'],
  'maquiadora': ['Curso de maquiagem profissional'],
  'pets': ['Curso de banho e tosa'],
  'dedetizador': ['Licença da Vigilância Sanitária', 'Curso de controle de pragas'],
}
# (id, nome, uf, faixa de preço 1..5, lat, lng)
REGIOES = [
  ('asa-sul', 'Asa Sul', 'DF', 1, -15.8150, -47.8960), ('asa-norte', 'Asa Norte', 'DF', 1, -15.7630, -47.8820),
  ('sudoeste', 'Sudoeste/Octogonal', 'DF', 1, -15.7990, -47.9250), ('noroeste', 'Noroeste', 'DF', 1, -15.7400, -47.9100),
  ('lago-sul', 'Lago Sul', 'DF', 1, -15.8400, -47.8500), ('lago-norte', 'Lago Norte', 'DF', 1, -15.7300, -47.8400),
  ('park-way', 'Park Way', 'DF', 1, -15.8950, -47.9600),
  ('cruzeiro', 'Cruzeiro', 'DF', 2, -15.7900, -47.9400), ('guara', 'Guará', 'DF', 2, -15.8300, -47.9800),
  ('aguas-claras', 'Águas Claras', 'DF', 2, -15.8400, -48.0270), ('vicente-pires', 'Vicente Pires', 'DF', 2, -15.8030, -48.0300),
  ('jardim-botanico', 'Jardim Botânico', 'DF', 2, -15.8700, -47.8000),
  ('taguatinga', 'Taguatinga', 'DF', 3, -15.8330, -48.0560), ('nucleo-bandeirante', 'Núcleo Bandeirante', 'DF', 3, -15.8710, -47.9670),
  ('riacho-fundo', 'Riacho Fundo', 'DF', 3, -15.8830, -48.0170), ('sobradinho', 'Sobradinho', 'DF', 3, -15.6530, -47.7900),
  ('paranoa', 'Paranoá', 'DF', 3, -15.7760, -47.7800),
  ('ceilandia', 'Ceilândia', 'DF', 4, -15.8190, -48.1080), ('samambaia', 'Samambaia', 'DF', 4, -15.8780, -48.0850),
  ('gama', 'Gama', 'DF', 4, -16.0190, -48.0620), ('santa-maria', 'Santa Maria', 'DF', 4, -16.0170, -48.0130),
  ('recanto-das-emas', 'Recanto das Emas', 'DF', 4, -15.9080, -48.0620), ('planaltina', 'Planaltina', 'DF', 4, -15.6200, -47.6500),
  ('sao-sebastiao', 'São Sebastião', 'DF', 4, -15.9030, -47.7740), ('brazlandia', 'Brazlândia', 'DF', 4, -15.6700, -48.2000),
  ('valparaiso', 'Valparaíso de Goiás', 'GO', 5, -16.0650, -47.9750), ('aguas-lindas', 'Águas Lindas de Goiás', 'GO', 5, -15.7610, -48.2810),
  ('luziania', 'Luziânia', 'GO', 5, -16.2530, -47.9500), ('novo-gama', 'Novo Gama', 'GO', 5, -16.0590, -48.0410),
  ('cidade-ocidental', 'Cidade Ocidental', 'GO', 5, -16.0780, -47.9250), ('santo-antonio', 'Santo Antônio do Descoberto', 'GO', 5, -15.9410, -48.2570),
  ('planaltina-go', 'Planaltina de Goiás', 'GO', 5, -15.4520, -47.6140), ('formosa', 'Formosa', 'GO', 5, -15.5370, -47.3340),
]
CONFIG = {
  'cobranca_ativa': (False, 'Planos VIP/Premium. Desligado no período grátis.'),
  'alcance_gratis_km': (10, 'Alcance do plano grátis quando a cobrança estiver ligada.'),
  'alcance_vip_km': (20, 'Alcance do plano VIP.'),
  'alcance_premium_km': (50, 'Alcance do plano Premium.'),
  'prazo_resposta_min': (10, 'Minutos para o profissional aceitar um pedido.'),
  'taxa_urgencia': (15, 'Taxa (R$) para pedidos "Agora".'),
  'janelas_hoje': (['08:00–10:00', '10:00–12:00', '12:00–14:00', '14:00–16:00', '16:00–18:00', '18:00–20:00', '20:00–22:00'], 'Janelas de horário para pedidos "Hoje".'),
  'dias_max_combinado': (7, 'Até quantos dias à frente um horário pode ser combinado com o profissional.'),
  'min_avaliacoes_ranking': (5, 'Abaixo disso o profissional é "Novo" e entra em rodízio.'),
  'min_profissionais_ranking': (3, 'Abaixo disso a profissão/região está em fase de lançamento: todos em rodízio.'),
  'raio_top_regiao_km': (15, 'Raio do "Top da sua região".'),
  'max_profissoes': (3, 'Profissões por profissional.'),
  'min_amostras_preco': (5, 'Preços reais mínimos para calcular a faixa da região.'),
  'fator_faixa_preco': ({'1': 1.05, '2': 0.92, '3': 0.82, '4': 0.75, '5': 0.67}, 'Ajuste da referência base por faixa de região.'),
  'pontos_por_servico': (10, 'Pontos de fidelidade por serviço concluído.'),
  'pontos_indicacao': (50, 'Pontos para quem indicou, na 1ª contratação do indicado.'),
  'dias_garantia': (30, 'Dias de garantia iService após a conclusão.'),
  'limite_anual_mei': (81000, 'Faturamento anual máximo do MEI (R$).'),
  'whatsapp_suporte': ('', 'Número do suporte no WhatsApp (só dígitos, com DDI).'),
}

def q(s):
  return "'" + str(s).replace("'", "''") + "'"

out = ['-- Gerado por tools/gerar_seed.py. Não edite à mão: mude o script e gere de novo.']
out.append('insert into public.app_config (chave, valor, descricao) values')
out.append(',\n'.join(f'  ({q(k)}, {q(json.dumps(v, ensure_ascii=False))}::jsonb, {q(d)})' for k, (v, d) in CONFIG.items()))
out.append('on conflict (chave) do update set valor = excluded.valor, descricao = excluded.descricao;')
out.append('insert into public.regioes (id, nome, uf, faixa_preco, centro, ordem) values')
out.append(',\n'.join(f'  ({q(i)}, {q(n)}, {q(u)}, {f}, public.ponto({la}, {lo}), {k})' for k, (i, n, u, f, la, lo) in enumerate(REGIOES)))
out.append('on conflict (id) do update set nome = excluded.nome, uf = excluded.uf, faixa_preco = excluded.faixa_preco, centro = excluded.centro, ordem = excluded.ordem;')
out.append('insert into public.profissoes (id, nome, icone, cor_inicio, cor_fim, preco_base, exige_antecedentes, palavras_chave, ordem) values')
out.append(',\n'.join(
  f"  ({q(i)}, {q(n)}, {q(ic)}, {q(c1)}, {q(c2)}, {p}, {'true' if i in EXIGE_ANTECEDENTES else 'false'}, array[{', '.join(q(w) for w in kw)}]::text[], {k})"
  for k, (i, n, ic, p, c1, c2, _, kw) in enumerate(PROFISSOES)))
out.append('on conflict (id) do update set nome = excluded.nome, icone = excluded.icone, cor_inicio = excluded.cor_inicio, cor_fim = excluded.cor_fim, preco_base = excluded.preco_base, exige_antecedentes = excluded.exige_antecedentes, palavras_chave = excluded.palavras_chave, ordem = excluded.ordem;')
esp = []
for (i, *_rest) in PROFISSOES:
  for k, e in enumerate(_rest[5]):
    esp.append(f'  ({q(i)}, {q(e)}, {k})')
out.append('insert into public.especialidades (profissao_id, nome, ordem) values')
out.append(',\n'.join(esp))
out.append('on conflict (profissao_id, nome) do update set ordem = excluded.ordem;')
cert = []
for p, lista in CERTIFICACOES.items():
  for c in lista:
    cert.append(f"  ({q(p)}, {q(c.lstrip('*'))}, {'true' if c.startswith('*') else 'false'})")
out.append('insert into public.certificacoes_sugeridas (profissao_id, nome, obrigatoria) values')
out.append(',\n'.join(cert))
out.append('on conflict (profissao_id, nome) do update set obrigatoria = excluded.obrigatoria;')

pathlib.Path(__file__).resolve().parent.parent.joinpath('supabase/migrations/20261025000400_catalogo.sql').write_text('\n'.join(out) + '\n')
print('ok', len(esp), 'especialidades')
