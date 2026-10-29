import 'dart:math' as math;

// Modelos dos dados que vêm do backend (tabelas e funções do Supabase).

double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
DateTime? _data(Object? v) => v == null ? null : DateTime.parse(v as String);
List<String> _textos(Object? v) => v == null ? const [] : List<String>.from(v as List);

class Regiao {
  const Regiao({required this.id, required this.nome, required this.uf, required this.faixaPreco});
  final String id;
  final String nome;
  final String uf;
  final int faixaPreco;

  String get nomeComUf => uf == 'DF' ? nome : '$nome ($uf)';

  factory Regiao.fromJson(Map<String, dynamic> j) =>
      Regiao(id: j['id'], nome: j['nome'], uf: j['uf'], faixaPreco: j['faixa_preco']);
}

class Especialidade {
  const Especialidade({required this.id, required this.profissaoId, required this.nome, this.preco});
  final int id;
  final String profissaoId;
  final String nome;

  /// Preço definido pelo profissional (só no perfil dele).
  final double? preco;

  factory Especialidade.fromJson(Map<String, dynamic> j, {String? profissaoId}) => Especialidade(
        id: j['id'],
        profissaoId: j['profissao_id'] ?? profissaoId ?? '',
        nome: j['nome'],
        preco: _dn(j['preco']),
      );
}

class Profissao {
  const Profissao({
    required this.id,
    required this.nome,
    required this.icone,
    required this.corInicio,
    required this.corFim,
    required this.exigeAntecedentes,
    required this.palavrasChave,
    this.especialidades = const [],
  });
  final String id;
  final String nome;
  final String icone;
  final String corInicio;
  final String corFim;
  final bool exigeAntecedentes;
  final List<String> palavrasChave;
  final List<Especialidade> especialidades;

  factory Profissao.fromJson(Map<String, dynamic> j) => Profissao(
        id: j['id'],
        nome: j['nome'],
        icone: j['icone'],
        corInicio: j['cor_inicio'],
        corFim: j['cor_fim'],
        exigeAntecedentes: j['exige_antecedentes'] ?? false,
        palavrasChave: _textos(j['palavras_chave']),
        especialidades: [
          for (final e in (j['especialidades'] as List? ?? const [])) Especialidade.fromJson(e, profissaoId: j['id']),
        ],
      );
}

class CertificacaoSugerida {
  const CertificacaoSugerida({required this.profissaoId, required this.nome, required this.obrigatoria});
  final String profissaoId;
  final String nome;
  final bool obrigatoria;

  factory CertificacaoSugerida.fromJson(Map<String, dynamic> j) =>
      CertificacaoSugerida(profissaoId: j['profissao_id'], nome: j['nome'], obrigatoria: j['obrigatoria']);
}

class Endereco {
  const Endereco({
    required this.id,
    required this.rotulo,
    required this.logradouro,
    required this.cidade,
    required this.uf,
    required this.lat,
    required this.lng,
    required this.principal,
    this.regiaoId,
    this.bloco,
    this.numero,
    this.complemento,
    this.referencia,
    this.cep,
  });
  final int id;
  final String rotulo;
  final String? regiaoId;
  final String logradouro;
  final String? bloco;
  final String? numero;
  final String? complemento;
  final String? referencia;
  final String? cep;
  final String cidade;
  final String uf;
  final double lat;
  final double lng;
  final bool principal;

  /// "SQS 308, Bloco C, Apto 101"
  String get linha1 => [logradouro, bloco, numero, complemento].where((s) => s != null && s.isNotEmpty).join(', ');

  factory Endereco.fromJson(Map<String, dynamic> j) => Endereco(
        id: j['id'],
        rotulo: j['rotulo'] ?? 'Casa',
        regiaoId: j['regiao_id'],
        logradouro: j['logradouro'],
        bloco: j['bloco'],
        numero: j['numero'],
        complemento: j['complemento'],
        referencia: j['referencia'],
        cep: j['cep'],
        cidade: j['cidade'] ?? 'Brasília',
        uf: j['uf'] ?? 'DF',
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        principal: j['principal'] ?? false,
      );
}

enum StatusCadastro { rascunho, emAnalise, aprovado, recusado, suspenso }

