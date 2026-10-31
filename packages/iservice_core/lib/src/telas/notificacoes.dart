import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../util/formatos.dart';
import '../widgets/componentes.dart';

IconData _icone(String tipo) => switch (tipo) {
      'pedido_novo' => Symbols.notifications_active_rounded,
      'pedido_aceito' || 'pedido_a_caminho' || 'pedido_em_atendimento' => Symbols.directions_run_rounded,
      'pedido_concluido' => Symbols.task_alt_rounded,
      'pedido_recusado' || 'pedido_expirado' || 'pedido_cancelado' => Symbols.event_busy_rounded,
      'mensagem' => Symbols.chat_rounded,
      'avaliacao_nova' => Symbols.star_rounded,
      'cadastro_aprovado' => Symbols.verified_rounded,
      'cadastro_recusado' || 'documento_recusado' => Symbols.error_rounded,
      'cadastro_recebido' => Symbols.hourglass_top_rounded,
      'boas_vindas' => Symbols.waving_hand_rounded,
      'reclamacao_aberta' || 'reclamacao_recebida' || 'garantia' => Symbols.shield_rounded,
      'conta_suspensa' => Symbols.block_rounded,
      'conta_reativada' => Symbols.check_circle_rounded,
      _ => Symbols.notifications_rounded,
    };

class TelaNotificacoes extends ConsumerStatefulWidget {
  const TelaNotificacoes({super.key, required this.aoAbrirPedido});
  final void Function(String pedidoId) aoAbrirPedido;

  @override
  ConsumerState<TelaNotificacoes> createState() => _TelaNotificacoesState();
}

class _TelaNotificacoesState extends ConsumerState<TelaNotificacoes> {
  @override
  void dispose() {
    // Ao sair da tela, tudo que foi visto conta como lido.
    ref.read(notificacoesRepo).marcarLidas();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(notificacoesProvider);
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: lista.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e),
        data: (l) => l.isEmpty
            ? const EstadoVazio(icone: Symbols.notifications_rounded, titulo: 'Tudo em dia', texto: 'Avisos de pedidos, mensagens e avaliações aparecem aqui.')
            : ListView.separated(
                itemCount: l.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (_, i) {
                  final Notificacao n = l[i];
                  return ListTile(
                    tileColor: n.lida ? null : c.acaoSuave.withValues(alpha: .5),
                    leading: CircleAvatar(backgroundColor: c.acaoSuave, child: Icon(_icone(n.tipo), color: c.acaoTexto)),
                    title: Text(n.titulo, style: t.titleSmall),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (n.corpo.isNotEmpty) Text(n.corpo),
                      Text(quandoFoi(n.criadaEm), style: t.labelSmall?.copyWith(color: c.textoSuave)),
                    ]),
                    onTap: n.pedidoId == null ? null : () => widget.aoAbrirPedido(n.pedidoId!),
                  );
                },
              ),
      ),
    );
  }
}
