import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'modelos.dart';

/// Erro já com a mensagem pronta para mostrar ao usuário.
class ErroIService implements Exception {
  const ErroIService(this.mensagem, {this.codigo});
  final String mensagem;
  final String? codigo;

  @override
  String toString() => mensagem;

  /// Converte qualquer erro do Supabase numa mensagem em português.
  static ErroIService de(Object e) {
    if (e is ErroIService) return e;
    if (e is PostgrestException) {
      // As funções do banco mandam a mensagem pronta e o código em "details".
      if (e.code == 'P0001') return ErroIService(e.message, codigo: e.details?.toString());
      if (e.code == '23505') return const ErroIService('Esse dado já está cadastrado em outra conta.', codigo: 'duplicado');
      if (e.code == '23514' && e.message.contains('cpf')) return const ErroIService('CPF inválido.', codigo: 'cpf');
      return const ErroIService('Não foi possível concluir agora. Tente de novo.');
    }
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return const ErroIService('E-mail ou senha incorretos.', codigo: 'login');
      if (m.contains('already registered')) return const ErroIService('Este e-mail já tem conta. Entre com ele.', codigo: 'email_existe');
      if (m.contains('email not confirmed')) return const ErroIService('Confirme seu e-mail pelo link que enviamos.', codigo: 'email_nao_confirmado');
      if (m.contains('password')) return const ErroIService('Senha fraca. Use 8 caracteres com letras e números.', codigo: 'senha');
      return ErroIService(e.message);
    }
    if (e is StorageException) return const ErroIService('Não foi possível enviar o arquivo. Tente de novo.');
    return const ErroIService('Sem conexão. Confira sua internet e tente de novo.');
  }
}

Future<T> _tentar<T>(Future<T> Function() f) async {
  try {
    return await f();
  } catch (e) {
    throw ErroIService.de(e);
  }
}

// ---------------------------------------------------------------------------

class CatalogoRepo {
  const CatalogoRepo(this._db);
  final SupabaseClient _db;

  Future<List<Profissao>> profissoes() => _tentar(() async {
        final linhas = await _db
            .from('profissoes')
            .select('*, especialidades(id, nome, ordem, aprovada)')
            .eq('ativa', true)
            .eq('especialidades.aprovada', true)
            .order('ordem')
            .order('ordem', referencedTable: 'especialidades');
        return [for (final l in linhas) Profissao.fromJson(l)];
      });

  Future<List<Regiao>> regioes() => _tentar(() async {
        final linhas = await _db.from('regioes').select('id, nome, uf, faixa_preco').order('ordem');
        return [for (final l in linhas) Regiao.fromJson(l)];
      });

  Future<List<CertificacaoSugerida>> certificacoesSugeridas() => _tentar(() async {
        final linhas = await _db.from('certificacoes_sugeridas').select();
        return [for (final l in linhas) CertificacaoSugerida.fromJson(l)];
      });

  Future<Map<String, dynamic>> config() => _tentar(() async {
        final linhas = await _db.from('app_config').select('chave, valor');
        return {for (final l in linhas) l['chave'] as String: l['valor']};
      });

  Future<FaixaPreco?> faixaPreco(int especialidadeId, String? regiaoId) => _tentar(() async {
        final r = await _db.rpc('faixa_preco', params: {'p_especialidade': especialidadeId, 'p_regiao': regiaoId});
        final l = r as List;
        return l.isEmpty ? null : FaixaPreco.fromJson(l.first);
      });
}

// ---------------------------------------------------------------------------

class ContaRepo {
  const ContaRepo(this._db);
  final SupabaseClient _db;

  Session? get sessao => _db.auth.currentSession;
  String? get usuarioId => _db.auth.currentUser?.id;
  Stream<AuthState> get mudancas => _db.auth.onAuthStateChange;

  Future<void> entrar(String email, String senha) =>
      _tentar(() => _db.auth.signInWithPassword(email: email.trim(), password: senha));

