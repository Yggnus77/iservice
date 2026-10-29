import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Profissionais de uma profissão perto do cliente.
/// Ordem padrão: mais bem avaliados primeiro (com rodízio justo para os novos).
class TelaListaProfissionais extends ConsumerStatefulWidget {
  const TelaListaProfissionais({super.key, required this.profissaoId, this.especialidadeId});
  final String profissaoId;
  final int? especialidadeId;

  @override
  ConsumerState<TelaListaProfissionais> createState() => _TelaListaProfissionaisState();
}

class _TelaListaProfissionaisState extends ConsumerState<TelaListaProfissionais> {
  late int? _esp = widget.especialidadeId;
  bool _porDistancia = false;
  // Cada nova busca gira o rodízio dos profissionais novos.
  int _rodizio = DateTime.now().millisecondsSinceEpoch ~/ 60000;

  FiltroBusca get _filtro => FiltroBusca(profissaoId: widget.profissaoId, especialidadeId: _esp, porDistancia: _porDistancia, rodizio: _rodizio);

  @override
  Widget build(BuildContext context) {
    final profissao = ref.watch(profissaoPorIdProvider(widget.profissaoId));
    final lista = ref.watch(buscaProvider(_filtro));
    final local = ref.watch(localBuscaProvider);
    final c = context.cores;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(profissao?.nome ?? ''),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 8),
            child: Row(children: [
              Icon(Symbols.location_on_rounded, size: 16, color: c.textoSuave),
              const SizedBox(width: 4),
              Expanded(child: Text('Perto de ${local.descricao}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _rodizio++);
          await ref.read(buscaProvider(_filtro).future);
        },
        child: CustomScrollView(slivers: [
          if (profissao != null && profissao.especialidades.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: const Text('Todas'), selected: _esp == null, onSelected: (_) => setState(() => _esp = null)),
                  ),
                  for (final e in profissao.especialidades)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(e.nome), selected: _esp == e.id, onSelected: (s) => setState(() => _esp = s ? e.id : null)),
                    ),
                ]),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Symbols.star_rounded), label: Text('Mais bem avaliados')),
                  ButtonSegment(value: true, icon: Icon(Symbols.near_me_rounded), label: Text('Mais perto')),
                ],
                selected: {_porDistancia},
                onSelectionChanged: (s) => setState(() => _porDistancia = s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          ...lista.when(
            loading: () => [const SliverFillRemaining(child: Carregando())],
            error: (e, _) => [SliverFillRemaining(child: ErroNaTela(erro: e, aoTentar: () => ref.invalidate(buscaProvider(_filtro))))],
            data: (l) => l.isEmpty
                ? [
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EstadoVazio(
                        icone: Symbols.person_search_rounded,
                        titulo: 'Ninguém disponível agora',
                        texto: 'Todos os profissionais dessa área estão atendendo ou fora do seu raio. Tente de novo em alguns minutos.',
                      ),
                    ),
                  ]
                : [
                    if (l.first.faseLancamento && !_porDistancia)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 8),
                          child: Text('Fase de lançamento: todos os profissionais aparecem em rodízio, com a mesma visibilidade.', style: t.bodySmall),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24),
                      sliver: SliverList.separated(
                        itemCount: l.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => CartaoProfissional(
                          p: l[i],
                          aoTocar: () => context.push('/profissional/${l[i].id}?profissao=${widget.profissaoId}'),
                        ),
                      ),
                    ),
                  ],
          ),
        ]),
      ),
    );
  }
}
