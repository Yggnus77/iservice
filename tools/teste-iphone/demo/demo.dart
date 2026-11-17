// Dados de exemplo locais para as capturas de tela do site. Nada aqui fala com o banco.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_catalogo.dart';
import 'iservice_core.dart';

final _db = SupabaseClient('http://127.0.0.1:9', 'demo');
final _agora = DateTime.now();
DateTime _m(int min) => _agora.add(Duration(minutes: min));
String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Etapa escolhida pela URL (?etapa=...).
final etapaDemo = Uri.base.queryParameters['etapa'] ?? 'caminho';

const _ana = 'u-ana';
const _carlos = 'u-carlos';
const _anaLat = -15.8145, _anaLng = -47.9005;

String img(String n) => 'img/$n.png';

final _pros = <Map<String, dynamic>>[
  {'profissional_id': _carlos, 'nome': 'Carlos Henrique Souza', 'foto_url': img('carlos'), 'nota_media': 4.9, 'total_avaliacoes': 87, 'servicos_concluidos': 112, 'anos_experiencia': 12, 'verificado': true, 'distancia_km': 1.2, 'preco_a_partir': 120, 'especialidades': ['Chuveiro elétrico', 'Quadro de luz e disjuntores'], 'posicao': 1, 'favorito': true},
  {'profissional_id': 'u-fernanda', 'nome': 'Fernanda Ribeiro', 'foto_url': img('fernanda'), 'nota_media': 4.9, 'total_avaliacoes': 54, 'servicos_concluidos': 70, 'anos_experiencia': 8, 'verificado': true, 'distancia_km': 2.6, 'preco_a_partir': 130, 'especialidades': ['Instalação elétrica', 'Iluminação e luminárias'], 'posicao': 2},
  {'profissional_id': 'u-marcos', 'nome': 'Marcos Vinícius Lima', 'foto_url': img('marcos'), 'nota_media': 4.8, 'total_avaliacoes': 41, 'servicos_concluidos': 63, 'anos_experiencia': 6, 'verificado': true, 'distancia_km': 3.4, 'preco_a_partir': 110, 'especialidades': ['Chuveiro elétrico', 'Ventilador de teto'], 'posicao': 3},
  {'profissional_id': 'u-roberto', 'nome': 'Roberto Alves', 'foto_url': img('roberto'), 'nota_media': 4.7, 'total_avaliacoes': 29, 'servicos_concluidos': 38, 'anos_experiencia': 20, 'verificado': true, 'distancia_km': 4.1, 'preco_a_partir': 125, 'especialidades': ['Padrão de energia', 'Quadro de luz e disjuntores'], 'posicao': 4},
  {'profissional_id': 'u-luciana', 'nome': 'Luciana Costa', 'foto_url': img('luciana'), 'nota_media': 0, 'total_avaliacoes': 0, 'servicos_concluidos': 3, 'anos_experiencia': 4, 'verificado': true, 'distancia_km': 2.1, 'preco_a_partir': 115, 'especialidades': ['Tomadas e interruptores'], 'posicao': 5, 'novo': true},
];

final _posicoes = <String, ({double lat, double lng})>{
  _carlos: (lat: -15.8072, lng: -47.8935),
  'u-fernanda': (lat: -15.8230, lng: -47.9110),
  'u-marcos': (lat: -15.8010, lng: -47.9120),
  'u-roberto': (lat: -15.8300, lng: -47.8890),
  'u-luciana': (lat: -15.8195, lng: -47.8870),
};

final List<Profissao> _profissoes = [for (final p in jsonDecode(catalogoDemoJson) as List) Profissao.fromJson(p)];

