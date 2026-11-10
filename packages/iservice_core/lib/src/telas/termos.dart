import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../estado/provedores.dart';
import '../push.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../widgets/componentes.dart';

/// "Li e aceito os Termos de Uso e a Política de Privacidade.", com os dois
/// nomes tocáveis abrindo as páginas do site.
class TextoAceiteTermos extends StatelessWidget {
  const TextoAceiteTermos({super.key, this.estilo});
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    final base = estilo ?? Theme.of(context).textTheme.bodySmall;
    final link = base?.copyWith(
      color: context.cores.acaoTexto,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: context.cores.acaoTexto,
    );
    InlineSpan ligacao(String texto, String url) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(texto, style: link),
            ),
          ),
        );
    return Text.rich(
      TextSpan(style: base, children: [
        const TextSpan(text: 'Li e aceito os '),
        ligacao('Termos de Uso', ConfigIService.urlTermos),
        const TextSpan(text: ' e a '),
        ligacao('Política de Privacidade', ConfigIService.urlPrivacidade),
        const TextSpan(text: ' do iService.'),
      ]),
    );
  }
}

/// Pede o aceite dos Termos a quem ainda não aceitou a versão em vigor: quem
/// entrou com o Google, contas antigas e todos depois de uma mudança nos textos.
class TelaAceitarTermos extends ConsumerStatefulWidget {
  const TelaAceitarTermos({super.key});

  @override
  ConsumerState<TelaAceitarTermos> createState() => _TelaAceitarTermosState();
}

class _TelaAceitarTermosState extends ConsumerState<TelaAceitarTermos> {
  bool _aceite = false;
  bool _carregando = false;

  Future<void> _continuar() async {
    if (!_aceite) {
      mostrarMensagem(context, 'Para continuar, marque que leu e aceita os Termos de Uso e a Política de Privacidade.');
      return;
    }
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).aceitarTermos();
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final jaAceitou = ref.watch(meuPerfilProvider).value?.termosVersao != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
          const SizedBox(height: 24),
          Icon(Symbols.verified_user_rounded, size: 48, color: context.cores.acaoTexto),
          const SizedBox(height: 12),
          Text(jaAceitou ? 'Atualizamos nossos Termos' : 'Antes de continuar', style: t.headlineSmall),
          const SizedBox(height: 6),
          Text(
            jaAceitou
                ? 'Os Termos de Uso e a Política de Privacidade do iService mudaram. Leia e confirme para seguir usando o app.'
                : 'Para usar o iService, leia e aceite os Termos de Uso e a Política de Privacidade. '
                    'Eles explicam as regras do app e como cuidamos dos seus dados.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _aceite,
            onChanged: (v) => setState(() => _aceite = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: TextoAceiteTermos(estilo: t.bodyMedium),
          ),
          const SizedBox(height: 20),
          BotaoPrincipal(rotulo: 'Aceitar e continuar', carregando: _carregando, aoTocar: _continuar),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _carregando ? null : () => sairDaConta(ref),
            child: const Text('Agora não, sair da conta'),
          ),
        ]),
      ),
    );
  }
}
