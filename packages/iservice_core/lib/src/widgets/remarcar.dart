import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../config.dart';
import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import 'agenda.dart';
import 'componentes.dart';

/// Pede para remarcar um agendamento confirmado. O cliente vê só os horários livres
/// do profissional; o profissional escolhe na própria agenda (pode sair do expediente).
/// Devolve true quando o pedido de remarcação foi enviado.
Future<bool> pedirRemarcacao(BuildContext context, WidgetRef ref, Pedido p, {required String profissionalId, required bool souProfissional}) async {
  final config = await ref.read(configProvider.future).catchError((_) => <String, dynamic>{});
  final agenda = await ref.read(pedidosRepo).agenda(profissionalId).catchError((_) => AgendaProfissional.vazia);
  if (!context.mounted) return false;
  final diasMax = (config['dias_max_combinado'] as num?)?.toInt() ?? 7;
  final semEste = agenda.sem(p.combinadoPara);
  final outro = primeiroNome(p.outraParteNome ?? (souProfissional ? 'O cliente' : 'O profissional'));
  final h = await escolherHorarioAgenda(
    context,
    diasMax: diasMax,
    titulo: 'Remarcar atendimento',
    subtitulo: 'Está marcado para ${diaRelativoEHora(p.combinadoPara!).toLowerCase()}. $outro recebe o novo horário e confirma pelo app.',
    ocupados: souProfissional ? semEste.ocupados : const [],
    agenda: souProfissional ? null : semEste,
    rotuloConfirmar: 'Pedir para remarcar',
  );
  if (h == null || !context.mounted) return false;
  try {
    await ref.read(pedidosRepo).remarcar(p.id, h);
    if (context.mounted) mostrarMensagem(context, 'Pedido enviado. Até $outro confirmar, continua o horário de agora.');
    return true;
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
    return false;
  }
}

/// Cartão de remarcação pendente: quem pediu aguarda (e pode desistir); o outro confirma ou mantém.
class CartaoRemarcacao extends ConsumerStatefulWidget {
  const CartaoRemarcacao({super.key, required this.p, this.aoMudar});
  final Pedido p;
  final VoidCallback? aoMudar;

  @override
  ConsumerState<CartaoRemarcacao> createState() => _CartaoRemarcacaoState();
}

class _CartaoRemarcacaoState extends ConsumerState<CartaoRemarcacao> {
  bool _ocupado = false;

  Future<void> _acao(Future<void> Function() f, String sucesso) async {
    setState(() => _ocupado = true);
    try {
      await f();
      widget.aoMudar?.call();
      if (mounted) mostrarMensagem(context, sucesso);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    if (!p.remarcacaoPendente) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final fuiEu = p.remarcarPor == supabase.auth.currentUser?.id;
    final nome = primeiroNome(p.outraParteNome ?? '');
    final repo = ref.read(pedidosRepo);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
              child: Icon(Symbols.edit_calendar_rounded, color: c.alerta),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fuiEu ? 'Você pediu para remarcar' : '$nome pediu para remarcar', style: t.bodySmall),
                Text(diaRelativoEHora(p.remarcarPara!), style: t.titleMedium),
                Text('Horário atual: ${diaRelativoEHora(p.combinadoPara!).toLowerCase()}', style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            fuiEu
                ? 'Aguardando $nome até as ${hora(p.remarcarAte!)}. Sem resposta, continua o horário atual.'
                : 'Responda até as ${hora(p.remarcarAte!)}. Sem resposta, continua o horário atual.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 12),
          if (fuiEu)
            OutlinedButton(
              onPressed: _ocupado ? null : () => _acao(() => repo.desistirRemarcacao(p.id), 'Pedido de remarcação desfeito.'),
              child: const Text('Desistir de remarcar'),
            )
          else ...[
            BotaoPrincipal(
              rotulo: 'Confirmar novo horário',
              icone: Symbols.event_available_rounded,
              carregando: _ocupado,
              aoTocar: () => _acao(() => repo.responderRemarcacao(p.id, aceitar: true), 'Remarcado. Avisamos vocês dois.'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _ocupado ? null : () => _acao(() => repo.responderRemarcacao(p.id, aceitar: false), 'Mantido o horário atual.'),
              child: const Text('Manter o horário atual'),
            ),
          ],
        ]),
      ),
    );
  }
}
