import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'modelos.dart';
import 'repositorios.dart';

/// O que o profissional marcou: profissões, especialidades e preços.
class MinhasProfissoes {
  const MinhasProfissoes({required this.profissoes, required this.especialidades});

  /// id da profissão -> é a principal?
  final Map<String, bool> profissoes;

  /// id da especialidade -> preço (null = ainda sem preço)
  final Map<int, double?> especialidades;
}

class DocumentoEnviado {
  const DocumentoEnviado({required this.tipo, required this.status, this.observacao});
  final String tipo;
  final String status;
  final String? observacao;
}

class ProfissionalRepo {
  const ProfissionalRepo(this._db);
  final SupabaseClient _db;

  String get _uid => _db.auth.currentUser!.id;

  Future<T> _t<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ErroIService.de(e);
    }
  }

  Future<void> ativar() => _t(() => _db.rpc('ativar_profissional'));

  Future<List<String>> pendencias() => _t(() async {
        final r = await _db.rpc('pendencias_profissional', params: {'p_id': _uid});
        return r == null ? const [] : List<String>.from(r as List);
      });

  Future<void> definirArea({required double lat, required double lng, required double raioKm, String? regiaoId}) =>
      _t(() => _db.rpc('definir_area_atendimento', params: {'p_lat': lat, 'p_lng': lng, 'p_raio_km': raioKm, 'p_regiao_id': regiaoId}));

  /// Devolve as pendências; vazio = foi para análise.
  Future<List<String>> enviarCadastro() => _t(() async {
        final r = await _db.rpc('enviar_cadastro_profissional') as Map<String, dynamic>;
        return List<String>.from(r['pendencias'] as List);
      });

  Future<void> definirDisponivel(bool v) => _t(() => _db.rpc('definir_disponivel', params: {'p_disponivel': v}));

  Future<void> salvarSobre({String? bio, int? anosExperiencia}) =>
      _t(() => _db.from('profissionais').update({'bio': bio, 'anos_experiencia': anosExperiencia}).eq('id', _uid));

  Future<MinhasProfissoes> minhasProfissoes() => _t(() async {
        final p = await _db.from('profissional_profissoes').select('profissao_id, principal').eq('profissional_id', _uid);
        final e = await _db.from('profissional_especialidades').select('especialidade_id, preco').eq('profissional_id', _uid);
        return MinhasProfissoes(
          profissoes: {for (final l in p) l['profissao_id'] as String: l['principal'] as bool},
          especialidades: {for (final l in e) l['especialidade_id'] as int: (l['preco'] as num?)?.toDouble()},
        );
      });

  Future<void> marcarProfissao(String profissaoId, bool marcar, {bool principal = false}) => _t(() async {
        if (marcar) {
          await _db.from('profissional_profissoes').insert({'profissional_id': _uid, 'profissao_id': profissaoId, 'principal': principal});
        } else {
          // Tira também as especialidades daquela profissão.
          final esps = await _db.from('especialidades').select('id').eq('profissao_id', profissaoId);
          final ids = [for (final e in esps) e['id']];
          if (ids.isNotEmpty) await _db.from('profissional_especialidades').delete().eq('profissional_id', _uid).inFilter('especialidade_id', ids);
          await _db.from('profissional_profissoes').delete().eq('profissional_id', _uid).eq('profissao_id', profissaoId);
        }
      });

  Future<void> marcarEspecialidade(int especialidadeId, bool marcar) => _t(() async {
        if (marcar) {
          await _db.from('profissional_especialidades').upsert({'profissional_id': _uid, 'especialidade_id': especialidadeId});
        } else {
          await _db.from('profissional_especialidades').delete().eq('profissional_id', _uid).eq('especialidade_id', especialidadeId);
        }
      });

  Future<void> definirPreco(int especialidadeId, double? preco) => _t(
      () => _db.from('profissional_especialidades').update({'preco': preco}).eq('profissional_id', _uid).eq('especialidade_id', especialidadeId));

  Future<int> sugerirEspecialidade(String profissaoId, String nome) =>
      _t(() async => ((await _db.rpc('sugerir_especialidade', params: {'p_profissao': profissaoId, 'p_nome': nome})) as num).toInt());

  /// Especialidades sugeridas pelo próprio profissional (ainda não aprovadas para todos).
  Future<List<Especialidade>> minhasSugestoes() => _t(() async {
        final l = await _db.from('especialidades').select('id, profissao_id, nome').eq('criada_por', _uid);
        return [for (final e in l) Especialidade.fromJson(e)];
      });

  Future<List<DocumentoEnviado>> documentos() => _t(() async {
        final l = await _db.from('documentos').select('tipo, status, observacao').eq('profissional_id', _uid).order('criado_em');
        return [for (final d in l) DocumentoEnviado(tipo: d['tipo'], status: d['status'], observacao: d['observacao'])];
      });

  Future<void> enviarDocumento(String tipo, Uint8List bytes, {String extensao = 'jpg', String contentType = 'image/jpeg'}) => _t(() async {
        final caminho = '$_uid/$tipo-${DateTime.now().millisecondsSinceEpoch}.$extensao';
        await _db.storage.from('documentos').uploadBinary(caminho, bytes, fileOptions: FileOptions(contentType: contentType));
        await _db.from('documentos').insert({'profissional_id': _uid, 'tipo': tipo, 'arquivo_path': caminho});
      });

  Future<List<Map<String, dynamic>>> certificacoes() =>
      _t(() async => List<Map<String, dynamic>>.from(await _db.from('certificacoes').select('id, nome, profissao_id, status').eq('profissional_id', _uid)));

  Future<void> adicionarCertificacao({required String nome, String? profissaoId, Uint8List? arquivo, String extensao = 'jpg'}) => _t(() async {
        String? caminho;
        if (arquivo != null) {
          caminho = '$_uid/certificado-${DateTime.now().millisecondsSinceEpoch}.$extensao';
          // O bucket só aceita imagem ou PDF, então o tipo vai explícito.
          final tipo = extensao.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg';
          await _db.storage.from('documentos').uploadBinary(caminho, arquivo, fileOptions: FileOptions(contentType: tipo));
        }
        await _db.from('certificacoes').insert({'profissional_id': _uid, 'nome': nome, 'profissao_id': profissaoId, 'arquivo_path': caminho});
      });

  Future<void> removerCertificacao(int id) => _t(() => _db.from('certificacoes').delete().eq('id', id));

  Future<List<ItemPortfolio>> portfolio() => _t(() async {
        final l = await _db.from('portfolio').select('id, descricao, antes_path, depois_path').eq('profissional_id', _uid).order('ordem');
        return [for (final p in l) ItemPortfolio.fromJson(p)];
      });

  Future<void> adicionarPortfolio({required Uint8List depois, Uint8List? antes, String? descricao}) => _t(() async {
        final agora = DateTime.now().millisecondsSinceEpoch;
        final d = '$_uid/$agora-depois.jpg';
        await _db.storage.from('portfolio').uploadBinary(d, depois, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        String? a;
        if (antes != null) {
          a = '$_uid/$agora-antes.jpg';
          await _db.storage.from('portfolio').uploadBinary(a, antes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        }
        await _db.from('portfolio').insert({'profissional_id': _uid, 'depois_path': d, 'antes_path': a, 'descricao': descricao});
      });

  Future<void> removerPortfolio(int id) => _t(() => _db.from('portfolio').delete().eq('id', id));

  Future<ResumoGanhos> ganhos({DateTime? inicio, DateTime? fim}) => _t(() async {
        final r = await _db.rpc('resumo_ganhos', params: {
          if (inicio != null) 'p_inicio': inicio.toIso8601String().substring(0, 10),
          if (fim != null) 'p_fim': fim.toIso8601String().substring(0, 10),
        });
        return ResumoGanhos.fromJson(r as Map<String, dynamic>);
      });

  Future<void> responderAvaliacao(String pedidoId, String resposta) =>
      _t(() => _db.from('avaliacoes').update({'resposta': resposta}).eq('pedido_id', pedidoId));
}
