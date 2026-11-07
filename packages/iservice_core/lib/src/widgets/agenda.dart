import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import 'componentes.dart';

/// Abre a folha para escolher dia e horário na agenda (até [diasMax] dias).
/// [ocupados] são horários já marcados com o profissional: ficam bloqueados
/// com 1 hora de folga para cada lado.
Future<DateTime?> escolherHorarioAgenda(
  BuildContext context, {
  required int diasMax,
  required String titulo,
  String? subtitulo,
  List<DateTime> ocupados = const [],
  DateTime? inicial,
  String rotuloConfirmar = 'Confirmar',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FolhaHorario(
      diasMax: diasMax,
      titulo: titulo,
      subtitulo: subtitulo,
      ocupados: ocupados,
      inicial: inicial,
      rotuloConfirmar: rotuloConfirmar,
    ),
  );
}

class _FolhaHorario extends StatefulWidget {
  const _FolhaHorario({
    required this.diasMax,
    required this.titulo,
    required this.subtitulo,
    required this.ocupados,
    required this.inicial,
    required this.rotuloConfirmar,
  });
  final int diasMax;
  final String titulo;
  final String? subtitulo;
  final List<DateTime> ocupados;
  final DateTime? inicial;
  final String rotuloConfirmar;

  @override
  State<_FolhaHorario> createState() => _FolhaHorarioState();
}

class _FolhaHorarioState extends State<_FolhaHorario> {
  /// Horários sugeridos de cada dia (o "Outro horário" abre o relógio).
  static const _inicio = 7;
  static const _fim = 21;

  late final DateTime _hoje = DateUtils.dateOnly(DateTime.now());
  late DateTime _dia;
  DateTime? _escolhido;

  @override
  void initState() {
    super.initState();
    final ini = widget.inicial?.toLocal();
    _escolhido = ini != null && _valido(ini) ? ini : null;
    _dia = ini != null ? DateUtils.dateOnly(ini) : _primeiroDiaComHorario();
  }

  List<DateTime> get _dias => [for (var i = 0; i <= widget.diasMax; i++) _hoje.add(Duration(days: i))];

  /// Último instante permitido (o banco aceita até agora + diasMax dias).
  DateTime get _limite => DateTime.now().add(Duration(days: widget.diasMax));

  bool _ocupado(DateTime h) => widget.ocupados.any((o) => h.difference(o).inMinutes.abs() < 60);

  bool _valido(DateTime h) => h.isAfter(DateTime.now().add(const Duration(minutes: 30))) && !h.isAfter(_limite) && !_ocupado(h);

  List<DateTime> _horarios(DateTime dia) => [
        for (var h = _inicio; h <= _fim; h++)
          for (final m in const [0, 30])
            if (!(h == _fim && m == 30)) DateTime(dia.year, dia.month, dia.day, h, m),
      ];

  int _livres(DateTime dia) => _horarios(dia).where(_valido).length;

  DateTime _primeiroDiaComHorario() => _dias.firstWhere((d) => _livres(d) > 0, orElse: () => _hoje.add(const Duration(days: 1)));

  Future<void> _outroHorario() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _escolhido == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.fromDateTime(_escolhido!),
      helpText: 'Outro horário em ${diaRelativo(_dia).toLowerCase()}',
    );
    if (t == null || !mounted) return;
    final h = DateTime(_dia.year, _dia.month, _dia.day, t.hour, t.minute);
    if (!_valido(h)) {
      mostrarMensagem(
        context,
        _ocupado(h) ? 'Esse horário já está marcado com outro cliente.' : 'Escolha a partir de 30 minutos daqui e até ${widget.diasMax} dias.',
      );
      return;
    }
    setState(() => _escolhido = h);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final horarios = _horarios(_dia);
    final temLivre = horarios.any(_valido);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 4),
            child: Text(widget.titulo, style: t.titleLarge),
          ),
          if (widget.subtitulo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 8),
              child: Text(widget.subtitulo!, style: t.bodySmall),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
              itemCount: _dias.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _dias[i];
                return CartaoDia(
                  dia: d,
                  selecionado: DateUtils.isSameDay(d, _dia),
                  rodape: _livres(d) == 0 ? 'cheio' : null,
                  aoTocar: () => setState(() => _dia = d),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 8),
            child: Text(diaRelativo(_dia), style: t.titleSmall),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!temLivre)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Não há horários livres neste dia. Escolha outro dia.', style: t.bodySmall),
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in horarios)
                    if (h.isAfter(DateTime.now().add(const Duration(minutes: 30))) && !h.isAfter(_limite))
                      ChoiceChip(
                        label: Text(_ocupado(h) ? '${hora(h)} · ocupado' : hora(h)),
                        selected: _escolhido == h,
                        showCheckmark: false,
                        onSelected: _ocupado(h) ? null : (_) => setState(() => _escolhido = h),
                      ),
                ]),
                const SizedBox(height: 8),
                TextButton.icon(onPressed: _outroHorario, icon: const Icon(Symbols.schedule_rounded), label: const Text('Outro horário')),
                if (widget.ocupados.isNotEmpty)
                  Row(children: [
                    Icon(Symbols.info_rounded, size: 16, color: c.textoSuave),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Horários marcados com outros clientes ficam bloqueados.', style: t.bodySmall)),
                  ]),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 4, Medidas.margemTela, 12),
            child: BotaoPrincipal(
              rotulo: _escolhido == null ? 'Escolha um horário' : '${widget.rotuloConfirmar}: ${diaRelativoEHora(_escolhido!)}',
              icone: Symbols.event_available_rounded,
              aoTocar: _escolhido == null ? null : () => Navigator.pop(context, _escolhido),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Cartão de um dia na faixa da semana ("SEX" / "14" / rodapé opcional).
class CartaoDia extends StatelessWidget {
  const CartaoDia({super.key, required this.dia, required this.selecionado, required this.aoTocar, this.rodape, this.marcados = 0});
  final DateTime dia;
  final bool selecionado;
  final VoidCallback aoTocar;
  final String? rodape;

  /// Quantos atendimentos marcados no dia (bolinhas embaixo do número).
  final int marcados;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final hoje = DateUtils.isSameDay(dia, DateTime.now());
    final semana = hoje ? 'HOJE' : DateFormat.E('pt_BR').format(dia).replaceAll('.', '').toUpperCase();
    final corTexto = selecionado ? c.textoNaAcao : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: selecionado ? c.acao : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.raioControle),
        side: BorderSide(color: selecionado ? c.acao : c.linha, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioControle),
        onTap: aoTocar,
        child: SizedBox(
          width: 60,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(semana, style: t.labelSmall?.copyWith(color: selecionado ? corTexto : c.textoSuave, fontWeight: FontWeight.w700, letterSpacing: .5)),
            const SizedBox(height: 2),
            Text('${dia.day}', style: t.titleLarge?.copyWith(color: corTexto, fontWeight: FontWeight.w700)),
            if (marcados > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < marcados.clamp(0, 3); i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: selecionado ? corTexto : c.acaoTexto, shape: BoxShape.circle),
                  ),
              ])
            else if (rodape != null)
              Text(rodape!, style: t.labelSmall?.copyWith(color: selecionado ? corTexto : c.textoSuave, fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}
