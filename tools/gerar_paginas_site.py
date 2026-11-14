"""Gera as páginas de cada profissão e a página para profissionais do site.

Uso: python3 tools/gerar_paginas_site.py

Lê o cabeçalho e o rodapé de site/termos.html, escreve site/<slug>-em-brasilia.html
para cada profissão, site/profissionais.html, o blog (site/blog/) e atualiza site/sitemap.xml
e a seção "Dicas para resolver hoje" de site/index.html.
Não edite as páginas geradas à mão: mude este script e gere de novo.

Blog: cada artigo é um arquivo tools/blog/<slug>.html com um comentário JSON no topo
(titulo, descricao, categoria, icone, publico, profissoes, publicado, faq) e o corpo em HTML.
Os links do corpo são escritos como se a página estivesse na raiz (ex.: chaveiro-em-brasilia.html).
Ícone novo precisa entrar no icon_names da fonte em todas as páginas.
"""
import html
import json
import re
from datetime import date
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / 'site'
DOMINIO = 'https://iservice.app.br/'
HOJE = date.today().isoformat()
BLOG_FONTES = Path(__file__).resolve().parent / 'blog'
MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro',
         'outubro', 'novembro', 'dezembro']

REGIOES_DF = ['Asa Sul', 'Asa Norte', 'Sudoeste', 'Noroeste', 'Lago Sul', 'Lago Norte', 'Park Way', 'Cruzeiro',
              'Guará', 'Águas Claras', 'Vicente Pires', 'Jardim Botânico', 'Taguatinga', 'Núcleo Bandeirante',
              'Riacho Fundo', 'Sobradinho', 'Paranoá', 'Ceilândia', 'Samambaia', 'Gama', 'Santa Maria',
              'Recanto das Emas', 'Planaltina', 'São Sebastião', 'Brazlândia']
REGIOES_GO = ['Valparaíso de Goiás', 'Águas Lindas de Goiás', 'Luziânia', 'Novo Gama', 'Cidade Ocidental',
              'Santo Antônio do Descoberto', 'Planaltina de Goiás', 'Formosa']

