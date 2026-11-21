import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

final _minhaNota = FutureProvider.autoDispose<ResumoCliente?>((ref) => ref.read(pedidosRepo).minhaNotaCliente());

/// Perfil do cliente: dados, endereços, fidelidade, acessibilidade e ajuda.
class TelaPerfil extends ConsumerWidget {
  const TelaPerfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider);
    final config = ref.watch(configProvider).value ?? const {};
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final minhaNota = ref.watch(_minhaNota).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: perfil.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(meuPerfilProvider)),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          final zap = (config['whatsapp_suporte'] as String?) ?? '';
          return ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 32), children: [
            Row(children: [
              Avatar(nome: p.nome, url: p.fotoUrl, tamanho: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nome, style: t.titleLarge),
                  Text(p.email ?? '', style: t.bodySmall),
                  if (p.telefone != null) Text(telefoneFormatado(p.telefone!), style: t.bodySmall),
                  if (minhaNota != null && minhaNota.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Symbols.star_rounded, size: 16, fill: 1, color: Cores.estrela),
                        const SizedBox(width: 2),
                        Text('${nota(minhaNota.nota)} · sua nota como cliente', style: t.labelMedium),
                      ]),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Card(
              color: c.alertaSuave,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Symbols.loyalty_rounded, size: 36, color: Cores.laranja, fill: 1),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.pontos} pontos', style: t.titleMedium),
                      Text('Ganhe pontos a cada serviço e quando um amigo contratar pela sua indicação.', style: t.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (p.codigoIndicacao != null)
              Card(
                child: ListTile(
                  leading: Icon(Symbols.redeem_rounded, color: c.acaoTexto),
                  title: Text('Seu código: ${p.codigoIndicacao}', style: t.titleSmall),
                  subtitle: const Text('Toque para copiar e enviar a um amigo.'),
                  onTap: () {
                    unawaited(Clipboard.setData(ClipboardData(text: 'Baixe o iService e use meu código ${p.codigoIndicacao} no cadastro!')));
                    mostrarMensagem(context, 'Convite copiado.');
                  },
                ),
              ),
            const SizedBox(height: 16),
            Text('Conta', style: t.titleSmall?.copyWith(color: c.textoSuave)),
            const SizedBox(height: 6),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Symbols.badge_rounded),
                  title: const Text('Meus dados'),
                  subtitle: p.exclusaoSolicitadaEm == null ? null : Text('Exclusão agendada', style: TextStyle(color: c.perigo)),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/meus-dados'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.location_on_rounded),
                  title: const Text('Meus endereços'),
                  subtitle: Text('${p.enderecos.length} salvo${p.enderecos.length == 1 ? '' : 's'}'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/enderecos'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.notifications_rounded),
                  title: const Text('Notificações'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/notificacoes'),
                ),
                const Divider(indent: 56),
                SwitchListTile(
                  secondary: const Icon(Symbols.format_size_rounded),
                  title: const Text('Letra grande'),
                  subtitle: const Text('Aumenta os textos do app.'),
                  value: p.letraGrande,
                  onChanged: (v) async {
                    try {
                      await ref.read(contaRepo).definirLetraGrande(v);
                      ref.invalidate(meuPerfilProvider);
                    } catch (e) {
                      if (context.mounted) mostrarErro(context, e);
                    }
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Ajuda', style: t.titleSmall?.copyWith(color: c.textoSuave)),
            const SizedBox(height: 6),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Symbols.help_rounded),
                  title: const Text('Central de Ajuda'),
                  subtitle: Text('Dúvidas frequentes · ${textoHorarioAtendimento(config)}'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/ajuda'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: Icon(Symbols.forum_rounded, color: c.acaoTexto),
                  title: const Text('Falar com o suporte'),
                  subtitle: const Text('Chat com a equipe do iService'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/suporte'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.support_agent_rounded, color: Cores.verdeTexto),
                  title: const Text('Falar com o iService no WhatsApp'),
                  trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                  onTap: zap.isEmpty
                      ? () => mostrarMensagem(context, 'O atendimento pelo WhatsApp começa no lançamento.')
                      : () => launchUrl(Uri.parse('https://wa.me/$zap'), mode: LaunchMode.externalApplication),
                ),
                const Divider(indent: 56),
                const ListTile(leading: Icon(Symbols.verified_user_rounded), title: Text('Garantia iService'), subtitle: Text('Problemas com um serviço? Abra pelo pedido em até 30 dias.')),
              ]),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: c.perigo),
              onPressed: () => sairDaConta(ref),
              icon: const Icon(Symbols.logout_rounded),
              label: const Text('Sair'),
            ),
          ]);
        },
      ),
    );
  }
}