StatusCadastro _statusCadastro(String? s) => switch (s) {
      'em_analise' => StatusCadastro.emAnalise,
      'aprovado' => StatusCadastro.aprovado,
      'recusado' => StatusCadastro.recusado,
      'suspenso' => StatusCadastro.suspenso,
      _ => StatusCadastro.rascunho,
    };

/// Dados do próprio profissional (vindos de meu_perfil()).
class MeuCadastroProfissional {
  const MeuCadastroProfissional({
    required this.status,
    required this.disponivel,
    required this.verificado,
    required this.areaRaioKm,
    required this.notaMedia,
    required this.totalAvaliacoes,
    required this.servicosConcluidos,
    required this.pedidosRecebidos,
    required this.pedidosAceitos,
    this.motivoStatus,
    this.bio,
    this.anosExperiencia,
    this.areaLat,
    this.areaLng,
    this.regiaoId,
  });
  final StatusCadastro status;
  final String? motivoStatus;
  final bool disponivel;
  final bool verificado;
  final String? bio;
  final int? anosExperiencia;
  final double? areaLat;
  final double? areaLng;
  final double areaRaioKm;
  final String? regiaoId;
  final double notaMedia;
  final int totalAvaliacoes;
  final int servicosConcluidos;
  final int pedidosRecebidos;
  final int pedidosAceitos;

  /// Percentual de pedidos aceitos (confiabilidade).
  double get taxaAceite => pedidosRecebidos == 0 ? 1 : pedidosAceitos / pedidosRecebidos;

  factory MeuCadastroProfissional.fromJson(Map<String, dynamic> j) => MeuCadastroProfissional(
        status: _statusCadastro(j['status']),
        motivoStatus: j['motivo_status'],
        disponivel: j['disponivel'] ?? false,
        verificado: j['verificado'] ?? false,
        bio: j['bio'],
        anosExperiencia: j['anos_experiencia'],
        areaLat: _dn(j['area_lat']),
        areaLng: _dn(j['area_lng']),
        areaRaioKm: _d(j['area_raio_km']),
        regiaoId: j['regiao_id'],
        notaMedia: _d(j['nota_media']),
        totalAvaliacoes: j['total_avaliacoes'] ?? 0,
        servicosConcluidos: j['servicos_concluidos'] ?? 0,
        pedidosRecebidos: j['pedidos_recebidos'] ?? 0,
        pedidosAceitos: j['pedidos_aceitos'] ?? 0,
      );
}

/// O usuário logado com tudo que é dele.
class MeuPerfil {
  const MeuPerfil({
    required this.id,
    required this.nome,
    required this.eCliente,
    required this.eProfissional,
    required this.eAdmin,
    required this.letraGrande,
    required this.enderecos,
    required this.pontos,
    this.email,
    this.telefone,
    this.cpf,
    this.nascimento,
    this.fotoUrl,
    this.codigoIndicacao,
    this.profissional,
    this.exclusaoSolicitadaEm,
    this.telefoneVerificado = false,
  });
  final String id;
  final String nome;
  final String? email;

  /// Quando o usuário pediu para excluir a conta (null = conta ativa).
  final DateTime? exclusaoSolicitadaEm;
  final String? telefone;

  /// Celular confirmado por SMS.
  final bool telefoneVerificado;
  final String? cpf;
  final DateTime? nascimento;
  final String? fotoUrl;
  final bool eCliente;
  final bool eProfissional;
  final bool eAdmin;
  final bool letraGrande;
  final String? codigoIndicacao;
  final List<Endereco> enderecos;
  final MeuCadastroProfissional? profissional;
  final int pontos;

  Endereco? get enderecoPrincipal =>
      enderecos.isEmpty ? null : enderecos.firstWhere((e) => e.principal, orElse: () => enderecos.first);