# slug, nome no título, ícone, especialidades (do catálogo do banco), frase de abertura,
# quando chamar (3 situações) e perguntas frequentes específicas (2).
PROFISSOES = [
    dict(slug='eletricista', nome='Eletricista', busca='eletricista', icone='bolt',
         esp=['Instalação elétrica', 'Tomadas e interruptores', 'Chuveiro elétrico', 'Quadro de luz e disjuntores',
              'Iluminação e luminárias', 'Ventilador de teto', 'Curto-circuito e reparos', 'Padrão de energia'],
         abre='Chuveiro queimou, disjuntor desarmando ou tomada sem energia? Encontre um eletricista perto de você em Brasília e no Entorno e seja atendido hoje.',
         quando=['O chuveiro parou de esquentar ou a resistência queimou.', 'O disjuntor desarma sozinho ou há cheiro de queimado.', 'Você precisa instalar tomada, luminária ou ventilador de teto.'],
         faq=[('Quanto custa trocar um chuveiro elétrico?', 'Quem define o valor é o eletricista, e você vê o preço antes de confirmar. O app mostra a faixa de preço da sua região como referência, para você saber se o valor está dentro do normal.'),
              ('O eletricista atende hoje mesmo?', 'Sim. O iService é feito para atendimento no mesmo dia: você pede para agora ou para um horário mais tarde, hoje.')]),
    dict(slug='encanador', nome='Encanador', busca='encanador', icone='plumbing',
         esp=['Vazamentos', 'Desentupimento', 'Caixa d’água', 'Torneiras e registros', 'Vaso sanitário e descarga',
              'Aquecedor a gás', 'Instalação hidráulica'],
         abre='Vazamento, pia entupida ou descarga com defeito? Chame um encanador perto de você em Brasília e no Entorno, com atendimento no mesmo dia.',
         quando=['Tem água vazando pelo teto, pela parede ou pelo registro.', 'A pia, o ralo ou o vaso entupiu.', 'A caixa d’água precisa de limpeza ou a boia não fecha.'],
         faq=[('Encanador faz desentupimento?', 'Sim. Desentupimento de pia, ralo, vaso e esgoto é uma das especialidades que o encanador pode marcar no perfil. Você filtra por ela na hora de pedir.'),
              ('Como sei se o encanador é de confiança?', 'Todo profissional passa por análise de documentos e selfie antes de ser aprovado. No perfil você vê as avaliações de outros clientes, com fotos.')]),
    dict(slug='chaveiro', nome='Chaveiro', busca='chaveiro', icone='key',
         esp=['Abertura de portas', 'Troca de fechadura', 'Cópia de chaves', 'Fechadura digital', 'Portão e cadeado', 'Cofres'],
         abre='Ficou trancado do lado de fora ou perdeu a chave? Encontre um chaveiro perto de você em Brasília e no Entorno e resolva agora.',
         quando=['Você ficou trancado fora de casa ou a chave quebrou na fechadura.', 'Mudou de casa e quer trocar o segredo da fechadura.', 'Quer instalar uma fechadura digital ou fazer cópias de chave.'],
         faq=[('O chaveiro vem até minha casa?', 'Sim. Você vê no mapa os chaveiros perto de você, escolhe pelo perfil e pelas avaliações, e ele vai até o endereço do pedido.'),
              ('Chaveiro abre porta sem estragar?', 'Na maioria dos casos, sim. Abertura de portas é uma especialidade: escolha um chaveiro que a tenha no perfil e veja as avaliações de outros clientes.')]),
    dict(slug='chaveiro-automotivo', nome='Chaveiro automotivo', busca='chaveiro automotivo', icone='car_repair',
         esp=['Abertura de carro', 'Chave codificada', 'Cópia de chave', 'Chave canivete', 'Conserto de ignição', 'Chave de moto'],
         abre='Trancou a chave dentro do carro ou precisa de uma chave codificada? Encontre um chaveiro automotivo perto de você em Brasília e no Entorno.',
         quando=['A chave ficou dentro do carro trancado.', 'Perdeu a única chave do carro ou da moto.', 'A chave não gira na ignição.'],
         faq=[('Chaveiro automotivo faz chave codificada?', 'Sim, quem marca a especialidade "Chave codificada" no perfil faz cópia e programação. Confira no perfil antes de pedir.'),
              ('Ele vai até onde o carro está?', 'Sim. O endereço do pedido pode ser onde o carro está, na rua ou num estacionamento.')]),
    dict(slug='baba', nome='Babá', busca='babá', icone='child_care',
         esp=['Diária', 'Meio período', 'Noite', 'Recém-nascidos', 'Crianças com deficiência', 'Levar e buscar na escola'],
         abre='Precisa de alguém de confiança para cuidar das crianças hoje? Encontre uma babá perto de você em Brasília e no Entorno, com certidão de antecedentes verificada.',
         quando=['Surgiu um compromisso e você precisa de alguém hoje.', 'Quer uma babá para a noite ou meio período.', 'Precisa que alguém leve ou busque na escola.'],
         faq=[('A babá tem antecedentes verificados?', 'Sim. No iService, a certidão de antecedentes criminais é obrigatória para babás. Sem ela, o cadastro não é aprovado.'),
              ('Posso conversar com a babá antes?', 'Sim. Depois do pedido, o chat do app fica aberto para vocês combinarem os detalhes.')]),
    dict(slug='diarista', nome='Diarista e faxineira', busca='diarista', icone='cleaning_services',
         esp=['Faxina completa', 'Limpeza pós-obra', 'Passadoria', 'Limpeza de vidros', 'Organização', 'Limpeza comercial'],
         abre='Precisa de uma faxina hoje? Encontre diarista e faxineira perto de você em Brasília e no Entorno, com avaliações de outros clientes.',
         quando=['Vai receber visita e a casa precisa de uma faxina completa.', 'Terminou uma reforma e precisa de limpeza pós-obra.', 'Quer ajuda para passar roupa ou organizar a casa.'],
         faq=[('Quanto custa uma diária de faxina?', 'Cada diarista define o próprio preço, e você vê o valor antes de confirmar. O app mostra a faixa de preço da sua região como referência.'),
              ('A diarista leva os produtos de limpeza?', 'Isso é combinado com a profissional pelo chat, antes do atendimento.')]),
    dict(slug='pintor', nome='Pintor', busca='pintor', icone='format_paint',
         esp=['Parede interna', 'Fachada', 'Textura e grafiato', 'Massa corrida', 'Portas e grades', 'Impermeabilização'],
         abre='Quer pintar um cômodo, fazer retoques ou aplicar textura? Encontre um pintor perto de você em Brasília e no Entorno.',
         quando=['Precisa pintar um cômodo ou fazer retoques antes de entregar o imóvel.', 'Quer aplicar textura, grafiato ou massa corrida.', 'Portões e grades precisam de pintura.'],
         faq=[('Posso ver trabalhos anteriores do pintor?', 'Sim. O perfil tem portfólio com fotos de antes e depois e avaliações de outros clientes.'),
              ('O pintor começa no mesmo dia?', 'O pedido é para hoje. Serviços maiores podem continuar em outros dias, combinados direto com o profissional.')]),
    dict(slug='marido-de-aluguel', nome='Marido de aluguel', busca='marido de aluguel', icone='handyman',
         esp=['Prateleiras e quadros', 'Cortinas e persianas', 'Pequenos reparos', 'Instalação de TV', 'Troca de lâmpadas', 'Varal e suportes'],
         abre='Precisa instalar TV, prateleira ou cortina? Encontre um marido de aluguel perto de você em Brasília e no Entorno para pequenos reparos hoje.',
         quando=['Comprou uma TV e precisa instalar o suporte na parede.', 'Quer pendurar quadros, prateleiras, cortinas ou varal.', 'Tem vários pequenos consertos acumulados em casa.'],
         faq=[('O que um marido de aluguel faz?', 'Pequenos reparos e instalações: suporte de TV, prateleiras, quadros, cortinas, persianas, varal e troca de lâmpadas, entre outros.'),
              ('Preciso comprar o material antes?', 'Depende do serviço. Combine com o profissional pelo chat do app antes do atendimento.')]),
    dict(slug='jardineiro', nome='Jardineiro', busca='jardineiro', icone='yard',
         esp=['Poda', 'Corte de grama', 'Paisagismo', 'Limpeza de terreno', 'Plantio', 'Irrigação'],
         abre='Grama alta, árvore para podar ou terreno para limpar? Encontre um jardineiro perto de você em Brasília e no Entorno.',
         quando=['A grama está alta e precisa de corte.', 'Árvores e arbustos precisam de poda.', 'O terreno precisa de limpeza.'],
         faq=[('O jardineiro leva as ferramentas?', 'Em geral, sim. Confirme pelo chat do app se ele leva roçadeira e recolhe o material cortado.'),
              ('Atende chácaras e lotes no Entorno?', 'Sim. O iService atende Brasília e todo o Entorno, e cada profissional define no mapa a área onde trabalha.')]),
    dict(slug='pedreiro', nome='Pedreiro', busca='pedreiro', icone='construction',
         esp=['Pisos e revestimentos', 'Banheiros', 'Reformas', 'Calçadas', 'Muros', 'Telhado e calhas', 'Contrapiso', 'Alvenaria'],
         abre='Piso solto, reboco caindo ou um reparo urgente? Encontre um pedreiro perto de você em Brasília e no Entorno.',
         quando=['Um piso soltou ou um azulejo quebrou.', 'Tem infiltração no muro ou na calçada.', 'A calha ou o telhado precisa de reparo.'],
         faq=[('O pedreiro faz reformas maiores?', 'O pedido no iService é para hoje. Para obras maiores, o profissional avalia no local e vocês combinam a continuação.'),
              ('Como escolho o pedreiro?', 'Pelo perfil: especialidades, fotos de antes e depois, avaliações e a distância até você.')]),
    dict(slug='cuidador-de-pets', nome='Cuidador de pets', busca='cuidador de pets', icone='pets',
         esp=['Passeio', 'Banho e tosa', 'Pet sitter', 'Hospedagem', 'Adestramento', 'Táxi pet'],
         abre='Precisa de alguém para passear, dar banho ou cuidar do seu cachorro ou gato hoje? Encontre um cuidador de pets perto de você em Brasília e no Entorno.',
         quando=['Vai passar o dia fora e o cachorro precisa de passeio.', 'O pet precisa de banho e tosa em casa.', 'Precisa de táxi pet para levar ao veterinário.'],
         faq=[('Tem pet sitter para cuidar em casa?', 'Sim. Pet sitter é uma das especialidades. O profissional vai até sua casa cuidar do animal.'),
              ('Atende gatos também?', 'Sim. Diga no pedido qual é o animal e combine os detalhes pelo chat.')]),
    dict(slug='tecnico-de-ar-condicionado', nome='Técnico de ar-condicionado', busca='técnico de ar-condicionado', icone='ac_unit',
         esp=['Instalação', 'Desinstalação', 'Manutenção', 'Limpeza e higienização', 'Recarga de gás', 'Reparos'],
         abre='Ar-condicionado sem gelar, pingando ou para instalar? Encontre um técnico de ar-condicionado perto de você em Brasília e no Entorno.',
         quando=['O ar não gela ou está pingando água.', 'Comprou um split e precisa de instalação.', 'Está na hora da limpeza e higienização.'],
         faq=[('Técnico faz recarga de gás?', 'Sim, quem marca a especialidade "Recarga de gás" faz. Você vê no perfil.'),
              ('O técnico tem certificação?', 'O perfil mostra as certificações que o profissional informou, como curso de refrigeração e NR-35 para trabalho em altura.')]),
    dict(slug='dedetizador', nome='Dedetizador', busca='dedetização', icone='pest_control',
         esp=['Baratas e formigas', 'Cupins', 'Ratos', 'Escorpiões', 'Pulgas e carrapatos', 'Mosquitos e pernilongos', 'Percevejos', 'Pombos e morcegos'],
         abre='Baratas, cupins, ratos ou escorpiões em casa? Encontre um dedetizador perto de você em Brasília e no Entorno.',
         quando=['Apareceram baratas, formigas ou escorpiões.', 'Tem cupim em móveis, portas ou no telhado.', 'Há sinais de ratos ou pombos no imóvel.'],
         faq=[('O dedetizador tem licença?', 'O perfil mostra as certificações que o profissional informou, como a licença da Vigilância Sanitária e o curso de controle de pragas.'),
              ('Preciso sair de casa durante a dedetização?', 'Depende do produto usado. O dedetizador explica pelo chat os cuidados antes e depois do serviço.')]),
    dict(slug='frete-e-carreto', nome='Frete e carreto', busca='frete e carreto', icone='local_shipping',
         esp=['Mudança', 'Carreto', 'Entrega', 'Transporte de móveis', 'Retirada de entulho', 'Montagem na mudança'],
         abre='Precisa levar um móvel, fazer uma pequena mudança ou tirar entulho? Encontre frete e carreto perto de você em Brasília e no Entorno.',
         quando=['Comprou um móvel e precisa levar para casa hoje.', 'Vai fazer uma pequena mudança.', 'Precisa retirar entulho de uma reforma.'],
         faq=[('O freteiro ajuda a carregar?', 'Combine pelo chat do app. Alguns profissionais também montam os móveis na mudança.'),
              ('Faz frete do DF para o Entorno?', 'Sim. O iService atende Brasília e todo o Entorno.')]),
    dict(slug='montador-de-moveis', nome='Montador de móveis', busca='montador de móveis', icone='chair',
         esp=['Guarda-roupa', 'Cozinha planejada', 'Escritório', 'Cama e berço', 'Desmontagem', 'Painel de TV'],
         abre='Comprou um móvel e precisa montar hoje? Encontre um montador de móveis perto de você em Brasília e no Entorno.',
         quando=['Chegou o guarda-roupa, a cama ou o berço.', 'Vai mudar e precisa desmontar os móveis.', 'Quer instalar um painel de TV.'],
         faq=[('O montador traz as ferramentas?', 'Sim, em geral o montador leva as próprias ferramentas. Confirme pelo chat se precisar de algo especial.'),
              ('Monta cozinha planejada?', 'Quem tem a especialidade "Cozinha planejada" no perfil monta. Veja as fotos de trabalhos anteriores.')]),
    dict(slug='limpeza-de-estofados', nome='Limpeza de estofados', busca='limpeza de sofá', icone='weekend',
         esp=['Sofá', 'Colchão', 'Cadeiras', 'Tapetes', 'Bancos de carro', 'Impermeabilização de estofado'],
         abre='Sofá manchado, colchão ou tapete para limpar? Encontre limpeza de estofados perto de você em Brasília e no Entorno.',
         quando=['O sofá tem manchas ou cheiro.', 'O colchão precisa de higienização.', 'Quer impermeabilizar o estofado.'],
         faq=[('Quanto tempo o sofá leva para secar?', 'Depende do tecido e do método. O profissional explica pelo chat antes do serviço.'),
              ('Limpa banco de carro?', 'Sim, quem tem a especialidade "Bancos de carro" no perfil faz.')]),
    dict(slug='barbeiro', nome='Barbeiro em domicílio', busca='barbeiro em domicílio', icone='content_cut',
         esp=['Corte masculino', 'Barba', 'Corte e barba', 'Corte infantil', 'Pezinho e acabamento', 'Sobrancelha', 'Pigmentação', 'Atendimento para idosos e acamados'],
         abre='Quer cortar o cabelo e fazer a barba sem sair de casa? Encontre um barbeiro em domicílio perto de você em Brasília e no Entorno.',
         quando=['Não tem tempo de ir à barbearia.', 'Precisa de corte para alguém idoso ou acamado.', 'Quer corte infantil em casa, sem fila.'],
         faq=[('O barbeiro atende idosos e acamados?', 'Sim. "Atendimento para idosos e acamados" é uma especialidade que o barbeiro pode marcar no perfil.'),
              ('O barbeiro leva o material?', 'Sim, o barbeiro leva máquina, tesoura e o que precisar para o atendimento.')]),
    dict(slug='borracheiro', nome='Borracheiro', busca='borracheiro', icone='tire_repair',
         esp=['Conserto de pneu furado', 'Troca pelo estepe', 'Calibragem e enchimento', 'Pneu de moto', 'Câmara de ar e válvula', 'Socorro na rua ou na estrada', 'Montagem e troca de pneus'],
         abre='Pneu furou? Encontre um borracheiro perto de você em Brasília e no Entorno que vai até onde o carro ou a moto está.',
         quando=['O pneu furou e você está na rua.', 'Precisa trocar pelo estepe e não tem como.', 'O pneu da moto murchou.'],
         faq=[('O borracheiro vai até onde estou?', 'Sim. O endereço do pedido pode ser onde o carro ou a moto está. "Socorro na rua ou na estrada" é uma especialidade.'),
              ('Atende moto?', 'Sim, quem tem a especialidade "Pneu de moto" no perfil atende.')]),
    dict(slug='promotor-de-eventos', nome='Promotor de eventos', busca='promotor de eventos', icone='campaign',
         esp=['Promoção em PDV e supermercado', 'Degustação', 'Recepção e hostess', 'Panfletagem e divulgação', 'Staff de eventos', 'Demonstração de produtos', 'Credenciamento e controle de acesso', 'Feiras e exposições'],
         abre='Vai fazer uma ação no supermercado, uma degustação ou um evento? Encontre promotores e recepcionistas perto de você em Brasília e no Entorno, com avaliações de outros clientes.',
         quando=['Sua marca vai fazer degustação ou ação de vendas no supermercado.', 'Precisa de recepção, credenciamento ou staff para um evento ou uma festa.', 'Quer divulgar o seu negócio com panfletagem ou estande em feira.'],
         faq=[('Como é cobrado o promotor de eventos?', 'O mais comum é por diária, mas cada profissional define o próprio valor e a forma de cobrança. Você vê o preço antes de confirmar, e o app mostra a faixa da sua região como referência.'),
              ('Dá para contratar mais de um promotor para o mesmo evento?', 'Sim. Cada pedido vai para um profissional que você escolhe, então basta fazer um pedido para cada pessoa da equipe e combinar os detalhes pelo chat.')]),
    dict(slug='maquiadora', nome='Maquiadora', busca='maquiadora', icone='face_retouching_natural',
         esp=['Social', 'Noiva', 'Formatura', 'Penteado', 'Debutante', 'Maquiagem artística'],
         abre='Tem um evento hoje? Encontre uma maquiadora que atende em casa, perto de você em Brasília e no Entorno.',
         quando=['Tem festa, casamento ou formatura hoje.', 'Quer maquiagem e penteado sem sair de casa.', 'Precisa de maquiagem artística para um ensaio.'],
         faq=[('A maquiadora faz penteado também?', 'Quem tem a especialidade "Penteado" no perfil faz. Veja as fotos de trabalhos anteriores.'),
              ('Dá para chamar para hoje?', 'Sim. O iService é para atendimento no mesmo dia, e você escolhe o horário.')]),
]

