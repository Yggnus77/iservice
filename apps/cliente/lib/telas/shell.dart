import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Barra inferior fixa: Início, Explorar, Pedidos, Favoritos e Perfil.
class ShellCliente extends StatelessWidget {
  const ShellCliente({super.key, required this.nav});
  final StatefulNavigationShell nav;

  static const _abas = [
    (Symbols.home_rounded, 'Início'),
    (Symbols.explore_rounded, 'Explorar'),
    (Symbols.receipt_long_rounded, 'Pedidos'),
    (Symbols.favorite_rounded, 'Favoritos'),
    (Symbols.person_rounded, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: VigiaExclusaoConta(child: nav),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color!))),
          child: NavigationBar(
            selectedIndex: nav.currentIndex,
            onDestinationSelected: (i) => nav.goBranch(i, initialLocation: i == nav.currentIndex),
            destinations: [
              for (final (icone, rotulo) in _abas)
                NavigationDestination(icon: Icon(icone), selectedIcon: Icon(icone, fill: 1), label: rotulo),
            ],
          ),
        ),
      );
}
