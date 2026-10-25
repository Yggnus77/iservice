import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';
import 'painel.dart';

/// Atendimentos aceitos: o que está em curso, o de hoje e os horários combinados (até 7 dias).
class TelaAgenda extends ConsumerWidget {
  const TelaAgenda({super.key});

  /// Dia do atendimento: "agora" e "hoje" contam para o dia do pedido.
  static DateTime _dia(Pedido p) {
    final d = (p.quando == QuandoPedido.combinado ? p.combinadoPara : null) ?? p.criadoEm;
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String _tituloDia(DateTime d) {
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final dif = d.difference(h).inDays;
    if (dif <= 0) return 'Hoje';
    if (dif == 1) return 'Amanhã';
    final s = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pedidosProProvider('andamento'));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pedidosProProvider),
        child: lista.when(
          loading: () => const Carregando(),
          error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(pedidosProProvider)),
          data: (l) {
            final aceitos = l.where((p) => p.status != StatusPedido.solicitado).toList()
              ..sort((a, b) {
                // Em curso primeiro; depois por dia e horário.
                int peso(Pedido p) => p.status == StatusPedido.emAtendimento ? 0 : (p.status == StatusPedido.aCaminho ? 1 : 2);
                final c = peso(a).compareTo(peso(b));
                if (c != 0) return c;
                final da = a.combinadoPara ?? a.criadoEm;
                final db = b.combinadoPara ?? b.criadoEm;
                return da.compareTo(db);
              });
            if (aceitos.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 60),
                EstadoVazio(
                  icone: Symbols.event_available_rounded,
                  titulo: 'Agenda livre',
                  texto: 'Os pedidos que você aceitar aparecem aqui, com o horário e o endereço.',
                ),
              ]);
            }
            final porDia = <DateTime, List<Pedido>>{};
            for (final p in aceitos) {
              porDia.putIfAbsent(_dia(p), () => []).add(p);
            }
            final dias = porDia.keys.toList()..sort();
            return ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 24), children: [
              for (final d in dias) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text(_tituloDia(d), style: t.titleMedium),
                ),
                for (final p in porDia[d]!) Padding(padding: const EdgeInsets.only(bottom: 10), child: CartaoAtendimento(p: p)),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