FAQ_GERAL = [
    ('Quanto custa usar o iService?', 'Baixar e usar o app é grátis. Você paga só o valor do serviço, que o profissional informa antes de você confirmar.'),
    ('Quando o app vai estar disponível?', 'O lançamento nas lojas está previsto para o primeiro semestre de 2027. A versão de teste já pode ser baixada no site.'),
]

e = html.escape


def arquivo(p):
    return f"{p['slug']}-em-brasilia.html"


def molde():
    texto = (SITE / 'termos.html').read_text()
    inicio = texto.index('<main id="conteudo">')
    fim = texto.index('</main>') + len('</main>')
    return texto[:inicio], texto[fim:]


def montar_cabeca(cabeca, titulo, descricao, url, ld):
    cabeca = re.sub(r'<title>.*?</title>', f'<title>{e(titulo)}</title>', cabeca)
    cabeca = re.sub(r'(<meta name="description" content=")[^"]*', lambda m: m.group(1) + e(descricao), cabeca)
    cabeca = re.sub(r'(<meta property="og:description" content=")[^"]*', lambda m: m.group(1) + e(descricao), cabeca)
    cabeca = re.sub(r'(<meta property="og:title" content=")[^"]*', lambda m: m.group(1) + e(titulo), cabeca)
    cabeca = re.sub(r'(<link rel="canonical" href=")[^"]*', lambda m: m.group(1) + url, cabeca)
    cabeca = re.sub(r'(<meta property="og:url" content=")[^"]*', lambda m: m.group(1) + url, cabeca)
    script = '<script type="application/ld+json">\n' + json.dumps(ld, ensure_ascii=False, indent=2) + '\n</script>\n'
    return cabeca.replace('</head>', script + '</head>', 1)