class DemoCatalogo extends CatalogoRepo {
  DemoCatalogo() : super(_db);
  @override
  Future<List<Profissao>> profissoes() async => _profissoes;
  @override
  Future<List<Regiao>> regioes() async => const [Regiao(id: 'asa-sul', nome: 'Asa Sul', uf: 'DF', faixaPreco: 1)];
  @override
  Future<List<CertificacaoSugerida>> certificacoesSugeridas() async => const [];
  @override
  Future<Map<String, dynamic>> config() async => {'dias_max_combinado': 7, 'prazo_resposta_min': 5, 'taxa_urgencia': 15, 'dias_garantia': 30, 'limite_anual_mei': 81000};
  @override
  Future<String?> regiaoProxima(double lat, double lng) async => 'asa-sul';
  @override
  Future<FaixaPreco?> faixaPreco(int especialidadeId, String? regiaoId, [Cobranca cobranca = Cobranca.servico]) async =>
      const FaixaPreco(minimo: 95, maximo: 150, estimada: false);
}

Map<String, dynamic> _perfilJson(bool pro) => {
      'perfil': pro
          ? {'id': _carlos, 'nome': 'Carlos Henrique Souza', 'email': 'carlos@exemplo.com', 'telefone': '61999990000', 'cpf': '00000000000', 'nascimento': '1988-03-10', 'foto_url': img('carlos'), 'e_cliente': false, 'e_profissional': true, 'termos_versao': ConfigIService.versaoTermos}
          : {'id': _ana, 'nome': 'Ana Beatriz', 'email': 'ana@exemplo.com', 'telefone': '61988880000', 'cpf': '00000000000', 'nascimento': '1992-06-21', 'foto_url': img('ana'), 'e_cliente': true, 'termos_versao': ConfigIService.versaoTermos},
      'enderecos': [
        pro
            ? {'id': 2, 'rotulo': 'Casa', 'logradouro': 'SQS 113', 'bloco': 'Bloco F', 'regiao_id': 'asa-sul', 'lat': -15.8250, 'lng': -47.9150, 'principal': true}
            : {'id': 1, 'rotulo': 'Casa', 'logradouro': 'SQS 308', 'bloco': 'Bloco C', 'complemento': 'Apto 101', 'regiao_id': 'asa-sul', 'lat': _anaLat, 'lng': _anaLng, 'principal': true},
      ],
      'profissional': pro
          ? {'status': 'aprovado', 'disponivel': true, 'verificado': true, 'atende_24h': true, 'bio': 'Eletricista há 12 anos, com NR-10.', 'anos_experiencia': 12, 'area_lat': -15.8250, 'area_lng': -47.9150, 'area_raio_km': 15, 'regiao_id': 'asa-sul', 'nota_media': 4.9, 'total_avaliacoes': 87, 'servicos_concluidos': 112, 'pedidos_recebidos': 120, 'pedidos_aceitos': 116}
          : null,
      'pontos': pro ? 0 : 120,
    };

class DemoConta extends ContaRepo {
  DemoConta(this.pro) : super(_db);
  final bool pro;
  @override
  Future<MeuPerfil?> meuPerfil() async => MeuPerfil.fromJson(_perfilJson(pro));
  @override
  Future<void> definirLetraGrande(bool ligado) async {}
}

class DemoBusca extends BuscaRepo {
  DemoBusca() : super(_db);
  @override
  Future<List<ProfissionalResumo>> buscar({required String profissaoId, required double lat, required double lng, int? especialidadeId, bool porDistancia = false, int rodizio = 0, bool urgencia24h = false}) async {
    final l = [for (final p in _pros) ProfissionalResumo.fromJson({...p, 'profissao_id': profissaoId})];
    if (porDistancia) l.sort((a, b) => a.distanciaKm.compareTo(b.distanciaKm));
    return l;
  }

  @override
  Future<Map<String, ({double lat, double lng})>> posicoesMapa(List<String> ids) async => {for (final id in ids) if (_posicoes[id] != null) id: _posicoes[id]!};

  @override
  Future<Map<String, PrecoBusca>> precos(List<String> ids, String profissaoId, int? especialidadeId) async => {
        for (final p in _pros) p['profissional_id'] as String: PrecoBusca((p['preco_a_partir'] as num).toDouble(), Cobranca.servico),
      };

