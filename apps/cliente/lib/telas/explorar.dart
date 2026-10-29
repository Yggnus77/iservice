import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Todas as profissões do lançamento em grade.
class TelaExplorar extends ConsumerWidget {
  const TelaExplorar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profissoes = ref.watch(profissoesProvider);
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Explorar')),
      body: profissoes.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(profissoesProvider)),
        data: (l) => CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 12),
            sliver: SliverToBoxAdapter(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: c.textoSuave),
                onPressed: () => context.push('/busca'),
                icon: const Icon(Symbols.search_rounded),
                label: const Text('Buscar profissão ou serviço'),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisExtent: 118),
              itemCount: l.length,
              itemBuilder: (_, i) => BotaoCategoria(profissao: l[i], aoTocar: () => context.push('/profissao/${l[i].id}')),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(Medidas.margemTela),
            sliver: SliverToBoxAdapter(
              child: Card(
                color: c.superficieSuave,
                child: ListTile(
                  leading: Icon(Symbols.info_rounded, color: c.acaoTexto),
                  title: Text('${l.length} profissões em Brasília e no Entorno.', style: t.bodyMedium),
                  subtitle: const Text('Não achou a sua? Conte pra gente pelo Perfil, em Ajuda.'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
