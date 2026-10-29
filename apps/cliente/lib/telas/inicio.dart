import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Início: local, busca, pedido em andamento, categorias e "Top da sua região".
class TelaInicio extends ConsumerWidget {
  const TelaInicio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider).value;
    final local = ref.watch(localBuscaProvider);
    final profissoes = ref.watch(profissoesProvider);
    final andamento = ref.watch(pedidosClienteProvider('andamento')).value ?? const [];
    final top = ref.watch(topRegiaoProvider(null));
    final naoLidas = ref.watch(naoLidasProvider);
    final t = Theme.of(context).textTheme;
    final c = context.cores;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(topRegiaoProvider);
          ref.invalidate(pedidosClienteProvider);
          await ref.read(topRegiaoProvider(null).future);
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: Cores.fundoMarca(alinhamento: Alignment.topCenter),
              padding: EdgeInsets.fromLTRB(Medidas.margemTela, MediaQuery.paddingOf(context).top + 12, 8, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/enderecos'),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Olá, ${primeiroNome(perfil?.nome ?? '')}', style: t.labelMedium?.copyWith(color: Colors.white70)),
                        Row(children: [
                          const Icon(Symbols.location_on_rounded, fill: 1, size: 18, color: Cores.laranja),
                          const SizedBox(width: 4),
                          Flexible(child: Text(local.descricao, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(color: Colors.white))),
                          const Icon(Symbols.expand_more_rounded, color: Colors.white),
                        ]),
                      ]),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notificações',
                    onPressed: () => context.push('/notificacoes'),
                    icon: Badge(isLabelVisible: naoLidas > 0, label: Text('$naoLidas'), child: const Icon(Symbols.notifications_rounded, color: Colors.white)),
                  ),
                ]),
                const SizedBox(height: 18),
                Text('Do que você precisa hoje?', style: t.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(Medidas.raioControle),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Medidas.raioControle),
                      onTap: () => context.push('/busca'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        child: Row(children: [
                          Icon(Symbols.search_rounded, color: c.textoSuave),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Buscar profissão ou serviço', style: t.bodyMedium?.copyWith(color: c.textoSuave))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (andamento.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
                child: _CartaoAndamento(pedido: andamento.first),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 12, 8, 0),
              child: TituloSecao(titulo: 'Categorias', acao: 'Ver todas', aoTocarAcao: () => context.go('/explorar')),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 112,
              child: profissoes.when(
                loading: () => const Carregando(),
                error: (e, _) => Center(child: Text(ErroIService.de(e).mensagem)),
                data: (l) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: l.length,
                  itemBuilder: (_, i) => SizedBox(
                    width: 86,
                    child: BotaoCategoria(profissao: l[i], aoTocar: () => context.push('/profissao/${l[i].id}')),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 12, 8, 0),
              child: TituloSecao(
                icone: const Icon(Symbols.emoji_events_rounded, fill: 1, color: Cores.laranja),
                titulo: (top.value?.firstOrNull?.faseLancamento ?? false) ? 'Profissionais da sua região' : 'Top da sua região',
                acao: 'Ranking',
                aoTocarAcao: () => context.push('/ranking'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 196,
              child: top.when(
                loading: () => const Carregando(),
                error: (e, _) => Center(child: Text(ErroIService.de(e).mensagem)),
                data: (l) => l.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
                        child: Card(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text('Estamos chegando à sua região. Em breve, profissionais perto de você.', style: t.bodySmall, textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
                        itemCount: l.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _CartaoRanking(p: l[i], posicao: i),
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Medidas.margemTela),
              child: _Banner(aoTocar: () => context.go('/explorar')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CartaoAndamento extends StatelessWidget {
  const _CartaoAndamento({required this.pedido});
  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Card(
      color: c.acaoSuave,
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: () => context.push('/pedido/${pedido.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Avatar(nome: pedido.outraParteNome ?? '', url: pedido.outraParteFoto, tamanho: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pedido em andamento', style: t.labelMedium?.copyWith(color: c.acaoTexto)),
                Text(pedido.outraParteNome ?? '', style: t.titleSmall),
                const SizedBox(height: 4),
                EtiquetaStatus(status: pedido.status),
              ]),
            ),
            Icon(Symbols.chevron_right_rounded, color: c.acaoTexto),
          ]),
        ),
      ),
    );
  }
}

class _CartaoRanking extends ConsumerWidget {
  const _CartaoRanking({required this.p, required this.posicao});
  final ProfissionalResumo p;
  final int posicao;

  static const _medalhas = [Color(0xFFFFC531), Color(0xFFB8C2D1), Color(0xFFD98C4A)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final profissao = p.profissaoId == null ? null : ref.watch(profissaoPorIdProvider(p.profissaoId!));
    return SizedBox(
      width: 148,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(Medidas.raioCartao),
          onTap: () => context.push('/profissional/${p.id}?profissao=${p.profissaoId ?? ''}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Avatar(nome: p.nome, url: p.fotoUrl, tamanho: 72, online: true),
                if (!p.faseLancamento)
                  Positioned(
                    left: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: posicao < 3 ? _medalhas[posicao] : context.cores.superficieSuave,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${posicao + 1}º', style: t.labelSmall?.copyWith(color: Cores.azulEscuro)),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(p.nome, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              Text(profissao?.nome ?? '', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              NotaCompacta(nota: p.notaMedia, total: p.totalAvaliacoes, tamanho: 13),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.aoTocar});
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: Cores.laranjaSuave,
      borderRadius: BorderRadius.circular(Medidas.raioCartao),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Serviços rápidos e confiáveis perto de você!', style: t.titleMedium?.copyWith(color: Cores.azulEscuro)),
                const SizedBox(height: 4),
                Text('Profissionais com documento conferido.', style: t.bodySmall?.copyWith(color: Cores.textoSuave)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(Medidas.raioPilula)),
                  child: Text('Solicitar serviço', style: t.labelMedium?.copyWith(color: Cores.azulEscuro)),
                ),
              ]),
            ),
            const Icon(Symbols.handyman_rounded, size: 72, fill: 1, color: Cores.azul),
          ]),
        ),
      ),
    );
  }
}