  @override
  Future<List<ProfissionalResumo>> topRegiao({required double lat, required double lng, String? profissaoId, int limite = 10, int rodizio = 0}) async => [
        ProfissionalResumo.fromJson({..._pros[0], 'profissao_id': 'eletricista', 'posicao': 1}),
        ProfissionalResumo.fromJson({'profissional_id': 'u-beatriz', 'nome': 'Beatriz Moura', 'foto_url': img('beatriz'), 'profissao_id': 'faxineira', 'nota_media': 4.9, 'total_avaliacoes': 64, 'servicos_concluidos': 90, 'verificado': true, 'distancia_km': 1.8, 'posicao': 2}),
        ProfissionalResumo.fromJson({'profissional_id': 'u-paulo', 'nome': 'Paulo Mendes', 'foto_url': img('paulo'), 'profissao_id': 'encanador', 'nota_media': 4.8, 'total_avaliacoes': 52, 'servicos_concluidos': 71, 'verificado': true, 'distancia_km': 2.2, 'posicao': 3}),
        ProfissionalResumo.fromJson({..._pros[1], 'profissao_id': 'eletricista', 'posicao': 4}),
      ];

  @override
  Future<PerfilProfissional?> perfil(String id) async {
    final r = _pros.firstWhere((p) => p['profissional_id'] == id, orElse: () => _pros.first);
    final esp = _profissoes.first.especialidades;
    double preco(String n) => switch (n) {
          'Chuveiro elétrico' => 120,
          'Quadro de luz e disjuntores' => 180,
          'Tomadas e interruptores' => 80,
          'Ventilador de teto' => 150,
          'Instalação elétrica' => 200,
          'Iluminação e luminárias' => 90,
          _ => 130,
        };
    return PerfilProfissional.fromJson({
      'id': r['profissional_id'],
      'nome': r['nome'],
      'foto_url': r['foto_url'],
      'bio': 'Eletricista há 12 anos, com NR-10. Atendo Asa Sul, Asa Norte, Sudoeste e Lago Sul. Chego com material básico e deixo tudo limpo.',
      'anos_experiencia': r['anos_experiencia'],
      'verificado': true,
      'disponivel': true,
      'nota_media': r['nota_media'],
      'total_avaliacoes': r['total_avaliacoes'],
      'servicos_concluidos': r['servicos_concluidos'],
      'minutos_trabalhados': 9480,
      'regiao': 'Asa Sul',
      'membro_desde': '2026-11-01T00:00:00Z',
      'tempo_resposta_seg': 120,
      'favorito': r['favorito'] ?? false,
      'profissoes': [
        {
          'id': 'eletricista',
          'nome': 'Eletricista',
          'icone': 'bolt',
          'especialidades': [
            for (final e in esp.where((e) => const ['Chuveiro elétrico', 'Quadro de luz e disjuntores', 'Tomadas e interruptores', 'Ventilador de teto'].contains(e.nome)))
              {'id': e.id, 'nome': e.nome, 'preco': preco(e.nome), 'cobranca': 'servico'},
          ],
        },
      ],
      'certificacoes': [
        {'nome': 'NR-10'},
        {'nome': 'NR-35 (trabalho em altura)'},
        {'nome': 'Curso SENAI'},
      ],
      'avaliacoes_recentes': [
        {'nota': 5, 'comentario': 'Trocou a resistência do chuveiro em 20 minutos e ainda revisou o disjuntor. Muito educado.', 'criada_em': _iso(_m(-60 * 26)), 'cliente_nome': 'Juliana M.', 'cliente_foto': img('juliana'), 'resposta': 'Obrigado, Juliana! Qualquer coisa é só chamar.'},
        {'nota': 5, 'comentario': 'Pontual e caprichoso. Explicou tudo antes de começar.', 'criada_em': _iso(_m(-60 * 72)), 'cliente_nome': 'Paulo R.', 'cliente_foto': img('paulo')},
      ],
      'distribuicao_notas': {'5': 80, '4': 6, '3': 1, '2': 0, '1': 0},
    });
  }