def regioes_html():
    df = ''.join(f'<li>{e(r)}</li>' for r in REGIOES_DF)
    go = ''.join(f'<li>{e(r)}</li>' for r in REGIOES_GO)
    return f'''<h2 id="regioes">Onde atendemos</h2>
      <p>Todo o Distrito Federal e as cidades do Entorno. Cada profissional marca no mapa a área onde trabalha, e você vê quem está mais perto.</p>
      <h3>Distrito Federal</h3>
      <ul class="regioes">{df}</ul>
      <h3>Entorno (Goiás)</h3>
      <ul class="regioes">{go}</ul>'''


def faq_html(faq):
    return '\n'.join(f'''      <details>
        <summary>{e(q)}<span class="ms">expand_more</span></summary>
        <p>{e(r)}</p>
      </details>''' for q, r in faq)


def outras_html(atual):
    itens = ''.join(f'<li><a href="{arquivo(p)}">{e(p["nome"])}</a></li>' for p in PROFISSOES if p is not atual)
    return f'<ul class="outros-servicos">{itens}</ul>'


def migalhas(nome, url):
    return {'@type': 'BreadcrumbList', 'itemListElement': [
        {'@type': 'ListItem', 'position': 1, 'name': 'iService', 'item': DOMINIO},
        {'@type': 'ListItem', 'position': 2, 'name': nome, 'item': url}]}