  /// Cria a conta. [app] decide se nasce também o cadastro de profissional.
  Future<void> criarConta({
    required String email,
    required String senha,
    required String nome,
    required AppIService app,
    String? codigoIndicacao,
  }) =>
      _tentar(() => _db.auth.signUp(
            email: email.trim(),
            password: senha,
            data: {
              'nome': nome.trim(),
              'app': app.name,
              if (codigoIndicacao != null && codigoIndicacao.isNotEmpty) 'indicacao': codigoIndicacao.trim(),
            },
          ));

  Future<void> recuperarSenha(String email) => _tentar(() => _db.auth.resetPasswordForEmail(email.trim()));

  Future<void> sair() => _tentar(() => _db.auth.signOut());

  Future<MeuPerfil?> meuPerfil() => _tentar(() async {
        if (usuarioId == null) return null;
        final r = await _db.rpc('meu_perfil');
        return r == null ? null : MeuPerfil.fromJson(r as Map<String, dynamic>);
      });

  Future<void> salvarDadosPessoais({
    required String nome,
    required DateTime nascimento,
    required String cpf,
    required String telefone,
  }) =>
      _tentar(() => _db.from('perfis').update({
            'nome': nome.trim(),
            'nascimento': nascimento.toIso8601String().substring(0, 10),
            'cpf': cpf,
            'telefone': telefone,
          }).eq('id', usuarioId!));

  Future<void> salvarFoto(String url) => _tentar(() => _db.from('perfis').update({'foto_url': url}).eq('id', usuarioId!));

  Future<void> definirLetraGrande(bool ligado) =>
      _tentar(() => _db.from('perfis').update({'letra_grande': ligado}).eq('id', usuarioId!));

  Future<int> salvarEndereco({
    required String logradouro,
    required double lat,
    required double lng,
    String? regiaoId,
    String? bloco,
    String? numero,
    String? complemento,
    String? referencia,
    String? cep,
    String cidade = 'Brasília',
    String uf = 'DF',
    String rotulo = 'Casa',
    bool principal = true,
    int? id,
  }) =>
      _tentar(() async {
        final r = await _db.rpc('salvar_endereco', params: {
          'p_logradouro': logradouro,
          'p_lat': lat,
          'p_lng': lng,
          'p_regiao_id': regiaoId,
          'p_bloco': bloco,
          'p_numero': numero,
          'p_complemento': complemento,
          'p_referencia': referencia,
          'p_cep': cep,
          'p_cidade': cidade,
          'p_uf': uf,
          'p_rotulo': rotulo,
          'p_principal': principal,
          'p_id': id,
        });
        return (r as num).toInt();
      });

  Future<void> apagarEndereco(int id) => _tentar(() => _db.from('enderecos').delete().eq('id', id));

  /// Devolve a lista do que falta (vazia = cadastro concluído).
  Future<List<String>> concluirCadastroCliente() => _tentar(() async {
        final r = await _db.rpc('concluir_cadastro_cliente') as Map<String, dynamic>;
        return List<String>.from(r['pendencias'] as List);
      });
}

// ---------------------------------------------------------------------------

class BuscaRepo {
  const BuscaRepo(this._db);
  final SupabaseClient _db;

  Future<List<ProfissionalResumo>> buscar({
    required String profissaoId,
    required double lat,
    required double lng,
    int? especialidadeId,
    bool porDistancia = false,
    int rodizio = 0,
  }) =>
      _tentar(() async {
        final r = await _db.rpc('buscar_profissionais', params: {
          'p_profissao': profissaoId,
          'p_lat': lat,
          'p_lng': lng,
          'p_especialidade': especialidadeId,
          'p_ordem': porDistancia ? 'distancia' : 'qualidade',
          'p_rodizio': rodizio,
        });
        return [for (final l in r as List) ProfissionalResumo.fromJson({...l, 'profissao_id': profissaoId})];
      });

