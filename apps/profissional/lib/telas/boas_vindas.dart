import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Fundos da entrada: um deitado para o navegador no computador e um em pé para o celular.
/// As duas imagens já trazem o logo, por isso a tela não repete o logo por cima.
const _fundoWeb = AssetImage('assets/fundo-web.jpg');
const _fundoCelular = AssetImage('assets/fundo-celular.jpg');

/// Na imagem do celular (1086 × 1448) o logo fica no meio e os dois profissionais à direita.
const _focoCelular = Alignment(.15, -1);

class TelaAbertura extends StatelessWidget {
  const TelaAbertura({super.key});

  @override
  Widget build(BuildContext context) {
    final tamanho = MediaQuery.sizeOf(context);
    final deitada = kIsWeb && tamanho.width >= 900 && tamanho.width > tamanho.height;
    return Scaffold(
      backgroundColor: const Color(0xFFEAF1FB),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image(image: deitada ? _fundoWeb : _fundoCelular, fit: BoxFit.cover, alignment: deitada ? Alignment.centerRight : _focoCelular),
          ),
          const Align(alignment: Alignment(0, .78), child: _Carregando()),
        ],
      ),
    );
  }
}

class _Carregando extends StatelessWidget {
  const _Carregando();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Cores.azulEscuro.withValues(alpha: .15), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cores.laranja)),
  );
}

const _vantagens = [
  (Symbols.near_me_rounded, 'Clientes perto de você'),
  (Symbols.sell_rounded, 'Você define o preço'),
  (Symbols.money_off_rounded, 'Grátis no lançamento'),
  (Symbols.emoji_events_rounded, 'Bom trabalho aparece'),
];

/// "Mais trabalho, mais conquistas": chamada para novos profissionais.
class TelaBoasVindas extends StatelessWidget {
  const TelaBoasVindas({super.key});

  @override
  Widget build(BuildContext context) => const EntradaWeb(
    imagem: _fundoWeb,
    cartao: _Cartao(escuro: true),
    estreito: EntradaCelular(imagem: _fundoCelular, alinhamento: _focoCelular, cartao: _Cartao(escuro: false)),
  );
}

/// Texto e botões da entrada. [escuro]: cartão azul-escuro do computador; senão, cartão branco do celular.
class _Cartao extends StatelessWidget {
  const _Cartao({required this.escuro});
  final bool escuro;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final texto = escuro ? Colors.white : Cores.texto;
    final suave = escuro ? Colors.white70 : Cores.textoSuave;
    final icone = escuro ? Cores.laranja : Cores.laranjaTexto;
    final entrar = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: texto,
        side: BorderSide(color: escuro ? Colors.white38 : Cores.bordaControle),
      ),
      onPressed: () => context.go('/entrar'),
      child: const Text('Já tenho cadastro'),
    );
    final cadastrar = BotaoPrincipal(rotulo: 'Quero me cadastrar', aoTocar: () => context.push('/cadastro/1'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(8)),
          child: const Text(
            'PROFISSIONAL',
            style: TextStyle(color: Cores.azulEscuro, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Mais trabalho, mais conquistas.',
          style: t.headlineSmall?.copyWith(color: texto, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text('Receba pedidos de clientes de Brasília e do Entorno direto no celular.', style: t.bodyMedium?.copyWith(color: suave)),
        const SizedBox(height: 18),
        if (!escuro)
          for (final (simbolo, frase) in _vantagens)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ItemEntrada(icone: simbolo, texto: frase, cor: icone, corTexto: texto),
            )
        else
          for (var i = 0; i < _vantagens.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (final (simbolo, frase) in _vantagens.sublist(i, i + 2)) ...[
                    Expanded(
                      child: ItemEntrada(icone: simbolo, texto: frase, cor: icone, corTexto: texto),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
        const SizedBox(height: 8),
        if (escuro)
          Row(
            children: [
              Expanded(child: cadastrar),
              const SizedBox(width: 10),
              Expanded(child: entrar),
            ],
          )
        else ...[
          SizedBox(width: double.infinity, child: cadastrar),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: entrar),
        ],
      ],
    );
  }
}