def pagina_profissao(p, cabeca, rodape):
    url = DOMINIO + arquivo(p)
    titulo = f"{p['nome']} em Brasília e Entorno, atendimento hoje | iService"
    descricao = p['abre']
    faq = p['faq'] + FAQ_GERAL
    ld = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'Service', 'name': f"{p['nome']} em Brasília e Entorno", 'serviceType': p['nome'],
         'description': descricao, 'url': url,
         'provider': {'@type': 'Organization', 'name': 'iService', 'url': DOMINIO,
                      'logo': DOMINIO + 'assets/img/icon-512.png'},
         'areaServed': [{'@type': 'City', 'name': 'Brasília'}] + [{'@type': 'City', 'name': r} for r in REGIOES_GO],
         'hasOfferCatalog': {'@type': 'OfferCatalog', 'name': p['nome'],
                             'itemListElement': [{'@type': 'Offer', 'itemOffered': {'@type': 'Service', 'name': s}} for s in p['esp']]}},
        migalhas(p['nome'], url),
        {'@type': 'FAQPage', 'mainEntity': [{'@type': 'Question', 'name': q,
                                              'acceptedAnswer': {'@type': 'Answer', 'text': r}} for q, r in faq]}]}
    esp = ''.join(f'<li><span class="ms">check_circle</span>{e(s)}</li>' for s in p['esp'])
    quando = ''.join(f'<li>{e(q)}</li>' for q in p['quando'])
    corpo = f'''<main id="conteudo">
<section class="pagina-cabeca servico-cabeca">
  <div class="envolve">
    <nav class="migalhas" aria-label="Você está em"><a href="index.html">Início</a> › <a href="index.html#servicos">Serviços</a> › {e(p['nome'])}</nav>
    <span class="selo-servico"><span class="ms">{p['icone']}</span></span>
    <h1>{e(p['nome'])} em Brasília e Entorno</h1>
    <p>{e(p['abre'])}</p>
    <div class="chamadas">
      <a class="btn btn-laranja" href="#baixar" data-baixar="cliente"><span class="ms">download</span> Baixar o iService</a>
      <a class="btn btn-branco" href="profissionais.html">Sou profissional e quero clientes</a>
    </div>
  </div>
</section>
<div class="envolve servico-corpo">
  <article>
    <h2>Serviços de {e(p['busca'])} que você pede pelo app</h2>
    <p>Cada profissional marca no perfil as especialidades que domina. Na hora de pedir, você escolhe exatamente o que precisa:</p>
    <ul class="especialidades">{esp}</ul>

    <h2>Quando chamar</h2>
    <ul>{quando}</ul>

    <h2>Como funciona</h2>
    <ol class="passos-servico">
      <li><b>Veja quem está perto.</b> O mapa mostra os profissionais de {e(p['busca'])} perto de você, com os mais bem avaliados no topo.</li>
      <li><b>Escolha pelo perfil.</b> Compare avaliações com foto, especialidades, preço e distância.</li>
      <li><b>Peça para hoje.</b> Só o profissional que você escolheu recebe o pedido. Sem leilão e sem fila de orçamentos.</li>
      <li><b>Acompanhe tudo.</b> Chat, localização ao vivo e avaliação no final.</li>
    </ol>

    <h2>Preço justo e segurança</h2>
    <p>O preço é definido pelo profissional, e você vê o valor antes de confirmar. O app mostra a faixa de preço da sua região como referência. Todo profissional passa por análise de documento e selfie, e o atendimento tem a Garantia iService, com mediação se algo der errado.</p>

    {regioes_html()}

    <h2 id="duvidas">Perguntas frequentes</h2>
    <div class="faq">
{faq_html(faq)}
    </div>
  </article>
  <aside>
    <div class="cartao-lateral">
      <b>Precisa de {e(p['busca'])} hoje?</b>
      <p>Baixe o iService e veja quem está perto de você.</p>
      <a class="btn btn-azul" href="#baixar" data-baixar="cliente">Baixar o app</a>
    </div>
    {dicas_html(p)}
    <div class="cartao-lateral">
      <b>Outros serviços</b>
      {outras_html(p)}
    </div>
  </aside>
</div>
</main>'''
    return montar_cabeca(cabeca, titulo, descricao, url, ld) + corpo + rodape


