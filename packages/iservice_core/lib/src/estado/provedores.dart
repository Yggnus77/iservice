import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../dados/modelos.dart';
import '../dados/profissional_repo.dart';
import '../dados/repositorios.dart';

/// Qual app está rodando. Cada app sobrescreve no ProviderScope.
final appProvider = Provider<AppIService>((ref) => throw UnimplementedError('Defina appProvider no ProviderScope.'));

final catalogoRepo = Provider((ref) => CatalogoRepo(supabase));
final contaRepo = Provider((ref) => ContaRepo(supabase));
final buscaRepo = Provider((ref) => BuscaRepo(supabase));
final pedidosRepo = Provider((ref) => PedidosRepo(supabase));
final chatRepo = Provider((ref) => ChatRepo(supabase));
final notificacoesRepo = Provider((ref) => NotificacoesRepo(supabase));
final arquivosRepo = Provider((ref) => ArquivosRepo(supabase));

/// Muda a cada login/logout.
final sessaoProvider = StreamProvider<Session?>((ref) async* {
  yield supabase.auth.currentSession;
  await for (final e in supabase.auth.onAuthStateChange) {
    yield e.session;
  }
});

final usuarioIdProvider = Provider<String?>((ref) => ref.watch(sessaoProvider).value?.user.id);

/// Perfil completo do usuário logado. Use ref.invalidate(meuPerfilProvider) depois de salvar algo.
final meuPerfilProvider = FutureProvider<MeuPerfil?>((ref) async {
  final uid = ref.watch(usuarioIdProvider);
  if (uid == null) return null;
  return ref.read(contaRepo).meuPerfil();
});

final profissoesProvider = FutureProvider<List<Profissao>>((ref) => ref.read(catalogoRepo).profissoes());
final regioesProvider = FutureProvider<List<Regiao>>((ref) => ref.read(catalogoRepo).regioes());
final certificacoesSugeridasProvider = FutureProvider((ref) => ref.read(catalogoRepo).certificacoesSugeridas());
final configProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.read(catalogoRepo).config());

final profissaoPorIdProvider = Provider.family<Profissao?, String>((ref, id) {
  final lista = ref.watch(profissoesProvider).value ?? const [];
  for (final p in lista) {
    if (p.id == id) return p;
  }
  return null;
});

/// Ponto de referência para buscas: o endereço principal do usuário.
/// O GPS só é usado quando ele pede "usar minha localização".
class Local {
  const Local(this.lat, this.lng, this.descricao, {this.enderecoId, this.regiaoId});
  final double lat;
  final double lng;
  final String descricao;
  final int? enderecoId;
  final String? regiaoId;
}

/// Centro do Plano Piloto, usado só antes de o usuário ter endereço.
const localPadrao = Local(-15.7939, -47.8828, 'Brasília');

final localEscolhidoProvider = NotifierProvider<LocalEscolhido, Local?>(LocalEscolhido.new);

class LocalEscolhido extends Notifier<Local?> {
  @override
  Local? build() => null;

  void escolher(Local? l) => state = l;
}

final localBuscaProvider = Provider<Local>((ref) {
  final escolhido = ref.watch(localEscolhidoProvider);
  if (escolhido != null) return escolhido;
  final e = ref.watch(meuPerfilProvider).value?.enderecoPrincipal;
  if (e == null) return localPadrao;
  return Local(e.lat, e.lng, e.linha1, enderecoId: e.id, regiaoId: e.regiaoId);
});

/// Pede permissão e lê o GPS uma vez. Devolve null se o usuário negar.
Future<Position?> lerLocalizacaoAtual() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
  return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
}

final notificacoesProvider = StreamProvider<List<Notificacao>>((ref) {
  if (ref.watch(usuarioIdProvider) == null) return const Stream.empty();
  return ref.read(notificacoesRepo).todas();
});

final naoLidasProvider = Provider<int>((ref) => (ref.watch(notificacoesProvider).value ?? const []).where((n) => !n.lida).length);

final profissionalRepo = Provider((ref) => ProfissionalRepo(supabase));
