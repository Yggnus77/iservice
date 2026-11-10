import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';
import 'painel.dart';

/// Agenda do profissional: os próximos dias (até dias_max_combinado) com os
/// atendimentos marcados, o que está em curso e os agendamentos aguardando resposta.
class TelaAgenda extends ConsumerStatefulWidget {
  const TelaAgenda({super.key});

  @override
  ConsumerState<TelaAgenda> createState() => _TelaAgendaState();
}

class _TelaAgendaState extends ConsumerState<TelaAgenda> {
  /// Dia escolhido na faixa da semana; null mostra todos.
  DateTime? _dia;

  static DateTime _diaDe(Pedido p) => DateUtils.dateOnly(p.dataAtendimento);

  static String _tituloDia(DateTime d) {
    final hoje = DateUtils.dateOnly(DateTime.now());
    if (d.isBefore(hoje)) return 'Hoje';
    return diaRelativo(d);
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(pedidosProProvider('andamento'));
    final config = ref.watch(configProvider).value ?? const {};
    final diasMax = (config['dias_max_combinado'] as num?)?.toInt() ?? 7;
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final hoje = DateUtils.dateOnly(DateTime.now());
    final dias = [for (var i = 0; i <= diasMax; i++) hoje.add(Duration(days: i))];

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pedidosProProvider),
        child: lista.when(
          loading: () => const Carregando(),
          error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(pedidosProProvider)),
          data: (l) {
            final marcados = l.where((p) => p.status != StatusPedido.solicitado).toList()
              ..sort((a, b) {
                // Em curso primeiro; depois por dia e horário.
                int peso(Pedido p) => p.status == StatusPedido.emAtendimento ? 0 : (p.status == StatusPedido.aCaminho ? 1 : 2);
                final c = peso(a).compareTo(peso(b));
                return c != 0 ? c : a.dataAtendimento.compareTo(b.dataAtendimento);
              });
            final aguardando = l.where((p) => p.status == StatusPedido.solicitado && (p.agendado || p.aguardandoCliente)).toList()
              ..sort((a, b) => (a.propostaPara ?? a.dataAtendimento).compareTo(b.propostaPara ?? b.dataAtendimento));

            final porDia = <DateTime, List<Pedido>>{};
            for (final p in marcados) {
              final d = _diaDe(p).isBefore(hoje) ? hoje : _diaDe(p);
              porDia.putIfAbsent(d, () => []).add(p);
            }
            final diasComAtendimento = porDia.keys.where((d) => _dia == null || DateUtils.isSameDay(d, _dia)).toList()..sort();

            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              const SizedBox(height: 4),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
                  itemCount: dias.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = dias[i];
                    final sel = _dia != null && DateUtils.isSameDay(d, _dia);
                    return CartaoDia(
                      dia: d,
                      selecionado: sel,
                      marcados: porDia[d]?.length ?? 0,
                      rodape: 'livre',
                      aoTocar: () => setState(() => _dia = sel ? null : d),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 10, Medidas.margemTela, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _dia == null ? 'Próximos $diasMax dias' : _tituloDia(_dia!),
                      style: t.titleMedium,
                    ),
                  ),
                  if (_dia != null) TextButton(onPressed: () => setState(() => _dia = null), child: const Text('Ver todos')),
                ]),
              ),
              if (aguardando.isNotEmpty && _dia == null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Medidas.margemTela),
                  child: TituloSecao(titulo: 'Aguardando confirmação'),
                ),
                for (final p in aguardando)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 10),
                    child: _CartaoAguardando(p: p),
                  ),
              ],
              if (diasComAtendimento.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: EstadoVazio(
                    icone: Symbols.event_available_rounded,
                    titulo: _dia == null ? 'Agenda livre' : 'Dia livre',
                    texto: 'Os atendimentos que você aceitar ou marcar com clientes aparecem aqui, com horário e endereço.',
                  ),
                ),
              for (final d in diasComAtendimento) ...[
                if (_dia == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 8),
                    child: Text(_tituloDia(d), style: t.titleSmall?.copyWith(color: c.textoSuave)),
                  )
                else
                  const SizedBox(height: 12),
                for (final p in porDia[d]!)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 52,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            p.agendado ? hora(p.combinadoPara!) : (p.quando == QuandoPedido.agora ? 'Agora' : 'Hoje'),
                            style: t.titleSmall?.copyWith(color: c.acaoTexto),
                          ),
                        ),
                      ),
                      Expanded(child: CartaoAtendimento(p: p)),
                    ]),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 20, Medidas.margemTela, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Symbols.notifications_active_rounded, size: 18, color: c.textoSuave),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clientes podem agendar com você até $diasMax dias à frente, mesmo quando você está ocupado. '
                      'Você e o cliente recebem lembrete na véspera e 1 hora antes.',
                      style: t.bodySmall,
                    ),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Agendamento pedido pelo cliente (ou horário que você sugeriu) ainda sem resposta.
class _CartaoAguardando extends StatelessWidget {
  const _CartaoAguardando({required this.p});
  final Pedido p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final nome = primeiroNome(p.outraParteNome ?? 'Cliente');
    final (texto, quem) = p.aguardandoCliente
        ? ('Você sugeriu ${diaRelativoEHora(p.propostaPara!).toLowerCase()}', 'Aguardando $nome')
        : ('$nome pediu ${p.quandoTexto.toLowerCase()}', 'Responda até ${hora(p.responderAte)}');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: p.aguardandoCliente ? c.acaoSuave : c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
          child: Icon(p.aguardandoCliente ? Symbols.edit_calendar_rounded : Symbols.pending_actions_rounded, color: p.aguardandoCliente ? c.acaoTexto : c.alerta),
        ),
        title: Text(texto, style: t.titleSmall),
        subtitle: Text([quem, if (p.especialidade != null) p.especialidade!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Symbols.chevron_right_rounded),
        onTap: () => context.push('/pedido/${p.id}'),
      ),
    );
  }
}