  @override
  Future<List<ProfissionalResumo>> favoritos() async => [ProfissionalResumo.fromJson({..._pros[0], 'profissao_id': 'eletricista'})];
  @override
  Future<void> favoritar(String profissionalId, bool favorito) async {}
}

/// Pedido principal: Ana pede o eletricista Carlos para o chuveiro.
Pedido pedidoPrincipal({required bool pro}) {
  final status = switch (etapaDemo) {
    'solicitado' => StatusPedido.solicitado,
    'aceito' => StatusPedido.aceito,
    'caminho' => StatusPedido.aCaminho,
    'atendimento' => StatusPedido.emAtendimento,
    _ => StatusPedido.concluido,
  };
  final s = status.index;
  return Pedido(
    id: 'p1',
    codigo: 'A3F9C2',
    status: status,
    quando: QuandoPedido.agora,
    profissaoId: 'eletricista',
    especialidade: 'Chuveiro elétrico',
    descricao: 'O chuveiro desarma o disjuntor quando liga no quente. Já troquei a resistência e continuou.',
    enderecoTexto: 'SQS 308, Bloco C, Apto 101, Brasília/DF',
    distanciaKm: 1.2,
    precoInformado: 120,
    taxaUrgencia: 15,
    valorCobrado: status == StatusPedido.concluido ? 135 : null,
    responderAte: _m(4).add(const Duration(seconds: 12)),
    criadoEm: status == StatusPedido.solicitado ? _m(-1) : _m(status == StatusPedido.aCaminho ? -8 : -48),
    concluidoEm: status == StatusPedido.concluido ? _m(-2) : null,
    aceitoEm: s >= 1 ? _m(status == StatusPedido.aCaminho ? -7 : -46) : null,
    aCaminhoEm: s >= 2 ? _m(status == StatusPedido.aCaminho ? -5 : -44) : null,
    iniciadoEm: s >= 3 ? _m(-31) : null,
    minutosTrabalhados: status == StatusPedido.concluido ? 46 : null,
    outraParteId: pro ? _ana : _carlos,
    outraParteNome: pro ? 'Ana Beatriz' : 'Carlos Henrique Souza',
    outraParteFoto: pro ? img('ana') : img('carlos'),
    naoLidas: status == StatusPedido.aCaminho && !pro ? 1 : 0,
  );
}

Pedido _agendado(String id, String cod, String nome, String foto, String esp, String desc, String end, DateTime quando, double preco) => Pedido(
      id: id,
      codigo: cod,
      status: StatusPedido.aceito,
      quando: QuandoPedido.combinado,
      combinadoPara: quando,
      profissaoId: 'eletricista',
      especialidade: esp,
      descricao: desc,
      enderecoTexto: end,
      distanciaKm: 3.1,
      precoInformado: preco,
      taxaUrgencia: 0,
      responderAte: _m(-600),
      criadoEm: _m(-60 * 20),
      aceitoEm: _m(-60 * 19),
      outraParteId: 'c-$id',
      outraParteNome: nome,
      outraParteFoto: img(foto),
    );

DateTime _dia(int dias, int h, [int min = 0]) {
  final d = _agora.add(Duration(days: dias));
  return DateTime(d.year, d.month, d.day, h, min);
}

List<Pedido> _agenda() => [
      _agendado('p2', 'B71D04', 'Paulo Mendes', 'paulo', 'Tomadas e interruptores', 'Trocar 4 tomadas da cozinha para o padrão novo.', 'SQN 210, Bloco A, Apto 302, Brasília/DF', _dia(1, 9), 80),
      _agendado('p3', 'C20E9A', 'Juliana Martins', 'juliana', 'Ventilador de teto', 'Instalar ventilador de teto no quarto (já comprei).', 'SQS 206, Bloco H, Apto 504, Brasília/DF', _dia(1, 14, 30), 150),
      _agendado('p4', 'D9A1F3', 'Beatriz Moura', 'beatriz', 'Quadro de luz e disjuntores', 'Disjuntor geral esquentando. Quero uma revisão do quadro.', 'SHIS QI 9, Conjunto 4, Lago Sul', _dia(3, 10), 180),
    ];

