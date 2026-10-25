import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Ganhos por semana, mês e ano, com o acompanhamento do limite anual do MEI.
class TelaGanhos extends ConsumerStatefulWidget {
  const TelaGanhos({super.key});

  @override
  ConsumerState<TelaGanhos> createState() => _TelaGanhosState();
}

class _TelaGanhosState extends ConsumerState<TelaGanhos> {
  String _periodo = 'semana';

  @override
  Widget build(BuildContext context) {
    final ganhos = ref.watch(ganhosProvider(_periodo));
    final concluidos = ref.watch(pedidosProProvider('concluidos')).value ?? const <Pedido>[];
    final t = Theme.of(context).textTheme;
    final c = context.cores;

    return Scaffold(
      appBar: AppBar(title: const Text('Ganhos')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ganhosProvider);
          ref.invalidate(pedidosProProvider);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24), children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'semana', label: Text('Semana')),
              ButtonSegment(value: 'mes', label: Text('Mês')),
              ButtonSegment(value: 'ano', label: Text('Ano')),
            ],
            selected: {_periodo},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _periodo = s.first),
          ),
          const SizedBox(height: 16),
          ganhos.when(
            loading: () => const SizedBox(height: 240, child: Carregando()),
            error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(ganhosProvider)),
            data: (g) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: Cores.gradienteMarca, borderRadius: BorderRadius.circular(Medidas.raioCartao)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    switch (_periodo) { 'semana' => 'Nesta semana', 'ano' => 'Neste ano', _ => 'Neste mês' },
                    style: t.labelLarge?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(reais(g.periodo), style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _Mini(rotulo: 'Hoje', valor: reais(g.hoje)),
                    _Mini(rotulo: 'Serviços', valor: '${g.servicos}'),
                    _Mini(rotulo: 'Ticket médio', valor: reais(g.ticketMedio)),
                  ]),
                ]),
              ),
              if (g.porDia.isNotEmpty) ...[
                const TituloSecao(titulo: 'Por dia'),
                Card(child: Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 10), child: _Barras(dias: g.porDia, periodo: _periodo))),
              ],
              const TituloSecao(titulo: 'Limite do MEI'),
              _LimiteMei(ano: g.ano, limite: g.limiteMei),
            ]),
          ),
          const TituloSecao(titulo: 'Serviços concluídos'),
          if (concluidos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Os serviços concluídos aparecem aqui com o valor cobrado.', style: t.bodySmall, textAlign: TextAlign.center),
            )
          else
            Card(
              child: Column(children: [
                for (final (i, p) in concluidos.take(20).indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto, tamanho: 40),
                    title: Text(p.outraParteNome ?? '', style: t.titleSmall),
                    subtitle: Text('${p.especialidade ?? p.codigo} · ${dataCurta(p.concluidoEm ?? p.criadoEm)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(reais(p.valorCobrado), style: t.titleSmall?.copyWith(color: c.sucesso)),
                    onTap: () => context.push('/pedido/${p.id}'),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Symbols.info_rounded, size: 16, color: c.textoSuave),
            const SizedBox(width: 6),
            Expanded(child: Text('Valores informados por você ao concluir. O cliente paga direto a você.', style: t.bodySmall)),
          ]),
        ]),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.rotulo, required this.valor});
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(valor, style: t.titleSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(rotulo, style: t.labelSmall?.copyWith(color: Colors.white70)),
      ]),
    );
  }
}

/// Gráfico de barras simples. No ano, agrupa por mês.
class _Barras extends StatelessWidget {
  const _Barras({required this.dias, required this.periodo});
  final List<(DateTime, double)> dias;
  final String periodo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final List<(String, double)> barras;
    if (periodo == 'ano') {
      final porMes = List<double>.filled(12, 0);
      for (final (d, v) in dias) {
        porMes[d.month - 1] += v;
      }
      barras = [for (var m = 0; m < 12; m++) (DateFormat.MMM('pt_BR').format(DateTime(2000, m + 1)).substring(0, 1).toUpperCase(), porMes[m])];
    } else if (periodo == 'semana') {
      final hoje = DateTime.now();
      final segunda = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: hoje.weekday - 1));
      const nomes = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
      barras = [
        for (var i = 0; i < 7; i++)
          (nomes[i], dias.where((d) => DateUtils.isSameDay(d.$1, segunda.add(Duration(days: i)))).fold(0.0, (s, d) => s + d.$2)),
      ];
    } else {
      barras = [for (final (d, v) in dias) ('${d.day}', v)];
    }
    final maior = barras.fold(0.0, (m, b) => math.max(m, b.$2));
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (rotulo, v) in barras)
          Expanded(
            child: Tooltip(
              message: reais(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: maior == 0 ? 2 : math.max(2, 110 * v / maior),
                    decoration: BoxDecoration(color: v > 0 ? c.acao : c.superficieSuave, borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(height: 6),
                  Text(rotulo, style: t.labelSmall, maxLines: 1),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _LimiteMei extends StatelessWidget {
  const _LimiteMei({required this.ano, required this.limite});
  final double ano;
  final double limite;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final fracao = limite <= 0 ? 0.0 : (ano / limite).clamp(0.0, 1.0);
    final perto = fracao >= 0.8;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Faturamento no ano', style: t.titleSmall)),
            Text('${(fracao * 100).round()}%', style: t.labelLarge?.copyWith(color: perto ? c.perigo : c.acaoTexto)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: fracao, minHeight: 10, color: perto ? c.perigo : c.acao, backgroundColor: c.superficieSuave),
          ),
          const SizedBox(height: 8),
          Text('${reais(ano)} de ${reais(limite)} permitidos ao MEI por ano.', style: t.bodySmall),
          if (perto) ...[
            const SizedBox(height: 8),
            Text('Você está perto do limite. Converse com um contador sobre mudar de enquadramento.', style: t.bodySmall?.copyWith(color: c.perigo)),
          ],
        ]),
      ),
    );
  }
}
