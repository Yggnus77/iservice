import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'agenda.dart' show minhaAgendaProvider;

/// Horário de trabalho: em que dias e horários o profissional atende.
/// Os clientes só conseguem agendar dentro desses horários.
class TelaMeusHorarios extends ConsumerStatefulWidget {
  const TelaMeusHorarios({super.key});

  @override
  ConsumerState<TelaMeusHorarios> createState() => _TelaMeusHorariosState();
}

class _TelaMeusHorariosState extends ConsumerState<TelaMeusHorarios> {
  /// Segunda a domingo, na ordem da tela (dia do banco: 0 = domingo).
  static const _dias = [(1, 'Segunda'), (2, 'Terça'), (3, 'Quarta'), (4, 'Quinta'), (5, 'Sexta'), (6, 'Sábado'), (0, 'Domingo')];
  static const _padrao = Expediente(8 * 60, 18 * 60);

  Map<int, Expediente>? _horario;
  final _ativo = <int, bool>{};
  bool _salvando = false;

  void _carregar(AgendaProfissional a) {
    if (_horario != null) return;
    if (a.temExpediente) {
      _horario = {for (final d in _dias) d.$1: a.expediente[d.$1] ?? _padrao};
      for (final d in _dias) {
        _ativo[d.$1] = a.expediente.containsKey(d.$1);
      }
    } else {
      // Sem horário salvo: sugere segunda a sábado, 8h às 18h.
      _horario = {for (final d in _dias) d.$1: _padrao};
      for (final d in _dias) {
        _ativo[d.$1] = d.$1 != 0;
      }
    }
  }

  Future<void> _escolher(int dia, bool inicio) async {
    final e = _horario![dia]!;
    final atual = inicio ? e.inicio : e.fim;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: atual ~/ 60, minute: atual % 60),
      helpText: inicio ? 'Começo a atender às' : 'Paro de atender às',
    );
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    setState(() => _horario![dia] = inicio ? Expediente(m, e.fim) : Expediente(e.inicio, m));
  }

  Future<void> _salvar() async {
    final h = {for (final d in _dias) if (_ativo[d.$1] == true) d.$1: _horario![d.$1]!};
    if (h.isEmpty) {
      mostrarMensagem(context, 'Marque pelo menos um dia. Para parar de receber pedidos, desligue "Disponível para chamados" no Início.');
      return;
    }
    for (final e in h.values) {
      if (e.fim - e.inicio < 60) {
        mostrarMensagem(context, 'Cada dia precisa ter pelo menos 1 hora de atendimento.');
        return;
      }
    }
    setState(() => _salvando = true);
    try {
      await ref.read(pedidosRepo).salvarExpediente(h);
      ref.invalidate(minhaAgendaProvider);
      if (!mounted) return;
      mostrarMensagem(context, 'Horários salvos. Os clientes só agendam dentro deles.');
      context.pop();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agenda = ref.watch(minhaAgendaProvider);
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Scaffold(
      appBar: AppBar(title: const Text('Meus horários')),
      body: agenda.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(minhaAgendaProvider)),
        data: (a) {
          _carregar(a);
          return ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 24), children: [
            Text('Em que dias e horários você atende?', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Os clientes só conseguem agendar dentro desses horários. Para uma folga, almoço ou compromisso, '
              'use "Bloquear horário" na Agenda.',
              style: t.bodySmall,
            ),
            if (!a.temExpediente) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Symbols.info_rounded, size: 16, color: c.alerta),
                const SizedBox(width: 6),
                Expanded(child: Text('Hoje os clientes podem agendar com você em qualquer dia, das 7h às 21h.', style: t.bodySmall)),
              ]),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                for (final d in _dias) ...[
                  if (d != _dias.first) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(children: [
                      SizedBox(width: 82, child: Text(d.$2, style: t.titleSmall)),
                      Expanded(
                        child: _ativo[d.$1] == true
                            ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                                _Hora(texto: Expediente.texto(_horario![d.$1]!.inicio), aoTocar: () => _escolher(d.$1, true)),
                                Text('às', style: t.bodySmall),
                                _Hora(texto: Expediente.texto(_horario![d.$1]!.fim), aoTocar: () => _escolher(d.$1, false)),
                              ])
                            : Text('Não atendo', style: t.bodyMedium?.copyWith(color: c.textoSuave)),
                      ),
                      Switch(value: _ativo[d.$1] == true, onChanged: (v) => setState(() => _ativo[d.$1] = v)),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() {
                final seg = _horario![1]!;
                for (final d in _dias) {
                  if (_ativo[d.$1] == true) _horario![d.$1] = seg;
                }
              }),
              icon: const Icon(Symbols.content_copy_rounded),
              label: const Text('Usar o horário de segunda nos outros dias'),
            ),
          ]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 12),
          child: BotaoPrincipal(rotulo: 'Salvar horários', icone: Symbols.check_rounded, carregando: _salvando, aoTocar: _horario == null ? null : _salvar),
        ),
      ),
    );
  }
}

class _Hora extends StatelessWidget {
  const _Hora({required this.texto, required this.aoTocar});
  final String texto;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => ActionChip(label: Text(texto), onPressed: aoTocar, visualDensity: VisualDensity.compact);
}