List<Pedido> _concluidos() => [
      for (final (i, (nome, foto, esp, valor, dias)) in [
        ('Juliana Martins', 'juliana', 'Chuveiro elétrico', 130.0, 0),
        ('Paulo Mendes', 'paulo', 'Tomadas e interruptores', 95.0, 1),
        ('Roberta Lima', 'luciana', 'Iluminação e luminárias', 160.0, 2),
        ('Marcos Teixeira', 'marcos', 'Quadro de luz e disjuntores', 220.0, 3),
      ].indexed)
        Pedido(
          id: 'c$i',
          codigo: 'E${i}0F1A',
          status: StatusPedido.concluido,
          quando: QuandoPedido.hoje,
          profissaoId: 'eletricista',
          especialidade: esp,
          descricao: '',
          enderecoTexto: 'Asa Sul, Brasília/DF',
          taxaUrgencia: 0,
          valorCobrado: valor,
          precoInformado: valor,
          responderAte: _m(-60 * 24 * dias - 120),
          criadoEm: _m(-60 * 24 * dias - 180),
          concluidoEm: _m(-60 * 24 * dias - 60),
          minutosTrabalhados: 50,
          outraParteNome: nome,
          outraParteFoto: img(foto),
          avaliado: true,
        ),
    ];

class DemoPedidos extends PedidosRepo {
  DemoPedidos(this.pro) : super(_db);
  final bool pro;

  @override
  Future<List<Pedido>> meus({required String papel, String grupo = 'todos'}) async {
    final p = pedidoPrincipal(pro: pro);
    final andamento = [if (p.status.emAndamento) p, if (pro) ..._agenda()];
    return switch (grupo) {
      'andamento' => andamento,
      'concluidos' => [if (!p.status.emAndamento) p, if (pro) ..._concluidos()],
      _ => [...andamento, if (!p.status.emAndamento) p, if (pro) ..._concluidos()],
    };
  }

  @override
  Stream<Pedido> acompanhar(Pedido base) => Stream.value(base.id == 'p1' ? pedidoPrincipal(pro: pro) : base);
  @override
  Stream<PosicaoAoVivo?> posicaoAoVivo(String pedidoId) => Stream.value(PosicaoAoVivo(
        lat: -15.8098,
        lng: -47.8957,
        destinoLat: _anaLat,
        destinoLng: _anaLng,
        atualizadoEm: _agora.subtract(const Duration(seconds: 8)),
      ));
  @override
  Future<void> enviarPosicao(String pedidoId, {required double lat, required double lng, double? precisao}) async {}
  @override
  Stream<void> mudancas(String papel) => const Stream.empty();
  @override
  Future<ResumoCliente?> resumoCliente(String pedidoId) async => const ResumoCliente(nota: 4.9, total: 14);
  @override
  Future<ResumoCliente?> minhaNotaCliente() async => const ResumoCliente(nota: 4.9, total: 14);
  @override
  Future<List<DateTime>> horariosOcupados(String profissionalId) async => const [];
}

class DemoChat extends ChatRepo {
  DemoChat() : super(_db);
  @override
  Stream<List<Mensagem>> mensagens(String pedidoId) => Stream.value([
        Mensagem(id: 1, pedidoId: pedidoId, autorId: _carlos, texto: 'Bom dia, Ana! Aqui é o Carlos. Já estou indo, chego em uns 10 minutos.', criadaEm: _m(-43)),
        Mensagem(id: 2, pedidoId: pedidoId, autorId: _ana, texto: 'Bom dia! Pode subir direto, o porteiro já está avisado. Bloco C, apto 101.', criadaEm: _m(-42), lidaEm: _m(-41)),
        Mensagem(id: 3, pedidoId: pedidoId, autorId: _carlos, texto: 'Combinado. Se puder, deixe o disjuntor do chuveiro desligado até eu chegar.', criadaEm: _m(-41)),
      ]);
  @override
  Future<void> enviar(String pedidoId, String texto) async {}
  @override
  Future<void> marcarLidas(String pedidoId) async {}
}

