import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

class TelaFavoritos extends ConsumerWidget {
  const TelaFavoritos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(favoritosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: lista.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(favoritosProvider)),
        data: (l) => l.isEmpty
            ? EstadoVazio(
                icone: Symbols.favorite_rounded,
                titulo: 'Nenhum favorito ainda',
                texto: 'Toque no coração no perfil de um profissional para encontrá-lo rápido aqui.',
                acao: 'Explorar',
                aoTocarAcao: () => context.go('/explorar'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(favoritosProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(Medidas.margemTela),
                  itemCount: l.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => CartaoProfissional(p: l[i], aoTocar: () => context.push('/profissional/${l[i].id}')),
                ),
              ),
      ),
    );
  }
}
