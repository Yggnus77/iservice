import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Pedidos direcionados a este profissional. Ele tem o prazo de app_config.prazo_resposta_min para aceitar um
/// pedido para agora (mais tempo para um agendado) e pode sugerir outro horário;
/// se recusar ou não responder, o pedido termina (não vai para outro).
class TelaSolicitacoes extends ConsumerWidget {
  const TelaSolicitacoes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Solicitações'),
          bottom: const TabBar(tabs: [Tab(text: 'Novas'), Tab(text: 'Histórico')]),
        ),
        body: const TabBarView(children: [_Novas(), _Historico()]),
      ),
    );
  }
}

class _Novas extends ConsumerWidget {
  const _Novas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pedidosProProvider('andamento'));
    final disponivel = ref.watch(meuPerfilProvider).value?.profissional?.disponivel ?? false;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pedidosProProvider),
      child: lista.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(pedidosProProvider)),
        data: (l) {
          final novas = l.where((p) => p.status == StatusPedido.solicitado).toList();
          if (novas.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 60),
              EstadoVazio(
                icone: Symbols.notifications_paused_rounded,
                titulo: 'Nenhuma solicitação agora',
                texto: disponivel
                    ? 'Quando um cliente escolher você, o pedido aparece aqui e você recebe um aviso.'
                    : 'Você está indisponível. Ligue a disponibilidade no Início para receber pedidos.',
                acao: disponivel ? null : 'Ir para o Início',
                aoTocarAcao: disponivel ? null : () => context.go('/inicio'),
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Medidas.margemTela),
            itemCount: novas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _CartaoSolicitacao(key: ValueKey(novas[i].id), p: novas[i]),
          );
        },
      ),
    );
  }
}

/// Aceita ou recusa um pedido (no Início e em Solicitações). Ao recusar, pergunta
/// o motivo; se a pessoa fechar sem escolher, nada acontece.
Future<void> responderChamado(BuildContext context, WidgetRef ref, Pedido p, {required bool aceitar}) async {
  String? motivo;
  if (!aceitar) {
    motivo = await _perguntarMotivo(context);
    if (motivo == null) return;
  }
  try {
    final r = await ref.read(pedidosRepo).responder(p.id, aceitar: aceitar, motivo: motivo);
    ref.invalidate(pedidosProProvider);
    if (!context.mounted) return;
    if (r.status == StatusPedido.expirado) {
      mostrarMensagem(context, 'O tempo para responder acabou.');
    } else if (aceitar && r.agendado) {
      mostrarMensagem(context, 'Marcado para ${r.quandoTexto.toLowerCase()}. Está na sua Agenda e avisamos o cliente.');
    } else if (aceitar) {
      unawaited(context.push('/pedido/${p.id}'));
    } else {
      mostrarMensagem(context, 'Pedido recusado.');
    }
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

/// Sugere outro dia e horário ao cliente (ocupado agora, ou o horário pedido não dá).
/// Os horários já marcados na agenda ficam bloqueados.
Future<void> sugerirHorario(BuildContext context, WidgetRef ref, Pedido p) async {
  final config = await ref.read(configProvider.future).catchError((_) => <String, dynamic>{});
  final agenda = await ref.read(pedidosProProvider('andamento').future).catchError((_) => <Pedido>[]);
  if (!context.mounted) return;
  final diasMax = (config['dias_max_combinado'] as num?)?.toInt() ?? 7;
  final ocupados = [
    for (final o in agenda)
      if (o.id != p.id && o.agendado && o.status != StatusPedido.solicitado) o.combinadoPara!.toLocal(),
  ];
  final h = await escolherHorarioAgenda(
    context,
    diasMax: diasMax,
    titulo: 'Sugerir outro horário',
    subtitulo: '${primeiroNome(p.outraParteNome ?? 'O cliente')} recebe a sugestão e confirma pelo app. Nos próximos $diasMax dias.',
    ocupados: ocupados,
    inicial: p.agendado ? p.combinadoPara : null,
    rotuloConfirmar: 'Sugerir',
  );
  if (h == null || !context.mounted) return;
  try {
    final r = await ref.read(pedidosRepo).proporHorario(p.id, h);
    ref.invalidate(pedidosProProvider);
    if (!context.mounted) return;
    mostrarMensagem(
      context,
      r.status == StatusPedido.expirado ? 'O tempo para responder acabou.' : 'Sugestão enviada. Avisamos quando ${primeiroNome(p.outraParteNome ?? 'o cliente')} confirmar.',
    );
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

/// Aviso no lugar dos botões enquanto o cliente decide sobre o horário sugerido.
class AguardandoCliente extends StatelessWidget {
  const AguardandoCliente({super.key, required this.p});
  final Pedido p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.acaoSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
      child: Row(children: [
        Icon(Symbols.edit_calendar_rounded, color: c.acaoTexto),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Você sugeriu ${diaRelativoEHora(p.propostaPara!).toLowerCase()}. Aguardando ${primeiroNome(p.outraParteNome ?? 'o cliente')} confirmar.',
            style: t.bodyMedium,
          ),
        ),
      ]),
    );
  }
}