  Future<List<ProfissionalResumo>> topRegiao({required double lat, required double lng, String? profissaoId, int limite = 10, int rodizio = 0}) =>
      _tentar(() async {
        final r = await _db.rpc('top_regiao', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_profissao': profissaoId,
          'p_limite': limite,
          'p_rodizio': rodizio,
        });
        return [for (final l in r as List) ProfissionalResumo.fromJson(l)];
      });

  Future<PerfilProfissional?> perfil(String id) => _tentar(() async {
        final r = await _db.rpc('perfil_profissional', params: {'p_id': id});
        return r == null ? null : PerfilProfissional.fromJson(r as Map<String, dynamic>);
      });

  Future<List<ProfissionalResumo>> favoritos() => _tentar(() async {
        final linhas = await _db
            .from('favoritos')
            .select('profissional_id, profissionais(nota_media, total_avaliacoes, servicos_concluidos, verificado, perfis(nome, foto_url))')
            .order('criado_em', ascending: false);
        return [
          for (final (i, l) in linhas.indexed)
            if (l['profissionais'] != null)
              ProfissionalResumo(
                id: l['profissional_id'],
                nome: l['profissionais']['perfis']['nome'],
                fotoUrl: l['profissionais']['perfis']['foto_url'],
                notaMedia: (l['profissionais']['nota_media'] as num).toDouble(),
                totalAvaliacoes: l['profissionais']['total_avaliacoes'],
                servicosConcluidos: l['profissionais']['servicos_concluidos'],
                verificado: l['profissionais']['verificado'],
                distanciaKm: 0,
                favorito: true,
                posicao: i + 1,
              ),
        ];
      });

  Future<void> favoritar(String profissionalId, bool favorito) => _tentar(() async {
        final uid = _db.auth.currentUser!.id;
        if (favorito) {
          await _db.from('favoritos').upsert({'cliente_id': uid, 'profissional_id': profissionalId});
        } else {
          await _db.from('favoritos').delete().eq('cliente_id', uid).eq('profissional_id', profissionalId);
        }
      });
}

// ---------------------------------------------------------------------------

class PedidosRepo {
  const PedidosRepo(this._db);
  final SupabaseClient _db;

  Future<Pedido> criar({
    required String profissionalId,
    required String profissaoId,
    required int enderecoId,
    required QuandoPedido quando,
    int? especialidadeId,
    String descricao = '',
    String? janela,
    DateTime? combinadoPara,
    List<String> fotos = const [],
  }) =>
      _tentar(() async {
        final r = await _db.rpc('criar_pedido', params: {
          'p_profissional': profissionalId,
          'p_profissao': profissaoId,
          'p_endereco_id': enderecoId,
          'p_quando': quando.valor,
          'p_especialidade': especialidadeId,
          'p_descricao': descricao,
          'p_janela': janela,
          'p_combinado_para': combinadoPara?.toUtc().toIso8601String(),
          'p_fotos': fotos,
        });
        return Pedido.daTabela(r as Map<String, dynamic>);
      });

  /// [papel] é 'cliente' ou 'profissional'; [grupo] é 'andamento', 'concluidos', 'cancelados' ou 'todos'.
  Future<List<Pedido>> meus({required String papel, String grupo = 'todos'}) => _tentar(() async {
        final r = await _db.rpc('meus_pedidos', params: {'p_papel': papel, 'p_grupo': grupo});
        return [for (final l in r as List) Pedido.fromLista(l)];
      });

  /// Pedido em tempo real: cada mudança de status chega na hora.
  Stream<Pedido> acompanhar(Pedido base) => _db
      .from('pedidos')
      .stream(primaryKey: ['id'])
      .eq('id', base.id)
      .where((l) => l.isNotEmpty)
      .map((l) => Pedido.daTabela(l.first, base: base));

  /// Avisa quando a lista de pedidos do usuário muda (novo pedido, mudança de status).
  Stream<void> mudancas(String papel) {
    final uid = _db.auth.currentUser!.id;
    return _db
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .eq(papel == 'profissional' ? 'profissional_id' : 'cliente_id', uid)
        .map((_) {});
  }

  Future<Pedido> responder(String pedidoId, {required bool aceitar, String? motivo}) => _tentar(() async {
        final r = await _db.rpc('responder_pedido', params: {'p_pedido': pedidoId, 'p_aceitar': aceitar, 'p_motivo': motivo});
        return Pedido.daTabela(r as Map<String, dynamic>);
      });

