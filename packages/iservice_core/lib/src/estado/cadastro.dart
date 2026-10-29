import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'provedores.dart';

/// Dados do cadastro preenchidos antes de a conta existir (passos 1 e 2).
/// Se o Supabase pedir confirmação de e-mail, ficam guardados no aparelho e
/// são gravados no primeiro login.
class RascunhoCadastro {
  const RascunhoCadastro({
    this.nome = '',
    this.nascimento,
    this.cpf = '',
    this.telefone = '',
    this.regiaoId,
    this.cidade = 'Brasília',
    this.uf = 'DF',
    this.logradouro = '',
    this.bloco,
    this.numero,
    this.complemento,
    this.referencia,
    this.cep,
    this.lat,
    this.lng,
    this.indicacao,
  });

  final String nome;
  final DateTime? nascimento;
  final String cpf;
  final String telefone;
  final String? regiaoId;
  final String cidade;
  final String uf;
  final String logradouro;
  final String? bloco;
  final String? numero;
  final String? complemento;
  final String? referencia;
  final String? cep;
  final double? lat;
  final double? lng;
  final String? indicacao;

  bool get temDadosPessoais => nome.isNotEmpty && nascimento != null && cpf.length == 11 && telefone.isNotEmpty;
  bool get temEndereco => logradouro.isNotEmpty && lat != null && lng != null;

  RascunhoCadastro copiar({
    String? nome,
    DateTime? nascimento,
    String? cpf,
    String? telefone,
    String? regiaoId,
    String? cidade,
    String? uf,
    String? logradouro,
    String? bloco,
    String? numero,
    String? complemento,
    String? referencia,
    String? cep,
    double? lat,
    double? lng,
    String? indicacao,
  }) =>
      RascunhoCadastro(
        nome: nome ?? this.nome,
        nascimento: nascimento ?? this.nascimento,
        cpf: cpf ?? this.cpf,
        telefone: telefone ?? this.telefone,
        regiaoId: regiaoId ?? this.regiaoId,
        cidade: cidade ?? this.cidade,
        uf: uf ?? this.uf,
        logradouro: logradouro ?? this.logradouro,
        bloco: bloco ?? this.bloco,
        numero: numero ?? this.numero,
        complemento: complemento ?? this.complemento,
        referencia: referencia ?? this.referencia,
        cep: cep ?? this.cep,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        indicacao: indicacao ?? this.indicacao,
      );

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'nascimento': nascimento?.toIso8601String(),
        'cpf': cpf,
        'telefone': telefone,
        'regiaoId': regiaoId,
        'cidade': cidade,
        'uf': uf,
        'logradouro': logradouro,
        'bloco': bloco,
        'numero': numero,
        'complemento': complemento,
        'referencia': referencia,
        'cep': cep,
        'lat': lat,
        'lng': lng,
        'indicacao': indicacao,
      };

  factory RascunhoCadastro.fromJson(Map<String, dynamic> j) => RascunhoCadastro(
        nome: j['nome'] ?? '',
        nascimento: j['nascimento'] == null ? null : DateTime.parse(j['nascimento']),
        cpf: j['cpf'] ?? '',
        telefone: j['telefone'] ?? '',
        regiaoId: j['regiaoId'],
        cidade: j['cidade'] ?? 'Brasília',
        uf: j['uf'] ?? 'DF',
        logradouro: j['logradouro'] ?? '',
        bloco: j['bloco'],
        numero: j['numero'],
        complemento: j['complemento'],
        referencia: j['referencia'],
        cep: j['cep'],
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        indicacao: j['indicacao'],
      );
}

const _chave = 'iservice.rascunho_cadastro';

final rascunhoCadastroProvider = NotifierProvider<RascunhoNotifier, RascunhoCadastro>(RascunhoNotifier.new);

class RascunhoNotifier extends Notifier<RascunhoCadastro> {
  @override
  RascunhoCadastro build() => const RascunhoCadastro();

  void atualizar(RascunhoCadastro r) => state = r;

  Future<void> guardarNoAparelho() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, jsonEncode(state.toJson()));
  }

  /// Cria a conta e grava os passos 1 e 2. Devolve false se o e-mail precisa
  /// ser confirmado antes (os dados ficam guardados para o primeiro login).
  Future<bool> criarConta({required String email, required String senha, required AppIService app}) async {
    final conta = ref.read(contaRepo);
    await conta.criarConta(email: email, senha: senha, nome: state.nome, app: app, codigoIndicacao: state.indicacao);
    if (conta.sessao == null) {
      await guardarNoAparelho();
      return false;
    }
    await gravar();
    return true;
  }

  /// Grava no backend o que estiver no rascunho.
  Future<void> gravar() async {
    final conta = ref.read(contaRepo);
    final r = state;
    if (r.temDadosPessoais) {
      await conta.salvarDadosPessoais(nome: r.nome, nascimento: r.nascimento!, cpf: r.cpf, telefone: r.telefone);
    }
    if (r.temEndereco) {
      await conta.salvarEndereco(
        logradouro: r.logradouro,
        lat: r.lat!,
        lng: r.lng!,
        regiaoId: r.regiaoId,
        bloco: r.bloco,
        numero: r.numero,
        complemento: r.complemento,
        referencia: r.referencia,
        cep: r.cep,
        cidade: r.cidade,
        uf: r.uf,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
    ref.invalidate(meuPerfilProvider);
  }

  /// No primeiro login depois de confirmar o e-mail, aplica o rascunho guardado.
  Future<void> aplicarGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_chave);
    if (s == null) return;
    state = RascunhoCadastro.fromJson(jsonDecode(s));
    await gravar();
  }
}
