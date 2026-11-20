import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../estado.dart';

/// Recebimentos pelo app: a conta no Asaas, o que está a caminho e os repasses.
class TelaRecebimentos extends ConsumerWidget {
  const TelaRecebimentos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(recebimentosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recebimentos')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recebimentosProvider),
        child: r.when(
          loading: () => const Carregando(),
          error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(recebimentosProvider)),
          data: (d) => ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24), children: [
            if (!d.ativo) const _EmBreve() else ...[
              _Conta(d: d),
              const SizedBox(height: 16),
              _Valores(d: d),
              const TituloSecao(titulo: 'Repasses'),
              if (d.itens.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Os pagamentos dos seus pedidos aparecem aqui.',
                      style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                )
              else
                Card(
                  child: Column(children: [
                    for (final (i, it) in d.itens.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                      _Item(it: it),
                    ],
                  ]),
                ),
            ],
            const TituloSecao(titulo: 'Como funciona'),
            _ComoFunciona(taxa: d.taxaServicoPct),
          ]),
        ),
      ),
    );
  }
}

class _EmBreve extends StatelessWidget {
  const _EmBreve();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Symbols.schedule_rounded, color: c.acaoTexto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pagamento pelo app em breve', style: t.titleSmall),
              const SizedBox(height: 4),
              Text('Quando ligarmos, você recebe aqui uma conta no seu nome para os pagamentos dos serviços. '
                  'Avisamos antes, pelo app e por e-mail.', style: t.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Situação da conta de recebimento e o próximo passo.
class _Conta extends StatelessWidget {
  const _Conta({required this.d});
  final Recebimentos d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final (icone, cor, fundo, titulo, texto) = switch ((d.contaStatus, d.contaSituacao)) {
      (null, _) || ('pendente', _) => (
          Symbols.hourglass_top_rounded, c.acaoTexto, c.acaoSuave, 'Criando a sua conta',
          'Estamos abrindo a sua conta de recebimento no Asaas, no seu nome e CPF. Leva alguns minutos.'),
      ('falhou', _) => (
          Symbols.error_rounded, c.perigo, c.perigoSuave, 'Não conseguimos criar a sua conta',
          'Confira se o seu nome, CPF, nascimento e endereço estão certos em Meus dados. Tentamos de novo sozinhos.'),
      (_, 'aprovada') => (
          Symbols.verified_rounded, c.sucesso, c.sucessoSuave, 'Conta de recebimento aprovada',
          'Os pagamentos dos seus serviços caem nela. Para sacar, use o app do Asaas (Pix para a sua conta de banco).'),
      (_, 'recusada') => (
          Symbols.report_rounded, c.perigo, c.perigoSuave, 'Envie o documento de novo',
          'O Asaas não aprovou um documento. Toque abaixo e envie de novo, com a foto nítida e sem cortes.'),
      (_, 'em_analise') => (
          Symbols.manage_search_rounded, c.alerta, c.alertaSuave, 'Documentos em análise',
          'O Asaas está conferindo os seus documentos. Costuma levar poucos minutos e, no máximo, 2 dias úteis.'),
      _ => (
          Symbols.mark_email_unread_rounded, c.alerta, c.alertaSuave, 'Ative a sua conta',
          'Envie um documento com foto e uma selfie para liberar os recebimentos. O Asaas também mandou um e-mail para você.'),
    };
    final link = d.linkDocumentos;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(Medidas.raioCartao)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icone, color: cor, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: t.titleSmall?.copyWith(color: cor)),
              const SizedBox(height: 4),
              Text(texto, style: t.bodySmall),
            ]),
          ),
        ]),
        if (link != null && !d.contaAprovada) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            icon: const Icon(Symbols.photo_camera_rounded),
            label: const Text('Enviar documento e selfie'),
          ),
        ],
      ]),
    );
  }
}

class _Valores extends StatelessWidget {
  const _Valores({required this.d});
  final Recebimentos d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget mini(String rotulo, double v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(reais(v), style: t.titleSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(rotulo, style: t.labelSmall?.copyWith(color: Colors.white70)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: Cores.fundoMarca(raio: BorderRadius.circular(Medidas.raioCartao)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('A receber', style: t.labelLarge?.copyWith(color: Colors.white70)),
        const SizedBox(height: 4),
        Text(reais(d.aReceber), style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        Text('Já pago pelo cliente. Cai na sua conta quando você conclui o serviço.',
            style: t.bodySmall?.copyWith(color: Colors.white70)),
        const SizedBox(height: 16),
        Row(children: [
          mini('Aguardando o cliente', d.aguardandoCliente),
          mini('Recebido no mês', d.recebidoMes),
        ]),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.it});
  final Recebimento it;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final cor = switch (it.status) {
      'liberado' => c.sucesso,
      'estornado' || 'cancelado' => c.textoSuave,
      'aguardando' || 'falhou' => c.alerta,
      _ => c.acaoTexto,
    };
    final titulo = [it.servico, if (it.complemento) 'complemento'].whereType<String>().join(' · ');
    return ListTile(
      title: Text(titulo.isEmpty ? 'Serviço' : titulo, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if ((it.cliente ?? '').isNotEmpty) it.cliente!, dataCurta(it.data), it.rotulo].join(' · '),
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(reais(it.valor),
          style: t.titleSmall?.copyWith(
              color: cor, decoration: it.status == 'estornado' || it.status == 'cancelado' ? TextDecoration.lineThrough : null)),
      onTap: () => context.push('/pedido/${it.pedidoId}'),
    );
  }
}

class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona({required this.taxa});
  final int taxa;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final passos = [
      (Symbols.payments_rounded, 'O cliente paga pelo app, com Pix ou cartão, logo depois que você aceita o pedido. Você só sai quando o pagamento cai.'),
      (Symbols.lock_rounded, 'O valor fica guardado com segurança até o serviço ser concluído.'),
      (Symbols.account_balance_wallet_rounded, 'Ao concluir, o seu valor inteiro (preço, deslocamento e acréscimos) vai para a sua conta.'),
      (Symbols.percent_rounded, 'A taxa de serviço de $taxa% é paga pelo cliente, por fora do seu preço. Você não paga nada.'),
      (Symbols.undo_rounded, 'Pedido cancelado antes do serviço: o cliente recebe o dinheiro de volta.'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(children: [
          for (final (icone, texto) in passos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icone, size: 20, color: c.acaoTexto),
                const SizedBox(width: 12),
                Expanded(child: Text(texto, style: t.bodyMedium)),
              ]),
            ),
        ]),
      ),
    );
  }
}
