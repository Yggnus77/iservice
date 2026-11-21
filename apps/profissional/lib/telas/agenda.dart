import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';
import 'painel.dart';

/// A própria agenda: expediente e bloqueios (com motivo).
final minhaAgendaProvider = FutureProvider.autoDispose<AgendaProfissional>(
    (ref) => ref.read(pedidosRepo).agenda(supabase.auth.currentUser!.id));

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
    final agenda = ref.watch(minhaAgendaProvider).value ?? AgendaProfissional.vazia;
    final config = ref.watch(configProvider).value ?? const {};
    final diasMax = (config['dias_max_combinado'] as num?)?.toInt() ?? 7;
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final hoje = DateUtils.dateOnly(DateTime.now());
    final dias = [for (var i = 0; i <= diasMax; i++) hoje.add(Duration(days: i))];

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda'), actions: [
        TextButton.icon(
          onPressed: () => context.push('/meus-horarios'),
          icon: const Icon(Symbols.schedule_rounded),
          label: const Text('Meus horários'),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => bloquearHorario(context, ref, dia: _dia),
        icon: const Icon(Symbols.block_rounded),
        label: const Text('Bloquear horário'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pedidosProProvider);
          ref.invalidate(minhaAgendaProvider);
        },
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
            final diasComAtendimento = {
              ...porDia.keys,
              for (final d in dias)
                if (agenda.bloqueiosDo(d).isNotEmpty) d,
            }.where((d) => _dia == null || DateUtils.isSameDay(d, _dia)).toList()
              ..sort();

            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
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
                      rodape: agenda.diaFechado(d) ? 'folga' : 'livre',
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
                    texto: 'Os atendimentos que você aceitar ou marcar com clientes aparecem aqui, com horário e endereço. '
                        'Folgas e compromissos: toque em "Bloquear horário".',
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
                for (final b in agenda.bloqueiosDo(d))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 10),
                    child: _CartaoBloqueio(b: b, dia: d),
                  ),
                for (final p in porDia[d] ?? const <Pedido>[])
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
                      'Clientes podem agendar com você até $diasMax dias à frente, mesmo quando você está ocupado, '
                      '${agenda.temExpediente ? 'só dentro dos seus horários' : 'das 7h às 21h (defina os seus em "Meus horários")'} e fora dos bloqueios. '
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

/// Período bloqueado na agenda, com o botão de desbloquear.
class _CartaoBloqueio extends ConsumerWidget {
  const _CartaoBloqueio({required this.b, required this.dia});
  final BloqueioAgenda b;
  final DateTime dia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final ini = DateTime(dia.year, dia.month, dia.day);
    final fim = ini.add(const Duration(days: 1));
    final diaTodo = !b.inicio.isAfter(ini) && !b.fim.isBefore(fim);
    final periodo = diaTodo
        ? 'Dia todo'
        : '${b.inicio.isBefore(ini) ? '00:00' : hora(b.inicio)} às ${b.fim.isAfter(fim) ? '24:00' : hora(b.fim)}';
    return Card(
      color: c.superficieSuave,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        leading: Icon(Symbols.block_rounded, color: c.textoSuave),
        title: Text('Bloqueado · $periodo', style: t.titleSmall),
        subtitle: b.motivo.isEmpty ? null : Text(b.motivo),
        trailing: IconButton(
          tooltip: 'Desbloquear',
          icon: const Icon(Symbols.close_rounded),
          onPressed: b.id == null
              ? null
              : () async {
                  try {
                    await ref.read(pedidosRepo).desbloquear(b.id!);
                    ref.invalidate(minhaAgendaProvider);
                    if (context.mounted) mostrarMensagem(context, 'Horário liberado para agendamentos.');
                  } catch (e) {
                    if (context.mounted) mostrarErro(context, e);
                  }
                },
        ),
      ),
    );
  }
}