  factory MeuPerfil.fromJson(Map<String, dynamic> j) {
    final p = j['perfil'] as Map<String, dynamic>;
    return MeuPerfil(
      id: p['id'],
      nome: p['nome'] ?? '',
      email: p['email'],
      telefone: p['telefone'],
      telefoneVerificado: p['telefone_verificado'] ?? false,
      cpf: p['cpf'],
      nascimento: p['nascimento'] == null ? null : DateTime.parse(p['nascimento']),
      fotoUrl: p['foto_url'],
      eCliente: p['e_cliente'] ?? false,
      eProfissional: p['e_profissional'] ?? false,
      eAdmin: p['e_admin'] ?? false,
      letraGrande: p['letra_grande'] ?? false,
      codigoIndicacao: p['codigo_indicacao'],
      enderecos: [for (final e in (j['enderecos'] as List? ?? const [])) Endereco.fromJson(e)],
      profissional: j['profissional'] == null ? null : MeuCadastroProfissional.fromJson(j['profissional']),
      pontos: (j['pontos'] as num?)?.toInt() ?? 0,
      exclusaoSolicitadaEm: p['exclusao_solicitada_em'] == null ? null : DateTime.parse(p['exclusao_solicitada_em']),
    );
  }
}

/// Linha da busca de profissionais e do ranking.
class ProfissionalResumo {
  const ProfissionalResumo({
    required this.id,
    required this.nome,
    required this.notaMedia,
    required this.totalAvaliacoes,
    required this.servicosConcluidos,
    required this.distanciaKm,
    required this.posicao,
    this.fotoUrl,
    this.profissaoId,
    this.anosExperiencia,
    this.verificado = false,
    this.novo = false,
    this.precoAPartir,
    this.especialidades = const [],
    this.favorito = false,
    this.faseLancamento = false,
  });
  final String id;
  final String nome;
  final String? fotoUrl;
  final String? profissaoId;
  final double notaMedia;
  final int totalAvaliacoes;
  final int servicosConcluidos;
  final int? anosExperiencia;
  final bool verificado;
  final double distanciaKm;
  final bool novo;
  final double? precoAPartir;
  final List<String> especialidades;
  final bool favorito;
  final bool faseLancamento;
  final int posicao;

  factory ProfissionalResumo.fromJson(Map<String, dynamic> j) => ProfissionalResumo(
        id: j['profissional_id'],
        nome: j['nome'],
        fotoUrl: j['foto_url'],
        profissaoId: j['profissao_id'],
        notaMedia: _d(j['nota_media']),
        totalAvaliacoes: j['total_avaliacoes'] ?? 0,
        servicosConcluidos: j['servicos_concluidos'] ?? 0,
        anosExperiencia: j['anos_experiencia'],
        verificado: j['verificado'] ?? false,
        distanciaKm: _d(j['distancia_km']),
        novo: j['novo'] ?? false,
        precoAPartir: _dn(j['preco_a_partir']),
        especialidades: _textos(j['especialidades']),
        favorito: j['favorito'] ?? false,
        faseLancamento: j['fase_lancamento'] ?? false,
        posicao: j['posicao'] ?? 0,
      );
}

class ProfissaoDoProfissional {
  const ProfissaoDoProfissional({required this.id, required this.nome, required this.icone, required this.especialidades});
  final String id;
  final String nome;
  final String icone;
  final List<Especialidade> especialidades;
}

class Avaliacao {
  const Avaliacao({
    required this.nota,
    required this.criadaEm,
    required this.clienteNome,
    this.comentario,
    this.fotos = const [],
    this.resposta,
    this.clienteFoto,
    this.pedidoId,
  });
  final String? pedidoId;
  final int nota;
  final String? comentario;
  final List<String> fotos;
  final String? resposta;
  final DateTime criadaEm;
  final String clienteNome;
  final String? clienteFoto;

  factory Avaliacao.fromJson(Map<String, dynamic> j) => Avaliacao(
        pedidoId: j['pedido_id'],
        nota: j['nota'],
        comentario: j['comentario'],
        fotos: _textos(j['fotos']),
        resposta: j['resposta'],
        criadaEm: DateTime.parse(j['criada_em']),
        clienteNome: j['cliente_nome'] ?? '',
        clienteFoto: j['cliente_foto'],
      );
}

class ItemPortfolio {
  const ItemPortfolio({required this.id, required this.depoisPath, this.antesPath, this.descricao});
  final int id;
  final String? descricao;
  final String? antesPath;
  final String depoisPath;

  factory ItemPortfolio.fromJson(Map<String, dynamic> j) =>
      ItemPortfolio(id: j['id'], descricao: j['descricao'], antesPath: j['antes_path'], depoisPath: j['depois_path']);
}