Future<String?> _perguntarMotivo(BuildContext context) {
  const motivos = ['Fora da minha área', 'Não faço esse serviço', 'Horário não dá e não tenho outro', 'Outro motivo'];
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 4),
          child: Text('Por que vai recusar?', style: Theme.of(ctx).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 8),
          child: Text('O cliente é avisado. Recusas frequentes baixam sua confiabilidade. Se só o horário não dá, sugira outro.', style: Theme.of(ctx).textTheme.bodySmall),
        ),
        for (final m in motivos) ListTile(title: Text(m), onTap: () => Navigator.pop(ctx, m)),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

class _CartaoSolicitacao extends ConsumerStatefulWidget {
  const _CartaoSolicitacao({super.key, required this.p});
  final Pedido p;

  @override
  ConsumerState<_CartaoSolicitacao> createState() => _CartaoSolicitacaoState();
}

class _CartaoSolicitacaoState extends ConsumerState<_CartaoSolicitacao> {
  bool _ocupado = false;
  bool _acabou = false;

  Pedido get p => widget.p;

  Future<void> _responder(bool aceitar) async {
    setState(() => _ocupado = true);
    await responderChamado(context, ref, p, aceitar: aceitar);
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    final expirou = _acabou || p.tempoParaResponder == Duration.zero;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.outraParteNome ?? 'Cliente', style: t.titleSmall),
                Text(profissao?.nome ?? '', style: t.bodySmall),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: expirou ? c.perigoSuave : c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioPilula)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.timer_rounded, size: 16, color: expirou ? c.perigo : c.alerta),
                const SizedBox(width: 4),
                if (expirou) Text('Expirou', style: t.labelMedium?.copyWith(color: c.perigo)) else ContagemRegressiva(
                        ate: p.responderAte,
                        estilo: t.labelMedium?.copyWith(color: c.alerta),
                        aoAcabar: () {
                          if (!mounted) return;
                          setState(() => _acabou = true);
                          ref.invalidate(pedidosProProvider);
                        },
                      ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (p.especialidade != null) Text(p.especialidade!, style: t.titleMedium),
          if (p.descricao.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.descricao, style: t.bodyMedium),
          ],
          const SizedBox(height: 12),
          _Info(
            icone: switch (p.quando) { QuandoPedido.agora => Symbols.bolt_rounded, QuandoPedido.hoje => Symbols.schedule_rounded, QuandoPedido.combinado => Symbols.event_rounded },
            texto: p.agendado ? 'Agendar para ${p.quandoTexto.toLowerCase()}' : p.quandoTexto,
            destaque: p.quando != QuandoPedido.hoje,
          ),
          _Info(icone: Symbols.location_on_rounded, texto: [p.enderecoTexto, if (p.distanciaKm != null) distancia(p.distanciaKm)].join(' · ')),
          _Info(
            icone: Symbols.payments_rounded,
            texto: [
              if (p.precoInformado == null) 'Preço combinado no local' else 'Seu preço: a partir de ${reais(p.precoInformado)}',
              if (p.taxaUrgencia > 0) '+ ${reais(p.taxaUrgencia)} de urgência',
            ].join(' '),
          ),
          const SizedBox(height: 14),
          if (p.aguardandoCliente)
            AguardandoCliente(p: p)
          else ...[
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _ocupado || expirou ? null : () => _responder(false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Medidas.alturaBotao), foregroundColor: c.perigo),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: BotaoPrincipal(
                  rotulo: p.agendado ? 'Confirmar horário' : 'Aceitar',
                  icone: Symbols.check_rounded,
                  carregando: _ocupado,
                  aoTocar: expirou ? null : () => _responder(true),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: _ocupado || expirou ? null : () => sugerirHorario(context, ref, p),
                icon: const Icon(Symbols.edit_calendar_rounded),
                label: const Text('Sugerir outro horário'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icone, required this.texto, this.destaque = false});
  final IconData icone;
  final String texto;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 18, fill: destaque ? 1 : 0, color: destaque ? c.alerta : c.textoSuave),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: destaque ? t.titleSmall : t.bodyMedium)),
      ]),
    );
  }
}

class _Historico extends ConsumerWidget {
  const _Historico();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pedidosProProvider('todos'));
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pedidosProProvider),
      child: lista.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(pedidosProProvider)),
        data: (l) {
          final hist = l.where((p) => !p.status.emAndamento).toList();
          if (hist.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 60),
              EstadoVazio(icone: Symbols.history_rounded, titulo: 'Sem histórico ainda', texto: 'Os pedidos encerrados aparecem aqui.'),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: hist.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (_, i) {
              final p = hist[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela, vertical: 4),
                leading: Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto, tamanho: 44),
                title: Text(p.outraParteNome ?? '', style: t.titleSmall),
                subtitle: Text('${p.especialidade ?? p.codigo} · ${dataCurta(p.criadoEm)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  EtiquetaStatus(status: p.status),
                  if (p.valorCobrado != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(reais(p.valorCobrado), style: t.labelMedium)),
                ]),
                onTap: () => context.push('/pedido/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