def pagina_profissionais(cabeca, rodape):
    url = DOMINIO + 'profissionais.html'
    titulo = 'Trabalhe como autônomo em Brasília: receba clientes perto de você | iService'
    descricao = ('Profissional autônomo em Brasília ou no Entorno? Cadastre-se grátis no iService, defina seu preço e receba '
                 'pedidos de clientes perto de você. Eletricista, encanador, diarista, chaveiro e mais 16 profissões.')
    faq = [
        ('Quanto custa para o profissional?', 'Nada no lançamento. O cadastro e o uso do app são grátis para profissionais.'),
        ('Quem define o preço do serviço?', 'Você. O app mostra a faixa de preço da região só como referência para o cliente.'),
        ('Preciso ser MEI?', 'Não é obrigatório para se cadastrar. Se você for MEI, o app tem um relatório de ganhos que ajuda a acompanhar o limite anual.'),
        ('Como recebo os pedidos?', 'O cliente escolhe você pelo perfil e só você recebe o pedido. Você aceita ou recusa, sem disputa com outros profissionais.'),
        ('O que preciso para o cadastro?', 'Foto de perfil, documento com foto, CPF, endereço, as profissões que você exerce, suas especialidades e certificados. Para babás, a certidão de antecedentes é obrigatória.'),
    ]
    ld = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'WebPage', 'name': titulo, 'description': descricao, 'url': url,
         'about': {'@type': 'Organization', 'name': 'iService', 'url': DOMINIO}},
        migalhas('Para profissionais', url),
        {'@type': 'FAQPage', 'mainEntity': [{'@type': 'Question', 'name': q,
                                              'acceptedAnswer': {'@type': 'Answer', 'text': r}} for q, r in faq]}]}
    lista = ''.join(f'<li><a href="{arquivo(p)}">{e(p["nome"])}</a></li>' for p in PROFISSOES)
    corpo = f'''<main id="conteudo">
<section class="pagina-cabeca servico-cabeca">
  <div class="envolve">
    <nav class="migalhas" aria-label="Você está em"><a href="index.html">Início</a> › Para profissionais</nav>
    <h1>Mais clientes perto de você, para quem trabalha por conta própria</h1>
    <p>Se você é profissional autônomo em Brasília ou no Entorno, o iService leva até você quem precisa do seu serviço hoje. Cadastro grátis e sem mensalidade no lançamento.</p>
    <div class="chamadas">
      <a class="btn btn-laranja" href="profissional/" data-baixar="profissional">Quero me cadastrar <span class="ms">arrow_forward</span></a>
      <a class="btn btn-branco" data-contato="whatsapp" data-manter-texto data-se-contato="whatsapp"><span class="ms">chat</span> Tirar dúvidas no WhatsApp</a>
    </div>
  </div>
</section>
<div class="envolve servico-corpo">
  <article>
    <h2>Por que trabalhar com o iService</h2>
    <ul class="especialidades">
      <li><span class="ms">payments</span>Você define o preço de cada serviço</li>
      <li><span class="ms">how_to_reg</span>O pedido é só seu: o cliente escolheu você</li>
      <li><span class="ms">toggle_on</span>Trabalhe quando quiser, com o modo disponível</li>
      <li><span class="ms">location_on</span>Escolha no mapa a área onde você atende</li>
      <li><span class="ms">photo_library</span>Portfólio com fotos de antes e depois</li>
      <li><span class="ms">bar_chart</span>Relatório de ganhos, pronto para quem é MEI</li>
      <li><span class="ms">verified</span>Selo de verificado para passar confiança</li>
      <li><span class="ms">emoji_events</span>Quem atende bem sobe no ranking da região</li>
    </ul>

    <h2>Como conseguir mais clientes como autônomo</h2>
    <p>No iService, os clientes procuram pelo serviço e veem no mapa quem está perto. A ordem é pela qualidade: avaliação, serviços concluídos, confiabilidade e distância. Quem é novo também ganha espaço, para começar a ser avaliado. Não existe pagamento para aparecer primeiro.</p>
    <ol class="passos-servico">
      <li><b>Faça o cadastro.</b> Foto, documento, profissões, especialidades e certificados.</li>
      <li><b>Espere a aprovação.</b> Nossa equipe confere seus dados e avisa por e-mail.</li>
      <li><b>Ligue o modo disponível.</b> Os pedidos chegam no celular, com o endereço e a distância.</li>
      <li><b>Atenda e seja avaliado.</b> Boas avaliações levam você ao topo da sua região.</li>
    </ol>

    <h2>Profissões aceitas</h2>
    <ul class="outros-servicos">{lista}</ul>

    {regioes_html()}

    <h2 id="duvidas">Perguntas frequentes</h2>
    <div class="faq">
{faq_html(faq)}
    </div>
  </article>
  <aside>
    <div class="cartao-lateral">
      <b>Comece agora</b>
      <p>O cadastro é grátis e leva poucos minutos.</p>
      <a class="btn btn-laranja" href="profissional/" data-baixar="profissional">Quero me cadastrar</a>
    </div>
    {dicas_profissionais_html()}
  </aside>
</div>
</main>'''
    return montar_cabeca(cabeca, titulo, descricao, url, ld) + corpo + rodape


# ---------------------------------------------------------------- blog

def ler_artigos():
    artigos = []
    for f in sorted(BLOG_FONTES.glob('*.html')):
        texto = f.read_text()
        m = re.match(r'\s*<!--(.*?)-->\s*', texto, re.S)
        a = json.loads(m.group(1))
        a['slug'] = f.stem
        a['corpo'] = texto[m.end():].strip()
        a.setdefault('faq', [])
        a.setdefault('profissoes', [])
        a.setdefault('atualizado', a['publicado'])
        palavras = len(re.sub(r'<[^>]+>', ' ', a['corpo']).split())
        a['leitura'] = max(2, round(palavras / 200))
        artigos.append(a)
    artigos.sort(key=lambda a: a['titulo'])
    artigos.sort(key=lambda a: (a['publicado'], a.get('destaque', 0)), reverse=True)
    return artigos


ARTIGOS = []


def url_artigo(a):
    return f"blog/{a['slug']}.html"


def data_br(iso):
    ano, mes, dia = iso.split('-')
    return f'{int(dia)} de {MESES[int(mes) - 1]} de {ano}'


def subir(texto):
    """Ajusta links relativos para páginas dentro de site/blog/."""
    return re.sub(r'(\s(?:href|src)=")(?!https?:|#|/|mailto:|tel:|data:|\.\./)', r'\1../', texto)


