import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'push.dart';

/// Liga o registro de travamentos (Firebase Crashlytics) nos apps de celular.
///
/// Na versão web, sem as chaves do Firebase ou em modo de desenvolvimento,
/// não faz nada. Nunca impede o app de abrir.
Future<void> iniciarMonitorFalhas(AppIService app) async {
  final opcoes = ConfigFirebase.opcoes(app);
  if (opcoes == null) return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: opcoes);
    final crash = FirebaseCrashlytics.instance;
    await crash.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = crash.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (erro, pilha) {
      unawaited(crash.recordError(erro, pilha, fatal: true));
      return true;
    };
  } on Object catch (e) {
    debugPrint('Monitor de falhas desligado: $e');
  }
}