/// Perfil público completo (perfil_profissional()).
class PerfilProfissional {
  const PerfilProfissional({
    required this.id,
    required this.nome,
    required this.verificado,
    required this.disponivel,
    required this.notaMedia,
    required this.totalAvaliacoes,
    required this.servicosConcluidos,
    required this.novo,
    required this.favorito,
    required this.profissoes,
    required this.certificacoes,
    required this.portfolio,
    required this.avaliacoes,
    required this.distribuicaoNotas,
    this.fotoUrl,
    this.bio,
    this.anosExperiencia,
    this.regiao,
    this.membroDesde,
  });
  final String id;
  final String nome;
  final String? fotoUrl;
  final String? bio;
  final int? anosExperiencia;
  final bool verificado;
  final bool disponivel;
  final double notaMedia;
  final int totalAvaliacoes;
  final int servicosConcluidos;
  final bool novo;
  final String? regiao;
  final DateTime? membroDesde;
  final bool favorito;
  final List<ProfissaoDoProfissional> profissoes;
  final List<String> certificacoes;
  final List<ItemPortfolio> portfolio;
  final List<Avaliacao> avaliacoes;
  final Map<int, int> distribuicaoNotas;

  factory PerfilProfissional.fromJson(Map<String, dynamic> j) => PerfilProfissional(
        id: j['id'],
        nome: j['nome'],
        fotoUrl: j['foto_url'],
        bio: j['bio'],
        anosExperiencia: j['anos_experiencia'],
        verificado: j['verificado'] ?? false,
        disponivel: j['disponivel'] ?? false,
        notaMedia: _d(j['nota_media']),
        totalAvaliacoes: j['total_avaliacoes'] ?? 0,
        servicosConcluidos: j['servicos_concluidos'] ?? 0,
        novo: j['novo'] ?? false,
        regiao: j['regiao'],
        membroDesde: _data(j['membro_desde']),
        favorito: j['favorito'] ?? false,
        profissoes: [
          for (final p in (j['profissoes'] as List? ?? const []))
            ProfissaoDoProfissional(
              id: p['id'],
              nome: p['nome'],
              icone: p['icone'],
              especialidades: [for (final e in (p['especialidades'] as List)) Especialidade.fromJson(e, profissaoId: p['id'])],
            ),
        ],
        certificacoes: [for (final c in (j['certificacoes'] as List? ?? const [])) c['nome'] as String],
        portfolio: [for (final p in (j['portfolio'] as List? ?? const [])) ItemPortfolio.fromJson(p)],
        avaliacoes: [for (final a in (j['avaliacoes_recentes'] as List? ?? const [])) Avaliacao.fromJson(a)],
        distribuicaoNotas: {
          for (final e in ((j['distribuicao_notas'] as Map?) ?? const {}).entries) int.parse(e.key): (e.value as num).toInt(),
        },
      );
}

class FaixaPreco {
  const FaixaPreco({required this.minimo, required this.maximo, required this.estimada});
  final double minimo;
  final double maximo;
  final bool estimada;

  /// Aviso quando o profissional digita um preço muito fora do comum.
  String? aviso(double? valor) {
    if (valor == null || valor <= 0) return null;
    if (valor < minimo * .7) return 'Bem abaixo do comum na região. Manter ou revisar?';
    if (valor > maximo * 1.3) return 'Bem acima do comum na região. Manter ou revisar?';
    return null;
  }

  factory FaixaPreco.fromJson(Map<String, dynamic> j) =>
      FaixaPreco(minimo: _d(j['minimo']), maximo: _d(j['maximo']), estimada: j['estimada'] ?? true);
}

enum QuandoPedido {
  agora('agora', 'Agora'),
  hoje('hoje', 'Hoje'),
  combinado('combinado', 'Horário combinado');

  const QuandoPedido(this.valor, this.rotulo);
  final String valor;
  final String rotulo;

  static QuandoPedido de(String s) => values.firstWhere((v) => v.valor == s);
}

enum StatusPedido {
  solicitado('solicitado', 'Aguardando resposta'),
  aceito('aceito', 'Aceito'),
  aCaminho('a_caminho', 'A caminho'),
  emAtendimento('em_atendimento', 'Em atendimento'),
  concluido('concluido', 'Concluído'),
  recusado('recusado', 'Recusado'),
  expirado('expirado', 'Sem resposta'),
  cancelado('cancelado', 'Cancelado');

