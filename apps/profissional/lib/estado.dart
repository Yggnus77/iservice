import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iservice_core/iservice_core.dart';

/// O que falta no cadastro (vem do banco). Vazio = completo.
final pendenciasProvider = FutureProvider<List<String>>((ref) {
  final perfil = ref.watch(meuPerfilProvider).value;
  if (perfil == null) return const [];
  return ref.read(profissionalRepo).pendencias();
});

/// Recarrega listas quando algum pedido do profissional muda (pedido novo, cancelamento...).
final _mudancas = StreamProvider<void>((ref) {
  if (ref.watch(usuarioIdProvider) == null) return const Stream.empty();
  return ref.read(pedidosRepo).mudancas('profissional');
});

final pedidosProProvider = FutureProvider.family<List<Pedido>, String>((ref, grupo) {
  ref.watch(_mudancas);
  return ref.read(pedidosRepo).meus(papel: 'profissional', grupo: grupo);
});

final minhasProfissoesProvider = FutureProvider((ref) {
  ref.watch(usuarioIdProvider);
  return ref.read(profissionalRepo).minhasProfissoes();
});

final ganhosProvider = FutureProvider.family<ResumoGanhos, String>((ref, periodo) {
  ref.watch(_mudancas);
  final hoje = DateTime.now();
  final inicio = switch (periodo) {
    'semana' => hoje.subtract(Duration(days: hoje.weekday - 1)),
    'ano' => DateTime(hoje.year),
    _ => DateTime(hoje.year, hoje.month),
  };
  return ref.read(profissionalRepo).ganhos(inicio: inicio, fim: hoje);
});

/// Raio de atendimento escolhido no cadastro (passo 2).
final raioAtendimentoProvider = NotifierProvider<_Raio, double>(_Raio.new);

class _Raio extends Notifier<double> {
  @override
  double build() => ref.read(meuPerfilProvider).value?.profissional?.areaRaioKm ?? 15;
  void definir(double v) => state = v;
}

/// Primeiro passo do cadastro que ainda falta, a partir das pendências do banco.
int passoPendente(List<String> pend) {
  if (pend.any(const {'nome', 'nascimento', 'cpf', 'telefone'}.contains)) return 1;
  if (pend.any(const {'endereco', 'area_atendimento'}.contains)) return 2;
  if (pend.contains('profissao')) return 4;
  if (pend.any(const {'documento', 'selfie', 'antecedentes'}.contains)) return 5;
  return 6;
}

const nomesPendencias = {
  'foto': 'foto de perfil',
  'nome': 'nome completo',
  'nascimento': 'data de nascimento (18+)',
  'cpf': 'CPF',
  'telefone': 'celular',
  'endereco': 'endereço',
  'area_atendimento': 'área de atendimento',
  'profissao': 'profissão',
  'especialidades_e_precos': 'especialidades com preço',
  'documento': 'foto do documento',
  'selfie': 'selfie com o documento',
  'antecedentes': 'certidão de antecedentes',
};
