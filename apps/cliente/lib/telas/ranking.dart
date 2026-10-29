import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Top 10 da região do cliente, geral ou por profissão.
/// A ordem segue a qualidade; o plano do profissional só define o alcance.
class TelaRanking extends ConsumerStatefulWidget {
  const TelaRanking({super.key, this.profissaoId});
  final String? profissaoId;

  @override
  ConsumerState<TelaRanking> createState() => _TelaRankingState();
}

class _TelaRankingState extends ConsumerState<TelaRanking> {
  late String? _profissao = widget.profissaoId;

  @override
  Widget build(BuildContext context) {
    final profissoes = ref.watch(profissoesProvider).value ?? const <Profissao>[];
    final lista = ref.watch(topRegiaoProvider(_profissao));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ranking da região')),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: const Text('Todas'), selected: _profissao == null, onSelected: (_) => setState(() => _profissao = null)),
            ),
            for (final p in profissoes)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(p.nome), selected: _profissao == p.id, onSelected: (_) => setState(() => _profissao = p.id)),
              ),
          ]),
        ),
        Expanded(
          child: lista.when(
            loading: () => const Carregando(),
            error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(topRegiaoProvider(_profissao))),
            data: (l) => l.isEmpty
                ? const EstadoVazio(icone: Symbols.emoji_events_rounded, titulo: 'Ranking em formação', texto: 'Quando houver avaliações suficientes na sua região, os melhores aparecem aqui.')
                : ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 24), children: [
                    Text(
                      l.first.faseLancamento ? 'Fase de lançamento: todos em rodízio, com a mesma visibilidade.' : 'Melhores avaliados até 15 km de você.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    for (final (i, p) in l.indexed) ...[
                      Row(children: [
                        if (!p.faseLancamento)
                          SizedBox(width: 36, child: Text('${i + 1}º', style: t.titleMedium?.copyWith(color: i < 3 ? Cores.laranja : null))),
                        Expanded(
                          child: CartaoProfissional(
                            p: p,
                            profissaoNome: p.profissaoId == null ? null : ref.watch(profissaoPorIdProvider(p.profissaoId!))?.nome,
                            aoTocar: () => context.push('/profissional/${p.id}?profissao=${p.profissaoId ?? ''}'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                    ],
                  ]),
          ),
        ),
      ]),
    );
  }
}
