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
  return await ref.read(contaRepo).meuPerfil();
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

/// Região do local de busca: a do endereço ou, no GPS, a mais próxima.
final regiaoLocalProvider = FutureProvider<String?>((ref) async {
  final local = ref.watch(localBuscaProvider);
  return local.regiaoId ?? await ref.read(catalogoRepo).regiaoProxima(local.lat, local.lng);
});

/// Faixa comum de preço de uma especialidade numa região, numa forma de cobrança.
final faixaPrecoProvider = FutureProvider.autoDispose.family<FaixaPreco?, (int, String?, Cobranca)>(
    (ref, k) => ref.read(catalogoRepo).faixaPreco(k.$1, k.$2, k.$3));

/// Valor mínimo de uma especialidade numa região, numa forma de cobrança (o profissional não cobra menos).
final precoMinimoProvider = FutureProvider.autoDispose.family<double?, (int, String?, Cobranca)>(
    (ref, k) => ref.read(catalogoRepo).precoMinimo(k.$1, k.$2, k.$3));

/// Acréscimo fora do horário comercial para (preço, momento do serviço).
final pagamentosDoPedidoProvider = StreamProvider.autoDispose.family<List<PagamentoPedido>, String>(
    (ref, pedidoId) => ref.read(pedidosRepo).pagamentos(pedidoId));
final deslocamentoPrevistoProvider = FutureProvider.autoDispose.family<double, (String, int)>(
    (ref, k) => ref.read(catalogoRepo).deslocamentoPrevisto(k.$1, k.$2));
final taxaForaHorarioProvider = FutureProvider.autoDispose.family<double, (double?, DateTime)>(
    (ref, k) => ref.read(catalogoRepo).taxaForaHorario(k.$1, k.$2));

/// Pede permissão e lê o GPS uma vez. Devolve null se o usuário negar, se o GPS
/// não responder em 20 s ou se o navegador falhar (no Safari do iPhone, a consulta
/// de permissão pode não existir ou dar erro; aí pedimos a posição direto, que já
/// mostra o aviso de permissão).
Future<Position?> lerLocalizacaoAtual() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    LocationPermission? p;
    try {
      p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    } on Object {
      p = null;
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
  } on Object {
    return null;
  }
}

final notificacoesProvider = StreamProvider<List<Notificacao>>((ref) {
  if (ref.watch(usuarioIdProvider) == null) return const Stream.empty();
  return ref.read(notificacoesRepo).todas();
});

final naoLidasProvider = Provider<int>((ref) => (ref.watch(notificacoesProvider).value ?? const []).where((n) => !n.lida).length);

final profissionalRepo = Provider((ref) => ProfissionalRepo(supabase));