  Future<Pedido> avancar(String pedidoId, StatusPedido status, {double? valor, String? formaPagamento}) => _tentar(() async {
        final r = await _db.rpc('avancar_pedido', params: {
          'p_pedido': pedidoId,
          'p_status': status.valor,
          'p_valor': valor,
          'p_forma_pagamento': formaPagamento,
        });
        return Pedido.daTabela(r as Map<String, dynamic>);
      });

  Future<Pedido> cancelar(String pedidoId, {String? motivo}) => _tentar(() async {
        final r = await _db.rpc('cancelar_pedido', params: {'p_pedido': pedidoId, 'p_motivo': motivo});
        return Pedido.daTabela(r as Map<String, dynamic>);
      });

  Future<void> avaliar(String pedidoId, int nota, {String? comentario, List<String> fotos = const []}) =>
      _tentar(() => _db.rpc('avaliar_pedido', params: {'p_pedido': pedidoId, 'p_nota': nota, 'p_comentario': comentario, 'p_fotos': fotos}));

  Future<void> emergencia({String? pedidoId, double? lat, double? lng}) =>
      _tentar(() => _db.rpc('acionar_emergencia', params: {'p_pedido': pedidoId, 'p_lat': lat, 'p_lng': lng}));

  /// Devolve o token do link de acompanhamento ao vivo.
  Future<String> compartilhar(String pedidoId) =>
      _tentar(() async => (await _db.rpc('compartilhar_acompanhamento', params: {'p_pedido': pedidoId})) as String);

  Future<void> reclamar(String pedidoId, {required String motivo, required String descricao, List<String> fotos = const []}) =>
      _tentar(() => _db.rpc('abrir_reclamacao', params: {'p_pedido': pedidoId, 'p_motivo': motivo, 'p_descricao': descricao, 'p_fotos': fotos}));
}

// ---------------------------------------------------------------------------

class ChatRepo {
  const ChatRepo(this._db);
  final SupabaseClient _db;

  Stream<List<Mensagem>> mensagens(String pedidoId) => _db
      .from('mensagens')
      .stream(primaryKey: ['id'])
      .eq('pedido_id', pedidoId)
      .order('criada_em')
      .map((l) => [for (final m in l) Mensagem.fromJson(m)]);

  Future<void> enviar(String pedidoId, String texto) => _tentar(
      () => _db.from('mensagens').insert({'pedido_id': pedidoId, 'autor_id': _db.auth.currentUser!.id, 'texto': texto.trim()}));

  Future<void> marcarLidas(String pedidoId) => _tentar(() => _db.rpc('marcar_mensagens_lidas', params: {'p_pedido': pedidoId}));
}

// ---------------------------------------------------------------------------

class NotificacoesRepo {
  const NotificacoesRepo(this._db);
  final SupabaseClient _db;

  Stream<List<Notificacao>> todas() => _db
      .from('notificacoes')
      .stream(primaryKey: ['id'])
      .eq('usuario_id', _db.auth.currentUser!.id)
      .order('criada_em', ascending: false)
      .limit(100)
      .map((l) => [for (final n in l) Notificacao.fromJson(n)]);

  Future<void> marcarLidas() =>
      _tentar(() => _db.from('notificacoes').update({'lida': true}).eq('usuario_id', _db.auth.currentUser!.id).eq('lida', false));
}

// ---------------------------------------------------------------------------

/// Envio de fotos e documentos. A pasta é sempre o id do usuário (regra do Storage).
class ArquivosRepo {
  const ArquivosRepo(this._db);
  final SupabaseClient _db;

  /// Envia e devolve o caminho dentro do bucket.
  Future<String> enviar({required String bucket, required String nome, required Uint8List bytes, String tipo = 'image/jpeg'}) =>
      _tentar(() async {
        final caminho = '${_db.auth.currentUser!.id}/$nome';
        await _db.storage.from(bucket).uploadBinary(caminho, bytes, fileOptions: FileOptions(upsert: true, contentType: tipo));
        return caminho;
      });

  String urlPublica(String bucket, String caminho) => _db.storage.from(bucket).getPublicUrl(caminho);

  Future<String> urlTemporaria(String bucket, String caminho) =>
      _tentar(() => _db.storage.from(bucket).createSignedUrl(caminho, 3600));
}
