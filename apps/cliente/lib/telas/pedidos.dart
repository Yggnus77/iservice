import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Pedidos do cliente: em andamento, concluídos e cancelados.
class TelaPedidos extends StatelessWidget {
  const TelaPedidos({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Pedidos'),
            bottom: const TabBar(tabs: [Tab(text: 'Em andamento'), Tab(text: 'Concluídos'), Tab(text: 'Cancelados')]),
          ),
          body: const TabBarView(children: [_Lista('andamento'), _Lista('concluidos'), _Lista('cancelados')]),
        ),
      );
}

class _Lista extends ConsumerWidget {
  const _Lista(this.grupo);
  final String grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pedidosClienteProvider(grupo));
    return lista.when(
      loading: () => const Carregando(),
      error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(pedidosClienteProvider(grupo))),
      data: (l) => l.isEmpty
          ? EstadoVazio(
              icone: Symbols.receipt_long_rounded,
              titulo: switch (grupo) { 'andamento' => 'Nenhum pedido em andamento', 'concluidos' => 'Nenhum serviço concluído ainda', _ => 'Nada por aqui' },
              texto: grupo == 'andamento' ? 'Encontre um profissional e faça seu pedido.' : null,
              acao: grupo == 'andamento' ? 'Explorar profissionais' : null,
              aoTocarAcao: () => context.go('/explorar'),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(pedidosClienteProvider(grupo).future),
              child: ListView.separated(
                padding: const EdgeInsets.all(Medidas.margemTela),
                itemCount: l.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _CartaoPedido(p: l[i]),
              ),
            ),
    );
  }
}

class _CartaoPedido extends ConsumerWidget {
  const _CartaoPedido({required this.p});
  final Pedido p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: () => context.push('/pedido/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto, tamanho: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.outraParteNome ?? '', style: t.titleSmall),
                  Text([profissao?.nome, p.especialidade].whereType<String>().join(' · '), style: t.bodySmall),
                ]),
              ),
              EtiquetaStatus(status: p.status),
            ]),
            const Divider(height: 20),
            Row(children: [
              Text(quandoFoi(p.criadoEm), style: t.bodySmall),
              const Spacer(),
              if (p.valorCobrado != null) Text(reais(p.valorCobrado), style: t.titleSmall),
              if (p.status == StatusPedido.concluido && !p.avaliado)
                TextButton(onPressed: () => context.push('/pedido/${p.id}/avaliar'), child: const Text('Avaliar')),
            ]),
          ]),
        ),
      ),
    );
  }
}
