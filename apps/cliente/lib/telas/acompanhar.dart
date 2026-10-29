import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../estado.dart';

final _pedidoBase = FutureProvider.autoDispose.family<Pedido?, String>((ref, id) async {
  final lista = await ref.read(pedidosRepo).meus(papel: 'cliente');
  return lista.where((p) => p.id == id).firstOrNull;
});

final _pedidoAoVivo = StreamProvider.autoDispose.family<Pedido, Pedido>((ref, base) => ref.read(pedidosRepo).acompanhar(base));

/// Acompanhamento do pedido em tempo real, com chat, compartilhar e emergência.
class TelaAcompanhar extends ConsumerWidget {
  const TelaAcompanhar({super.key, required this.pedidoId});
  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(_pedidoBase(pedidoId));
    return base.when(
      loading: () => const Scaffold(body: Carregando()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErroNaTela(erro: e, aoTentar: () => ref.invalidate(_pedidoBase(pedidoId)))),
      data: (b) {
        if (b == null) return Scaffold(appBar: AppBar(), body: const EstadoVazio(icone: Symbols.receipt_long_rounded, titulo: 'Pedido não encontrado'));
        final p = ref.watch(_pedidoAoVivo(b)).value ?? b;
        return _Conteudo(p: p);
      },
    );
  }
}

class _Conteudo extends ConsumerStatefulWidget {
  const _Conteudo({required this.p});
  final Pedido p;

  @override
  ConsumerState<_Conteudo> createState() => _ConteudoState();
}

class _ConteudoState extends ConsumerState<_Conteudo> {
  bool _ocupado = false;

  Pedido get p => widget.p;

