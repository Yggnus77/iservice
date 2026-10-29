import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Barra inferior do Profissional: Início, Solicitações, Agenda, Ganhos e Perfil.
class ShellProfissional extends ConsumerWidget {
  const ShellProfissional({super.key, required this.nav});
  final StatefulNavigationShell nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aguardando = (ref.watch(pedidosProProvider('andamento')).value ?? const []).where((p) => p.status.valor == 'solicitado').length;
    final abas = [
      (Symbols.dashboard_rounded, 'Início', 0),
      (Symbols.notifications_active_rounded, 'Solicitações', aguardando),
      (Symbols.calendar_month_rounded, 'Agenda', 0),
      (Symbols.payments_rounded, 'Ganhos', 0),
      (Symbols.person_rounded, 'Perfil', 0),
    ];
    return Scaffold(
      body: VigiaExclusaoConta(child: nav),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color!))),
        child: NavigationBar(
          selectedIndex: nav.currentIndex,
          onDestinationSelected: (i) => nav.goBranch(i, initialLocation: i == nav.currentIndex),
          destinations: [
            for (final (icone, rotulo, n) in abas)
              NavigationDestination(
                icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icone)),
                selectedIcon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icone, fill: 1)),
                label: rotulo,
              ),
          ],
        ),
      ),
    );
  }
}