/// Folha para bloquear um período: dia, dia todo ou das/às, e o motivo (só você vê).
Future<void> bloquearHorario(BuildContext context, WidgetRef ref, {DateTime? dia}) async {
  final r = await showModalBottomSheet<(DateTime, DateTime, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FolhaBloqueio(dia: dia),
  );
  if (r == null || !context.mounted) return;
  try {
    final conflitos = await ref.read(pedidosRepo).bloquear(r.$1, r.$2, motivo: r.$3);
    ref.invalidate(minhaAgendaProvider);
    if (!context.mounted) return;
    mostrarMensagem(
      context,
      conflitos == 0
          ? 'Horário bloqueado. Clientes não conseguem agendar nele.'
          : 'Bloqueado. Atenção: $conflitos ${conflitos == 1 ? 'atendimento marcado continua' : 'atendimentos marcados continuam'} nesse período. Remarque ou cancele.',
    );
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

class _FolhaBloqueio extends StatefulWidget {
  const _FolhaBloqueio({this.dia});
  final DateTime? dia;

  @override
  State<_FolhaBloqueio> createState() => _FolhaBloqueioState();
}

class _FolhaBloqueioState extends State<_FolhaBloqueio> {
  late DateTime _de = DateUtils.dateOnly(widget.dia ?? DateTime.now());
  late DateTime _ate = _de;
  bool _diaTodo = false;
  TimeOfDay _ini = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _fim = const TimeOfDay(hour: 13, minute: 0);
  final _motivo = TextEditingController();

  Future<void> _escolherDia(bool inicio) async {
    final hoje = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      firstDate: inicio ? hoje : _de,
      lastDate: hoje.add(const Duration(days: 90)),
      initialDate: inicio ? _de : _ate,
    );
    if (d == null) return;
    setState(() {
      if (inicio) {
        _de = d;
        if (_ate.isBefore(d)) _ate = d;
      } else {
        _ate = d;
      }
    });
  }

  Future<void> _escolherHora(bool inicio) async {
    final h = await showTimePicker(context: context, initialTime: inicio ? _ini : _fim);
    if (h != null) setState(() => inicio ? _ini = h : _fim = h);
  }

  void _confirmar() {
    final DateTime ini;
    final DateTime fim;
    if (_diaTodo) {
      ini = _de;
      fim = _ate.add(const Duration(days: 1));
    } else {
      ini = DateTime(_de.year, _de.month, _de.day, _ini.hour, _ini.minute);
      fim = DateTime(_de.year, _de.month, _de.day, _fim.hour, _fim.minute);
      if (!fim.isAfter(ini)) {
        mostrarMensagem(context, 'O fim precisa ser depois do início.');
        return;
      }
    }
    Navigator.pop(context, (ini, fim, _motivo.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String data(DateTime d) => diaRelativo(d);
    return Padding(
      padding: EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Bloquear horário', style: t.titleLarge),
        const SizedBox(height: 4),
        Text('Clientes não conseguem agendar nesse período. Só você vê o motivo.', style: t.bodySmall),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dia todo (folga)'),
          value: _diaTodo,
          onChanged: (v) => setState(() => _diaTodo = v),
        ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _escolherDia(true),
              icon: const Icon(Symbols.calendar_month_rounded),
              label: Text(_diaTodo ? 'De ${data(_de).toLowerCase()}' : data(_de)),
            ),
          ),
          if (_diaTodo) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _escolherDia(false),
                icon: const Icon(Symbols.event_rounded),
                label: Text('Até ${data(_ate).toLowerCase()}'),
              ),
            ),
          ],
        ]),
        if (!_diaTodo) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _escolherHora(true), child: Text('Das ${_ini.format(context)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _escolherHora(false), child: Text('Às ${_fim.format(context)}'))),
          ]),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const ['Almoço', 'Folga', 'Compromisso', 'Médico'])
            ChoiceChip(label: Text(m), selected: _motivo.text == m, onSelected: (_) => setState(() => _motivo.text = m)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _motivo, maxLength: 80, decoration: const InputDecoration(hintText: 'Motivo (opcional)')),
        const SizedBox(height: 4),
        BotaoPrincipal(rotulo: 'Bloquear', icone: Symbols.block_rounded, aoTocar: _confirmar),
      ]),
    );
  }
}