  const StatusPedido(this.valor, this.rotulo);
  final String valor;
  final String rotulo;

  bool get emAndamento => this == solicitado || this == aceito || this == aCaminho || this == emAtendimento;
  bool get encerradoSemServico => this == recusado || this == expirado || this == cancelado;

  static StatusPedido de(String s) => values.firstWhere((v) => v.valor == s);
}

/// Pedido como aparece nas listas (meus_pedidos()) e no acompanhamento.
class Pedido {
  const Pedido({
    required this.id,
    required this.codigo,
    required this.status,
    required this.quando,
    required this.profissaoId,
    required this.descricao,
    required this.enderecoTexto,
    required this.taxaUrgencia,
    required this.responderAte,
    required this.criadoEm,
    this.janela,
    this.combinadoPara,
    this.especialidade,
    this.distanciaKm,
    this.precoInformado,
    this.valorCobrado,
    this.concluidoEm,
    this.outraParteId,
    this.outraParteNome,
    this.outraParteFoto,
    this.avaliado = false,
    this.naoLidas = 0,
  });
  final String id;
  final String codigo;
  final StatusPedido status;
  final QuandoPedido quando;
  final String? janela;
  final DateTime? combinadoPara;
  final String profissaoId;
  final String? especialidade;
  final String descricao;
  final String enderecoTexto;
  final double? distanciaKm;
  final double? precoInformado;
  final double taxaUrgencia;
  final double? valorCobrado;
  final DateTime responderAte;
  final DateTime criadoEm;
  final DateTime? concluidoEm;
  final String? outraParteId;
  final String? outraParteNome;
  final String? outraParteFoto;
  final bool avaliado;
  final int naoLidas;

  /// Tempo que falta para o profissional responder (zero se já passou).
  Duration get tempoParaResponder {
    final r = responderAte.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  String get quandoTexto => switch (quando) {
        QuandoPedido.agora => 'Agora',
        QuandoPedido.hoje => 'Hoje${janela == null ? '' : ', $janela'}',
        QuandoPedido.combinado => combinadoPara == null ? 'Combinado' : _diaHora(combinadoPara!),
      };

  static String _diaHora(DateTime d) {
    final l = d.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(l.day)}/${dois(l.month)} às ${dois(l.hour)}:${dois(l.minute)}';
  }

  /// Linha vinda de meus_pedidos().
  factory Pedido.fromLista(Map<String, dynamic> j) => Pedido(
        id: j['id'],
        codigo: j['codigo'],
        status: StatusPedido.de(j['status']),
        quando: QuandoPedido.de(j['quando']),
        janela: j['janela'],
        combinadoPara: _data(j['combinado_para']),
        profissaoId: j['profissao_id'],
        especialidade: j['especialidade'],
        descricao: j['descricao'] ?? '',
        enderecoTexto: j['endereco_texto'] ?? '',
        distanciaKm: _dn(j['distancia_km']),
        precoInformado: _dn(j['preco_informado']),
        taxaUrgencia: _d(j['taxa_urgencia']),
        valorCobrado: _dn(j['valor_cobrado']),
        responderAte: DateTime.parse(j['responder_ate']),
        criadoEm: DateTime.parse(j['criado_em']),
        concluidoEm: _data(j['concluido_em']),
        outraParteId: j['outra_parte_id'],
        outraParteNome: j['outra_parte_nome'],
        outraParteFoto: j['outra_parte_foto'],
        avaliado: j['avaliado'] ?? false,
        naoLidas: j['nao_lidas'] ?? 0,
      );

  /// Linha crua da tabela pedidos (tempo real). Mantém os dados da outra parte de [base].
  factory Pedido.daTabela(Map<String, dynamic> j, {Pedido? base}) => Pedido(
        id: j['id'],
        codigo: j['codigo'],
        status: StatusPedido.de(j['status']),
        quando: QuandoPedido.de(j['quando']),
        janela: j['janela'],
        combinadoPara: _data(j['combinado_para']),
        profissaoId: j['profissao_id'],
        especialidade: base?.especialidade,
        descricao: j['descricao'] ?? '',
        enderecoTexto: j['endereco_texto'] ?? '',
        distanciaKm: _dn(j['distancia_km']),
        precoInformado: _dn(j['preco_informado']),
        taxaUrgencia: _d(j['taxa_urgencia']),
        valorCobrado: _dn(j['valor_cobrado']),
        responderAte: DateTime.parse(j['responder_ate']),
        criadoEm: DateTime.parse(j['criado_em']),
        concluidoEm: _data(j['concluido_em']),
        outraParteId: base?.outraParteId,
        outraParteNome: base?.outraParteNome,
        outraParteFoto: base?.outraParteFoto,
        avaliado: base?.avaliado ?? false,
        naoLidas: base?.naoLidas ?? 0,
      );
}