  Future<void> _acao(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cancelar() async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Por que você quer cancelar?', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final m in const ['Resolvi de outra forma', 'Demorou demais', 'Pedi por engano', 'Outro motivo'])
            ListTile(title: Text(m), onTap: () => Navigator.pop(ctx, m)),
        ]),
      ),
    );
    if (motivo == null) return;
    await _acao(() async {
      await ref.read(pedidosRepo).cancelar(p.id, motivo: motivo);
      ref.invalidate(pedidosClienteProvider);
    });
  }

  Future<void> _compartilhar() => _acao(() async {
        final token = await ref.read(pedidosRepo).compartilhar(p.id);
        final config = await ref.read(configProvider.future);
        final base = (config['url_acompanhamento'] as String?) ?? 'https://iservice.app/acompanhar/';
        await Clipboard.setData(ClipboardData(text: '$base$token'));
        if (mounted) mostrarMensagem(context, 'Link copiado. Envie para quem você quiser: ele vale por 12 horas.');
      });

  Future<void> _emergencia() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Symbols.emergency_rounded, color: Cores.perigo, size: 36),
        title: const Text('Ligar para a polícia (190)?'),
        content: const Text('Vamos registrar o alerta para a equipe iService e abrir a ligação para o 190.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Cores.perigo, foregroundColor: Colors.white, minimumSize: const Size(120, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ligar 190')),
        ],
      ),
    );
    if (ok != true) return;
    final pos = await lerLocalizacaoAtual().catchError((_) => null);
    ref.read(pedidosRepo).emergencia(pedidoId: p.id, lat: pos?.latitude, lng: pos?.longitude).ignore();
    await launchUrl(Uri.parse('tel:190'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    final nome = p.outraParteNome ?? '';
    final ativo = p.status == StatusPedido.aceito || p.status == StatusPedido.aCaminho || p.status == StatusPedido.emAtendimento;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${p.codigo}'),
        actions: [
          if (ativo)
            IconButton(tooltip: 'Emergência', onPressed: _emergencia, icon: const Icon(Symbols.emergency_rounded, color: Cores.perigo)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24), children: [
        _Cabecalho(p: p, aoAcabarPrazo: () => ref.invalidate(pedidosClienteProvider)),
        if (p.status == StatusPedido.aCaminho) ...[
          const SizedBox(height: 16),
          MapaAoVivo(pedidoId: p.id, nomeProfissional: nome, fotoProfissional: p.outraParteFoto),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(nome: nome, url: p.outraParteFoto, tamanho: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nome, style: t.titleSmall),
                  Text([profissao?.nome, p.especialidade].whereType<String>().join(' · '), style: t.bodySmall),
                ]),
              ),
              if (ativo || p.status == StatusPedido.solicitado || p.status == StatusPedido.concluido)
                IconButton.filledTonal(
                  tooltip: 'Conversar',
                  onPressed: () => context.push('/pedido/${p.id}/chat?nome=${Uri.encodeComponent(nome)}&foto=${Uri.encodeComponent(p.outraParteFoto ?? '')}&sub=${Uri.encodeComponent(profissao?.nome ?? '')}'),
                  icon: Badge(isLabelVisible: p.naoLidas > 0, label: Text('${p.naoLidas}'), child: const Icon(Symbols.chat_rounded)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _Linha(Symbols.schedule_rounded, 'Quando', p.quandoTexto),
        _Linha(Symbols.location_on_rounded, 'Onde', p.enderecoTexto),
        if (p.descricao.isNotEmpty) _Linha(Symbols.description_rounded, 'Descrição', p.descricao),
        if (p.precoInformado != null) _Linha(Symbols.sell_rounded, 'Preço informado', 'a partir de ${reais(p.precoInformado)}'),
        if (p.taxaUrgencia > 0) _Linha(Symbols.bolt_rounded, 'Taxa de urgência', reais(p.taxaUrgencia)),
        if (p.valorCobrado != null) _Linha(Symbols.payments_rounded, 'Valor cobrado', reais(p.valorCobrado)),
        const SizedBox(height: 16),
        if (ativo) ...[
          OutlinedButton.icon(onPressed: _ocupado ? null : _compartilhar, icon: const Icon(Symbols.share_location_rounded), label: const Text('Compartilhar acompanhamento ao vivo')),
          const SizedBox(height: 10),
        ],
        if (p.status == StatusPedido.solicitado || p.status == StatusPedido.aceito || p.status == StatusPedido.aCaminho)
          TextButton(onPressed: _ocupado ? null : _cancelar, style: TextButton.styleFrom(foregroundColor: c.perigo), child: const Text('Cancelar pedido')),
        if (p.status.encerradoSemServico) ...[
          BotaoPrincipal(rotulo: 'Escolher outro profissional', icone: Symbols.person_search_rounded, aoTocar: () => context.pushReplacement('/profissao/${p.profissaoId}')),
        ],
        if (p.status == StatusPedido.concluido) ...[
          if (!p.avaliado) BotaoPrincipal(rotulo: 'Avaliar ${primeiroNome(nome)}', icone: Symbols.star_rounded, aoTocar: () => context.push('/pedido/${p.id}/avaliar')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => _garantia(context), icon: const Icon(Symbols.verified_user_rounded), label: const Text('Garantia iService: tive um problema')),
        ],
      ]),
    );
  }

  Future<void> _garantia(BuildContext context) async {
    final texto = TextEditingController();
    String motivo = 'Serviço mal feito';
    final enviar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Garantia iService', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Conte o que aconteceu. Nossa equipe fala com você e com o profissional para resolver.', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const ['Serviço mal feito', 'Cobrança diferente', 'Dano no local', 'Comportamento', 'Outro'])
                ChoiceChip(label: Text(m), selected: motivo == m, onSelected: (_) => set(() => motivo = m)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: texto, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Descreva o problema')),
            const SizedBox(height: 12),
            BotaoPrincipal(rotulo: 'Enviar para a equipe', aoTocar: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (enviar != true || texto.text.trim().isEmpty) return;
    await _acao(() async {
      await ref.read(pedidosRepo).reclamar(p.id, motivo: motivo, descricao: texto.text.trim());
      if (mounted) mostrarMensagem(this.context, 'Recebemos sua reclamação. Vamos falar com você em até 24 horas.');
    });
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.p, required this.aoAcabarPrazo});
  final Pedido p;
  final VoidCallback aoAcabarPrazo;

  static const _etapas = [StatusPedido.solicitado, StatusPedido.aceito, StatusPedido.aCaminho, StatusPedido.emAtendimento, StatusPedido.concluido];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final nome = primeiroNome(p.outraParteNome ?? 'o profissional');
    final (titulo, texto, icone) = switch (p.status) {
      StatusPedido.solicitado => ('Aguardando $nome', 'Só $nome recebeu o seu pedido.', Symbols.hourglass_top_rounded),
      StatusPedido.aceito => ('$nome aceitou!', p.quando == QuandoPedido.combinado ? 'Horário confirmado: ${p.quandoTexto}.' : 'Ele vai sair para o seu endereço em breve.', Symbols.thumb_up_rounded),
      StatusPedido.aCaminho => ('$nome está a caminho', 'Fique de olho no chat.', Symbols.directions_car_rounded),
      StatusPedido.emAtendimento => ('Em atendimento', '$nome chegou e começou o serviço.', Symbols.construction_rounded),
      StatusPedido.concluido => ('Serviço concluído', 'Obrigado por usar o iService!', Symbols.task_alt_rounded),
      StatusPedido.recusado => ('$nome não pode atender agora', 'O pedido foi encerrado e não foi enviado a mais ninguém. Escolha outro profissional.', Symbols.event_busy_rounded),
      StatusPedido.expirado => ('$nome não respondeu a tempo', 'O pedido foi encerrado. Escolha outro profissional recomendado.', Symbols.timer_off_rounded),
      StatusPedido.cancelado => ('Pedido cancelado', 'Nenhuma cobrança foi feita.', Symbols.cancel_rounded),
    };
    final idx = _etapas.indexOf(p.status);
    final ruim = p.status.encerradoSemServico;
    return Column(children: [
      const SizedBox(height: 8),
      Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: ruim ? c.perigoSuave : (p.status == StatusPedido.concluido ? c.sucessoSuave : c.acaoSuave), shape: BoxShape.circle),
        child: Icon(icone, size: 42, color: ruim ? c.perigo : (p.status == StatusPedido.concluido ? c.sucesso : c.acaoTexto)),
      ),
      const SizedBox(height: 12),
      Text(titulo, style: t.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(texto, style: t.bodyMedium?.copyWith(color: c.textoSuave), textAlign: TextAlign.center),
      if (p.status == StatusPedido.solicitado) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioPilula)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.timer_rounded, size: 18, color: c.alerta),
            const SizedBox(width: 6),
            Text('Resposta em até ', style: t.labelMedium?.copyWith(color: c.alerta)),
            ContagemRegressiva(ate: p.responderAte, estilo: t.labelLarge?.copyWith(color: c.alerta), aoAcabar: aoAcabarPrazo),
          ]),
        ),
      ],
      if (!ruim) ...[
        const SizedBox(height: 20),
        Row(children: [
          for (var i = 0; i < _etapas.length; i++) ...[
            Expanded(
              child: Column(children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(color: i <= idx ? c.acao : c.linha, borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(height: 6),
                Text(_etapas[i].rotulo.replaceFirst('Aguardando resposta', 'Solicitado'), style: t.labelSmall?.copyWith(color: i <= idx ? c.acaoTexto : c.textoSuave, fontSize: 10), textAlign: TextAlign.center),
              ]),
            ),
            if (i < _etapas.length - 1) const SizedBox(width: 4),
          ],
        ]),
      ],
    ]);
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.icone, this.rotulo, this.valor);
  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 20, color: context.cores.textoSuave),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: t.bodySmall),
            Text(valor, style: t.bodyMedium),
          ]),
        ),
      ]),
    );
  }
}
