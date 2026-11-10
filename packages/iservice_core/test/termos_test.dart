import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iservice_core/iservice_core.dart';

void main() {
  testWidgets('tela de aceite pede a marcação antes de continuar', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [meuPerfilProvider.overrideWith((ref) async => null)],
      child: MaterialApp(theme: temaIService(AppIService.cliente), home: const TelaAceitarTermos()),
    ));
    await tester.pump();
    expect(find.text('Antes de continuar'), findsOneWidget);
    expect(find.text('Termos de Uso'), findsOneWidget);
    expect(find.text('Política de Privacidade'), findsOneWidget);

    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pump();
    expect(find.textContaining('marque que leu e aceita'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
  });
}