class Mensagem {
  const Mensagem({required this.id, required this.pedidoId, required this.autorId, required this.texto, required this.criadaEm, this.lidaEm});
  final int id;
  final String pedidoId;
  final String autorId;
  final String texto;
  final DateTime criadaEm;
  final DateTime? lidaEm;

  factory Mensagem.fromJson(Map<String, dynamic> j) => Mensagem(
        id: j['id'],
        pedidoId: j['pedido_id'],
        autorId: j['autor_id'],
        texto: j['texto'],
        criadaEm: DateTime.parse(j['criada_em']),
        lidaEm: _data(j['lida_em']),
      );
}

/// Onde está o profissional a caminho e para onde ele vai.
class PosicaoAoVivo {
  const PosicaoAoVivo({
    required this.lat,
    required this.lng,
    required this.destinoLat,
    required this.destinoLng,
    required this.atualizadoEm,
    this.precisaoM,
  });
  final double lat;
  final double lng;
  final double destinoLat;
  final double destinoLng;
  final double? precisaoM;
  final DateTime atualizadoEm;

  factory PosicaoAoVivo.fromJson(Map<String, dynamic> j) => PosicaoAoVivo(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        destinoLat: (j['destino_lat'] as num).toDouble(),
        destinoLng: (j['destino_lng'] as num).toDouble(),
        precisaoM: (j['precisao_m'] as num?)?.toDouble(),
        atualizadoEm: DateTime.parse(j['atualizado_em']),
      );

  /// Distância em linha reta até o local do serviço, em km.
  double get distanciaKm {
    const r = 6371.0;
    double rad(double g) => g * math.pi / 180;
    final dLat = rad(destinoLat - lat);
    final dLng = rad(destinoLng - lng);
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat)) * math.cos(rad(destinoLat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  /// Estimativa simples: trajeto ~1,4x a linha reta a 25 km/h, no mínimo 1 minuto.
  int get minutosEstimados => math.max(1, (distanciaKm * 1.4 / 25 * 60).round());
}

class Notificacao {
  const Notificacao({required this.id, required this.tipo, required this.titulo, required this.corpo, required this.lida, required this.criadaEm, this.pedidoId});
  final int id;
  final String tipo;
  final String titulo;
  final String corpo;
  final bool lida;
  final DateTime criadaEm;
  final String? pedidoId;

  factory Notificacao.fromJson(Map<String, dynamic> j) => Notificacao(
        id: j['id'],
        tipo: j['tipo'],
        titulo: j['titulo'],
        corpo: j['corpo'] ?? '',
        lida: j['lida'] ?? false,
        criadaEm: DateTime.parse(j['criada_em']),
        pedidoId: (j['dados'] as Map?)?['pedido_id'],
      );
}

class ResumoGanhos {
  const ResumoGanhos({
    required this.hoje,
    required this.periodo,
    required this.servicos,
    required this.ticketMedio,
    required this.porDia,
    required this.ano,
    required this.limiteMei,
  });
  final double hoje;
  final double periodo;
  final int servicos;
  final double ticketMedio;
  final List<(DateTime, double)> porDia;
  final double ano;
  final double limiteMei;

  factory ResumoGanhos.fromJson(Map<String, dynamic> j) => ResumoGanhos(
        hoje: _d(j['hoje']),
        periodo: _d(j['periodo']),
        servicos: (j['servicos'] as num?)?.toInt() ?? 0,
        ticketMedio: _d(j['ticket_medio']),
        porDia: [for (final d in (j['por_dia'] as List? ?? const [])) (DateTime.parse(d['dia']), _d(d['valor']))],
        ano: _d(j['ano']),
        limiteMei: _d(j['limite_mei']),
      );
}