class DemoNotificacoes extends NotificacoesRepo {
  DemoNotificacoes(this.pro) : super(_db);
  final bool pro;
  @override
  Stream<List<Notificacao>> todas() => Stream.value([
        if (pro)
          Notificacao(id: 1, tipo: 'pedido_novo', titulo: 'Novo pedido de Ana', corpo: 'Chuveiro elétrico · Agora · 1,2 km', lida: etapaDemo != 'solicitado', criadaEm: _m(-1))
        else ...[
          Notificacao(id: 2, tipo: 'pedido', titulo: 'Carlos está a caminho', corpo: 'Acompanhe pelo mapa.', lida: false, criadaEm: _m(-44)),
          Notificacao(id: 1, tipo: 'pedido', titulo: 'Carlos aceitou seu pedido', corpo: 'Acompanhe pelo app.', lida: true, criadaEm: _m(-46)),
        ],
      ]);
  @override
  Future<void> marcarLidas() async {}
}

class DemoArquivos extends ArquivosRepo {
  DemoArquivos() : super(_db);
  @override
  String urlPublica(String bucket, String caminho) => caminho;
  @override
  Future<String> urlTemporaria(String bucket, String caminho) async => caminho;
}

class DemoProfissional extends ProfissionalRepo {
  DemoProfissional() : super(_db);
  @override
  Future<List<String>> pendencias() async => const [];
  @override
  Future<void> definirDisponivel(bool v) async {}
  @override
  Future<MinhasProfissoes> minhasProfissoes() async =>
      const MinhasProfissoes(profissoes: {'eletricista': true}, especialidades: {3: 120, 4: 180, 2: 80, 6: 150});
  @override
  Future<List<DocumentoEnviado>> documentos() async => const [];
  @override
  Future<List<Map<String, dynamic>>> certificacoes() async => const [];
  @override
  Future<List<ItemPortfolio>> portfolio() async => const [];
  @override
  Future<ResumoGanhos> ganhos({DateTime? inicio, DateTime? fim}) async {
    final valores = [180.0, 315.0, 0.0, 260.0, 410.0, 225.0, 135.0];
    final hoje = DateTime(_agora.year, _agora.month, _agora.day);
    return ResumoGanhos(
      hoje: 135,
      periodo: 1525,
      servicos: 12,
      ticketMedio: 127,
      porDia: [for (var i = 0; i < 7; i++) (hoje.subtract(Duration(days: 6 - i)), valores[i])],
      ano: 9840,
      limiteMei: 81000,
    );
  }
}

/// Overrides para rodar o app inteiro com os dados acima.
List<Override> overridesDemo({required bool pro}) {
  final user = User(id: pro ? _carlos : _ana, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-11-01T00:00:00Z', email: pro ? 'carlos@exemplo.com' : 'ana@exemplo.com');
  final sessao = Session(accessToken: 'demo', tokenType: 'bearer', user: user);
  return [
    sessaoProvider.overrideWith((ref) => Stream.value(sessao)),
    catalogoRepo.overrideWithValue(DemoCatalogo()),
    contaRepo.overrideWithValue(DemoConta(pro)),
    buscaRepo.overrideWithValue(DemoBusca()),
    pedidosRepo.overrideWithValue(DemoPedidos(pro)),
    chatRepo.overrideWithValue(DemoChat()),
    notificacoesRepo.overrideWithValue(DemoNotificacoes(pro)),
    arquivosRepo.overrideWithValue(DemoArquivos()),
    profissionalRepo.overrideWithValue(DemoProfissional()),
  ];
}