def dicas_html(p):
    lista = [a for a in ARTIGOS if p['slug'] in a['profissoes']]
    if not lista:
        return ''
    itens = ''.join(f'<li><a href="{url_artigo(a)}">{e(a["titulo"])}</a></li>' for a in lista[:3])
    return f"""<div class="cartao-lateral">
      <b>Dicas do blog</b>
      <ul class="outros-servicos">{itens}</ul>
    </div>"""


def dicas_profissionais_html():
    lista = [a for a in ARTIGOS if a['publico'] == 'profissional']
    if not lista:
        return ''
    itens = ''.join(f'<li><a href="{url_artigo(a)}">{e(a["titulo"])}</a></li>' for a in lista[:3])
    return f"""<div class="cartao-lateral">
      <b>Dicas para autônomos</b>
      <ul class="outros-servicos">{itens}</ul>
    </div>"""


def cartao_artigo(a, titulo_tag='h3'):
    return f"""<a class="cartao-artigo" href="{url_artigo(a)}">
        <span class="selo-artigo"><span class="ms">{a['icone']}</span></span>
        <span class="categoria">{e(a['categoria'])}</span>
        <{titulo_tag}>{e(a['titulo'])}</{titulo_tag}>
        <p>{e(a['descricao'])}</p>
        <span class="leia">Ler artigo · {a['leitura']} min <span class="ms">arrow_forward</span></span>
      </a>"""


def pagina_artigo(a, cabeca, rodape):
    url = DOMINIO + url_artigo(a)
    titulo = f"{a['titulo']} | Blog iService"
    profs = [p for s in a['profissoes'] for p in PROFISSOES if p['slug'] == s]
    org = {'@type': 'Organization', 'name': 'iService', 'url': DOMINIO,
           'logo': {'@type': 'ImageObject', 'url': DOMINIO + 'assets/img/icon-512.png'}}
    post = {'@type': 'BlogPosting', 'headline': a['titulo'], 'description': a['descricao'], 'url': url,
            'mainEntityOfPage': url, 'datePublished': a['publicado'], 'dateModified': a['atualizado'],
            'inLanguage': 'pt-BR', 'image': DOMINIO + 'og-image.jpg', 'articleSection': a['categoria'],
            'author': org, 'publisher': org,
            'isPartOf': {'@type': 'Blog', 'name': 'Blog iService', 'url': DOMINIO + 'blog/'},
            'spatialCoverage': {'@type': 'Place', 'name': 'Brasília e Entorno'}}
    if profs:
        post['about'] = [{'@type': 'Service', 'name': p['nome'], 'url': DOMINIO + arquivo(p)} for p in profs]
    grafo = [post, {'@type': 'BreadcrumbList', 'itemListElement': [
        {'@type': 'ListItem', 'position': 1, 'name': 'iService', 'item': DOMINIO},
        {'@type': 'ListItem', 'position': 2, 'name': 'Blog', 'item': DOMINIO + 'blog/'},
        {'@type': 'ListItem', 'position': 3, 'name': a['titulo'], 'item': url}]}]
    if a['faq']:
        grafo.append({'@type': 'FAQPage', 'mainEntity': [
            {'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': r}} for q, r in a['faq']]})
    ld = {'@context': 'https://schema.org', '@graph': grafo}
    cab = montar_cabeca(cabeca, titulo, a['descricao'], url, ld)
    cab = cab.replace('<meta property="og:type" content="website">',
                      '<meta property="og:type" content="article">\n'
                      f'<meta property="article:published_time" content="{a["publicado"]}">\n'
                      f'<meta property="article:modified_time" content="{a["atualizado"]}">')

    if a['publico'] == 'profissional':
        chamadas = """<a class="btn btn-laranja" href="profissional/" data-baixar="profissional">Quero me cadastrar <span class="ms">arrow_forward</span></a>
      <a class="btn btn-branco" href="profissionais.html">Como funciona para profissionais</a>"""
        lateral = """<div class="cartao-lateral">
      <b>Receba clientes perto de você</b>
      <p>Cadastro grátis no lançamento. Você define o preço e o pedido chega só para você.</p>
      <a class="btn btn-laranja" href="profissional/" data-baixar="profissional">Quero me cadastrar</a>
    </div>"""
    else:
        alvo = profs[0] if profs else None
        nome = alvo['busca'] if alvo else 'um profissional'
        chamadas = '<a class="btn btn-laranja" href="#baixar" data-baixar="cliente"><span class="ms">download</span> Baixar o iService</a>'
        if alvo:
            chamadas += f'\n      <a class="btn btn-branco" href="{arquivo(alvo)}">Ver {e(alvo["busca"])} perto de você</a>'
        lateral = f"""<div class="cartao-lateral">
      <b>Precisa de {e(nome)} hoje?</b>
      <p>Veja no mapa quem está perto, compare avaliações e preço e chame quem preferir.</p>
      <a class="btn btn-azul" href="#baixar" data-baixar="cliente">Baixar o app</a>
    </div>"""
    servicos = ''
    if profs:
        itens = ''.join(f'<li><a href="{arquivo(p)}">{e(p["nome"])} em Brasília</a></li>' for p in profs)
        servicos = f"""<div class="cartao-lateral">
      <b>Serviços deste artigo</b>
      <ul class="outros-servicos">{itens}</ul>
    </div>"""
    outros = [o for o in ARTIGOS if o is not a]
    outros.sort(key=lambda o: (o['publico'] != a['publico'], -len(set(o['profissoes']) & set(a['profissoes']))))
    leia = ''.join(cartao_artigo(o) for o in outros[:3])
    faq = ''
    if a['faq']:
        faq = f"""
    <h2 id="duvidas">Perguntas frequentes</h2>
    <div class="faq">
{faq_html(a['faq'])}
    </div>"""
    corpo = f"""<main id="conteudo">
<section class="pagina-cabeca servico-cabeca artigo-cabeca">
  <div class="envolve">
    <nav class="migalhas" aria-label="Você está em"><a href="index.html">Início</a> › <a href="blog/">Blog</a> › {e(a['categoria'])}</nav>
    <span class="categoria-artigo"><span class="ms">{a['icone']}</span>{e(a['categoria'])}</span>
    <h1>{e(a['titulo'])}</h1>
    <p>{e(a['descricao'])}</p>
    <p class="artigo-meta"><time datetime="{a['publicado']}">{data_br(a['publicado'])}</time> · {a['leitura']} min de leitura · Equipe iService</p>
    <div class="chamadas">
      {chamadas}
    </div>
  </div>
</section>
<div class="envolve servico-corpo">
  <article class="artigo-texto">
{a['corpo']}
{faq}
  </article>
  <aside>
    {lateral}
    {servicos}
  </aside>
</div>
<section class="secao cinza leia-tambem">
  <div class="envolve">
    <div class="cabeca"><span class="etiqueta">Continue lendo</span><h2>Mais dicas do iService</h2></div>
    <div class="blog-grade">
      {leia}
    </div>
  </div>
</section>
</main>"""
    return subir(cab + corpo + rodape)


