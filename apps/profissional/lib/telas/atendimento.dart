import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../estado.dart';

final _pedidoBase = FutureProvider.autoDispose.family<Pedido?, String>((ref, id) async {
  final lista = await ref.read(pedidosRepo).meus(papel: 'profissional');
  return lista.where((p) => p.id == id).firstOrNull;
});

final _pedidoAoVivo = StreamProvider.autoDispose.family<Pedido, Pedido>((ref, base) => ref.read(pedidosRepo).acompanhar(base));

/// Atendimento do pedido pelo profissional: a caminho, iniciar, concluir com o valor, chat e cancelar.
class TelaAtendimento extends ConsumerWidget {
  const TelaAtendimento({super.key, required this.pedidoId});
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
      ref.invalidate(pedidosProProvider);
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _avancar(StatusPedido s) => _acao(() => ref.read(pedidosRepo).avancar(p.id, s));

  Future<void> _responder(bool aceitar) => _acao(() async {
        final r = await ref.read(pedidosRepo).responder(p.id, aceitar: aceitar, motivo: aceitar ? null : 'Recusado pelo profissional');
        if (r.status == StatusPedido.expirado && mounted) mostrarMensagem(context, 'O tempo para responder acabou.');
      });

  Future<void> _concluir() async {
    final r = await showModalBottomSheet<(double, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FolhaConcluir(sugestao: p.precoInformado == null ? null : p.precoInformado! + p.taxaUrgencia),
    );
    if (r == null) return;
    await _acao(() => ref.read(pedidosRepo).avancar(p.id, StatusPedido.concluido, valor: r.$1, formaPagamento: r.$2));
    if (mounted) mostrarMensagem(context, 'Serviço concluído. Bom trabalho!');
  }

  Future<void> _cancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar este atendimento?'),
        content: const Text('O cliente é avisado na hora. Cancelamentos baixam sua confiabilidade e a sua posição nas buscas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Cores.perigo), child: const Text('Cancelar atendimento')),
        ],
      ),
    );
    if (ok == true) await _acao(() => ref.read(pedidosRepo).cancelar(p.id, motivo: 'Cancelado pelo profissional'));
  }

  Future<void> _emergencia() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Symbols.emergency_rounded, color: Cores.perigo, size: 36),
        title: const Text('Ligar para a polícia (190)?'),
        content: const Text('Vamos registrar o alerta para a equipe iService e abrir a ligação para o 190.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.perigo, foregroundColor: Colors.white, minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ligar 190'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final pos = await lerLocalizacaoAtual().catchError((_) => null);
    ref.read(pedidosRepo).emergencia(pedidoId: p.id, lat: pos?.latitude, lng: pos?.longitude).ignore();
    await launchUrl(Uri.parse('tel:190'));
  }

  void _abrirRota() {
    final q = Uri.encodeComponent(p.enderecoTexto);
    launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q'), mode: LaunchMode.externalApplication);
  }

  void _abrirChat() {
    final nome = Uri.encodeComponent(p.outraParteNome ?? '');
    final foto = Uri.encodeComponent(p.outraParteFoto ?? '');
    final sub = Uri.encodeComponent('Pedido ${p.codigo}');
    context.push('/pedido/${p.id}/chat?nome=$nome&foto=$foto&sub=$sub');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    final ativo = p.status == StatusPedido.aceito || p.status == StatusPedido.aCaminho || p.status == StatusPedido.emAtendimento;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido ${p.codigo}'),
        actions: [
          if (ativo) IconButton(tooltip: 'Emergência', onPressed: _emergencia, icon: const Icon(Symbols.emergency_rounded, color: Cores.perigo)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24), children: [
        _Etapas(status: p.status),
        TransmissorPosicao(pedidoId: p.id, ativo: p.status == StatusPedido.aCaminho),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto, tamanho: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.outraParteNome ?? 'Cliente', style: t.titleMedium),
                  const SizedBox(height: 4),
                  EtiquetaStatus(status: p.status),
                ]),
              ),
              if (ativo)
                IconButton.filledTonal(
                  tooltip: 'Conversar',
                  onPressed: _abrirChat,
                  icon: Badge(isLabelVisible: p.naoLidas > 0, label: Text('${p.naoLidas}'), child: const Icon(Symbols.chat_rounded)),
                ),
            ]),
          ),
        ),
        const TituloSecao(titulo: 'Serviço'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.especialidade ?? profissao?.nome ?? '', style: t.titleMedium),
              if (p.descricao.isNotEmpty) ...[const SizedBox(height: 6), Text(p.descricao, style: t.bodyMedium)],
              const Divider(height: 24),
              _Linha(icone: p.quando == QuandoPedido.agora ? Symbols.bolt_rounded : Symbols.schedule_rounded, texto: p.quandoTexto),
              _Linha(icone: Symbols.location_on_rounded, texto: p.enderecoTexto, acao: ativo ? ('Rota', _abrirRota) : null),
              _Linha(
                icone: Symbols.payments_rounded,
                texto: p.valorCobrado != null
                    ? 'Cobrado: ${reais(p.valorCobrado)}'
                    : [
                        p.precoInformado == null ? 'Preço combinado no local' : 'A partir de ${reais(p.precoInformado)}',
                        if (p.taxaUrgencia > 0) '+ ${reais(p.taxaUrgencia)} de urgência',
                      ].join(' '),
              ),
            ]),
          ),
        ),
        if (p.status == StatusPedido.solicitado) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Symbols.timer_rounded, size: 18, color: c.alerta),
            const SizedBox(width: 6),
            Text('Responda em ', style: t.bodyMedium),
            ContagemRegressiva(ate: p.responderAte, estilo: t.titleSmall?.copyWith(color: c.alerta), aoAcabar: () => ref.invalidate(_pedidoBase(p.id))),
          ]),
        ],
        if (p.status.encerradoSemServico) ...[
          const SizedBox(height: 16),
          Text(
            switch (p.status) {
              StatusPedido.recusado => 'Você recusou este pedido.',
              StatusPedido.expirado => 'O prazo de resposta acabou e o pedido foi encerrado.',
              _ => 'Este pedido foi cancelado.',
            },
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        if (p.status == StatusPedido.aceito || p.status == StatusPedido.aCaminho) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _ocupado ? null : _cancelar,
              style: TextButton.styleFrom(foregroundColor: c.perigo),
              child: const Text('Cancelar atendimento'),
            ),
          ),
        ],
      ]),
      bottomNavigationBar: _botoes(),
    );
  }

  Widget? _botoes() {
    final Widget? conteudo = switch (p.status) {
      StatusPedido.solicitado => Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _ocupado ? null : () => _responder(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Medidas.alturaBotao), foregroundColor: Cores.perigo),
              child: const Text('Recusar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: BotaoPrincipal(rotulo: 'Aceitar', icone: Symbols.check_rounded, carregando: _ocupado, aoTocar: () => _responder(true))),
        ]),
      StatusPedido.aceito => Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _ocupado ? null : () => _avancar(StatusPedido.emAtendimento),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Medidas.alturaBotao)),
              child: const Text('Já estou lá'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: BotaoPrincipal(rotulo: 'Estou a caminho', icone: Symbols.directions_car_rounded, carregando: _ocupado, aoTocar: () => _avancar(StatusPedido.aCaminho)),
          ),
        ]),
      StatusPedido.aCaminho => BotaoPrincipal(rotulo: 'Cheguei, iniciar serviço', icone: Symbols.handyman_rounded, carregando: _ocupado, aoTocar: () => _avancar(StatusPedido.emAtendimento)),
      StatusPedido.emAtendimento => BotaoPrincipal(rotulo: 'Concluir serviço', icone: Symbols.task_alt_rounded, carregando: _ocupado, aoTocar: _concluir),
      _ => null,
    };
    if (conteudo == null) return null;
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 12), child: conteudo));
  }
}

