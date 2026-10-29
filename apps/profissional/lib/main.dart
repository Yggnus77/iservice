import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iservice_core/iservice_core.dart';

import 'rotas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await ConfigIService.iniciar();
  runApp(ProviderScope(
    overrides: [appProvider.overrideWithValue(AppIService.profissional)],
    child: const AppProfissional(),
  ));
}

class AppProfissional extends ConsumerWidget {
  const AppProfissional({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letraGrande = ref.watch(meuPerfilProvider.select((p) => p.value?.letraGrande ?? false));
    return MaterialApp.router(
      title: 'iService Profissional',
      debugShowCheckedModeBanner: false,
      theme: temaIService(AppIService.profissional, letraGrande: letraGrande),
      darkTheme: temaIService(AppIService.profissional, brilho: Brightness.dark, letraGrande: letraGrande),
      routerConfig: ref.watch(rotasProvider),
      builder: (_, filho) => VigiaRecuperacaoSenha(child: filho ?? const SizedBox.shrink()),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
