import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'estado/provedores.dart';
import 'widgets/componentes.dart';

/// Chaves do Firebase passadas na compilação (config/firebase.json). Sem elas o
/// push fica desligado e o app funciona normalmente (as notificações seguem na tela
/// de Notificações). Cada app tem o seu "app id" no Firebase.
class ConfigFirebase {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _clienteAndroid = String.fromEnvironment('FIREBASE_CLIENTE_ANDROID_APP_ID');
  static const _clienteIos = String.fromEnvironment('FIREBASE_CLIENTE_IOS_APP_ID');
  static const _profissionalAndroid = String.fromEnvironment('FIREBASE_PROFISSIONAL_ANDROID_APP_ID');
  static const _profissionalIos = String.fromEnvironment('FIREBASE_PROFISSIONAL_IOS_APP_ID');

  static FirebaseOptions? opcoes(AppIService app) {
    // Na versão web (links de teste) o push não é usado.
    if (kIsWeb || projectId.isEmpty || senderId.isEmpty) return null;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final appId = switch ((app, ios)) {
      (AppIService.cliente, false) => _clienteAndroid,
      (AppIService.cliente, true) => _clienteIos,
      (AppIService.profissional, false) => _profissionalAndroid,
      (AppIService.profissional, true) => _profissionalIos,
    };
    final apiKey = ios ? _iosApiKey : _androidApiKey;
    if (appId.isEmpty || apiKey.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      iosBundleId: ios ? (app == AppIService.cliente ? 'br.app.iservice.cliente' : 'br.app.iservice.profissional') : null,
    );
  }
}

/// Liga o push enquanto há alguém logado: pede permissão, registra o aparelho no
/// backend e abre o pedido quando a pessoa toca na notificação.
class RegistroPush extends ConsumerStatefulWidget {
  const RegistroPush({super.key, required this.aoAbrirPedido, required this.child});
  final void Function(String pedidoId) aoAbrirPedido;
  final Widget child;

  @override
  ConsumerState<RegistroPush> createState() => _RegistroPushState();
}

class _RegistroPushState extends ConsumerState<RegistroPush> {
  final _assinaturas = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final app = ref.read(appProvider);
    final opcoes = ConfigFirebase.opcoes(app);
    if (opcoes == null) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: opcoes);
      final fcm = FirebaseMessaging.instance;
      final permissao = await fcm.requestPermission();
      if (permissao.authorizationStatus == AuthorizationStatus.denied) return;
      // No iPhone, mostra o aviso mesmo com o app aberto.
      await fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      final plataforma = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      Future<void> registrar(String? token) async {
        if (token == null) return;
        await ref.read(contaRepo).registrarDispositivo(token: token, app: app.name, plataforma: plataforma);
      }

      // Token clássico do FCM (o que a função enviar-push usa). A API nova de
      // "Installation ID" ainda não serve para o envio pela HTTP v1.
      // ignore: deprecated_member_use
      await registrar(await fcm.getToken());
      // ignore: deprecated_member_use
      _assinaturas.add(fcm.onTokenRefresh.listen(registrar));

      // App aberto: mostra um aviso discreto (a lista de Notificações já atualiza sozinha).
      _assinaturas.add(FirebaseMessaging.onMessage.listen((m) {
        final titulo = m.notification?.title;
        if (titulo != null && mounted && defaultTargetPlatform != TargetPlatform.iOS) mostrarMensagem(context, titulo);
      }));
      _assinaturas.add(FirebaseMessaging.onMessageOpenedApp.listen(_abrir));
      final inicial = await fcm.getInitialMessage();
      if (inicial != null) _abrir(inicial);
    } catch (e) {
      debugPrint('Push desligado: $e');
    }
  }

  void _abrir(RemoteMessage m) {
    final pedido = m.data['pedido_id'];
    if (pedido is String && pedido.isNotEmpty && mounted) widget.aoAbrirPedido(pedido);
  }

  @override
  void dispose() {
    for (final a in _assinaturas) {
      a.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Token deste aparelho, para tirar do backend ao sair da conta.
Future<String?> tokenPushAtual() async {
  if (Firebase.apps.isEmpty) return null;
  try {
    // ignore: deprecated_member_use
    return await FirebaseMessaging.instance.getToken();
  } catch (_) {
    return null;
  }
}

/// Sai da conta tirando este aparelho do push (para não receber avisos da conta antiga).
Future<void> sairDaConta(WidgetRef ref) async => ref.read(contaRepo).sair(tokenPush: await tokenPushAtual());