def pagina_blog(cabeca, rodape):
    url = DOMINIO + 'blog/'
    titulo = 'Blog iService: dicas de casa e serviços em Brasília e Entorno'
    descricao = ('Dicas práticas para resolver hoje os imprevistos da casa e do carro em Brasília e no Entorno: '
                 'preços, emergências, segurança e conselhos para profissionais autônomos.')
    ld = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'Blog', 'name': 'Blog iService', 'description': descricao, 'url': url, 'inLanguage': 'pt-BR',
         'publisher': {'@type': 'Organization', 'name': 'iService', 'url': DOMINIO},
         'blogPost': [{'@type': 'BlogPosting', 'headline': a['titulo'], 'url': DOMINIO + url_artigo(a),
                       'datePublished': a['publicado']} for a in ARTIGOS]},
        migalhas('Blog', url)]}
    clientes = ''.join(cartao_artigo(a, 'h2') for a in ARTIGOS if a['publico'] != 'profissional')
    profissionais = ''.join(cartao_artigo(a, 'h2') for a in ARTIGOS if a['publico'] == 'profissional')
    corpo = f"""<main id="conteudo">
<section class="pagina-cabeca servico-cabeca">
  <div class="envolve">
    <nav class="migalhas" aria-label="Você está em"><a href="index.html">Início</a> › Blog</nav>
    <h1>Blog iService</h1>
    <p>Dicas para resolver hoje os imprevistos da casa e do carro em Brasília e no Entorno, e conselhos para quem trabalha por conta própria.</p>
  </div>
</section>
<section class="secao blog-lista">
  <div class="envolve">
    <h2 class="blog-titulo-grupo">Para a sua casa e o seu carro</h2>
    <div class="blog-grade">
      {clientes}
    </div>
    <h2 class="blog-titulo-grupo">Para profissionais</h2>
    <div class="blog-grade">
      {profissionais}
    </div>
  </div>
</section>
</main>"""
    return subir(montar_cabeca(cabeca, titulo, descricao, url, ld) + corpo + rodape)


def atualizar_inicio():
    """Reescreve a seção entre <!-- blog:inicio --> e <!-- blog:fim --> de index.html."""
    arq = SITE / 'index.html'
    texto = arq.read_text()
    cartoes = ''.join(cartao_artigo(a) for a in ARTIGOS[:3])
    secao = f"""<!-- blog:inicio -->
<section class="secao" id="dicas">
  <div class="envolve">
    <div class="cabeca centro">
      <span class="etiqueta">Blog</span>
      <h2>Dicas para resolver hoje</h2>
      <p>O que fazer quando falta luz, vaza água ou a chave some, e quanto costuma custar.</p>
    </div>
    <div class="blog-grade">
      {cartoes}
    </div>
    <p class="ver-todas"><a class="btn btn-contorno-escuro" href="blog/">Ver todas as dicas <span class="ms">arrow_forward</span></a></p>
  </div>
</section>
<!-- blog:fim -->"""
    texto = re.sub(r'<!-- blog:inicio -->.*?<!-- blog:fim -->', lambda m: secao, texto, flags=re.S)
    arq.write_text(texto)


def sitemap():
    urls = [(u, HOJE) for u in ['', 'profissionais.html'] + [arquivo(p) for p in PROFISSOES]]
    urls += [('blog/', max([a['atualizado'] for a in ARTIGOS] or [HOJE]))]
    urls += [(url_artigo(a), a['atualizado']) for a in ARTIGOS]
    urls += [(u, HOJE) for u in ['termos.html', 'privacidade.html', 'excluir-conta.html']]
    corpo = ''.join(f'  <url>\n    <loc>{DOMINIO}{u}</loc>\n    <lastmod>{d}</lastmod>\n  </url>\n' for u, d in urls)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{corpo}</urlset>\n'


def main():
    ARTIGOS[:] = ler_artigos()
    cabeca, rodape = molde()
    (SITE / 'blog').mkdir(exist_ok=True)
    for velho in (SITE / 'blog').glob('*.html'):
        velho.unlink()
    for a in ARTIGOS:
        (SITE / url_artigo(a)).write_text(pagina_artigo(a, cabeca, rodape))
    (SITE / 'blog' / 'index.html').write_text(pagina_blog(cabeca, rodape))
    atualizar_inicio()
    for p in PROFISSOES:
        (SITE / arquivo(p)).write_text(pagina_profissao(p, cabeca, rodape))
    (SITE / 'profissionais.html').write_text(pagina_profissionais(cabeca, rodape))
    (SITE / 'sitemap.xml').write_text(sitemap())
    print(f'{len(PROFISSOES)} profissões + profissionais.html + {len(ARTIGOS)} artigos do blog + sitemap.xml')


if __name__ == '__main__':
    main()