/// Linha do tempo: Aceito → A caminho → Em atendimento → Concluído.
class _Etapas extends StatelessWidget {
  const _Etapas({required this.status});
  final StatusPedido status;

  static const _ordem = [StatusPedido.aceito, StatusPedido.aCaminho, StatusPedido.emAtendimento, StatusPedido.concluido];

  @override
  Widget build(BuildContext context) {
    if (status == StatusPedido.solicitado || status.encerradoSemServico) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final atual = _ordem.indexOf(status);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        for (final (i, s) in _ordem.indexed) ...[
          if (i > 0) Expanded(child: Container(height: 3, color: i <= atual ? c.acao : c.linha)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i <= atual ? c.acao : c.superficieSuave),
              child: Icon(i < atual ? Symbols.check_rounded : Symbols.circle, size: i < atual ? 18 : 10, fill: 1, color: i <= atual ? c.textoNaAcao : c.textoSuave),
            ),
            const SizedBox(height: 4),
            SizedBox(width: 64, child: Text(s.rotulo, style: t.labelSmall, textAlign: TextAlign.center, maxLines: 2)),
          ]),
        ],
      ]),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto, this.acao});
  final IconData icone;
  final String texto;
  final (String, VoidCallback)? acao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icone, size: 18, color: c.textoSuave),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: t.bodyMedium)),
        if (acao != null) TextButton.icon(onPressed: acao!.$2, icon: const Icon(Symbols.directions_rounded, size: 18), label: Text(acao!.$1)),
      ]),
    );
  }
}

class _FolhaConcluir extends StatefulWidget {
  const _FolhaConcluir({this.sugestao});
  final double? sugestao;

  @override
  State<_FolhaConcluir> createState() => _FolhaConcluirState();
}

class _FolhaConcluirState extends State<_FolhaConcluir> {
  late final _valor = TextEditingController(text: widget.sugestao?.toStringAsFixed(0));
  String _forma = 'pix';

  static const _formas = [('pix', 'Pix', Symbols.qr_code_2_rounded), ('dinheiro', 'Dinheiro', Symbols.payments_rounded), ('cartao', 'Cartão', Symbols.credit_card_rounded)];

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  void _confirmar() {
    final v = double.tryParse(_valor.text.replaceAll('.', '').replaceAll(',', '.'));
    if (v == null || v < 0) {
      mostrarMensagem(context, 'Informe o valor cobrado.');
      return;
    }
    Navigator.pop(context, (v, _forma));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Concluir serviço', style: t.titleLarge),
        const SizedBox(height: 4),
        Text('Informe quanto o cliente pagou. Esse valor entra no seu relatório de ganhos.', style: t.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _valor,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: t.headlineSmall,
          decoration: const InputDecoration(labelText: 'Valor cobrado', prefixText: 'R\$ '),
        ),
        const SizedBox(height: 16),
        Text('Forma de pagamento', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final (v, rotulo, icone) in _formas)
            ChoiceChip(avatar: Icon(icone, size: 18), label: Text(rotulo), selected: _forma == v, onSelected: (_) => setState(() => _forma = v)),
        ]),
        const SizedBox(height: 20),
        BotaoPrincipal(rotulo: 'Confirmar conclusão', aoTocar: _confirmar),
      ]),
    );
  }
}
