import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iservice_core/iservice_core.dart';

/// Recarrega as listas de pedidos sempre que algum pedido do cliente muda.
final _mudancasPedidos = StreamProvider<void>((ref) {
  if (ref.watch(usuarioIdProvider) == null) return const Stream.empty();
  return ref.read(pedidosRepo).mudancas('cliente');
});

final pedidosClienteProvider = FutureProvider.family<List<Pedido>, String>((ref, grupo) {
  ref.watch(_mudancasPedidos);
  return ref.read(pedidosRepo).meus(papel: 'cliente', grupo: grupo);
});

final topRegiaoProvider = FutureProvider.family<List<ProfissionalResumo>, String?>((ref, profissaoId) {
  final local = ref.watch(localBuscaProvider);
  return ref.read(buscaRepo).topRegiao(lat: local.lat, lng: local.lng, profissaoId: profissaoId, rodizio: DateTime.now().hour);
});

final favoritosProvider = FutureProvider((ref) {
  ref.watch(usuarioIdProvider);
  return ref.read(buscaRepo).favoritos();
});

final perfilProfissionalProvider = FutureProvider.autoDispose.family<PerfilProfissional?, String>((ref, id) => ref.read(buscaRepo).perfil(id));

/// Parâmetros da busca de uma profissão.
class FiltroBusca {
  const FiltroBusca({required this.profissaoId, this.especialidadeId, this.porDistancia = false, this.rodizio = 0});
  final String profissaoId;
  final int? especialidadeId;
  final bool porDistancia;
  final int rodizio;

  @override
  bool operator ==(Object other) =>
      other is FiltroBusca && other.profissaoId == profissaoId && other.especialidadeId == especialidadeId && other.porDistancia == porDistancia && other.rodizio == rodizio;

  @override
  int get hashCode => Object.hash(profissaoId, especialidadeId, porDistancia, rodizio);
}

final buscaProvider = FutureProvider.autoDispose.family<List<ProfissionalResumo>, FiltroBusca>((ref, f) {
  final local = ref.watch(localBuscaProvider);
  return ref.read(buscaRepo).buscar(
        profissaoId: f.profissaoId,
        lat: local.lat,
        lng: local.lng,
        especialidadeId: f.especialidadeId,
        porDistancia: f.porDistancia,
        rodizio: f.rodizio,
      );
});
