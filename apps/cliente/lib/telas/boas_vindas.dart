import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Fundos da entrada: um deitado para o navegador no computador e um em pé para o celular.
/// As duas imagens já trazem o logo, por isso a tela não repete o logo por cima.
const _fundoWeb = AssetImage('assets/fundo-web.jpg');
const _fundoCelular = AssetImage('assets/fundo-celular.jpg');

/// Abertura enquanto o app confere o login.
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
            child: Image(image: deitada ? _fundoWeb : _fundoCelular, fit: BoxFit.cover, alignment: deitada ? Alignment.centerRight : Alignment.topCenter),
          ),
          Align(
            alignment: const Alignment(0, .78),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Cores.azulEscuro.withValues(alpha: .15), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cores.azul)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pagina {
  const _Pagina(this.titulo, this.texto, this.icone, this.cor);
  final String titulo;
  final String texto;
  final IconData icone;
  final Color cor;
}

const _paginas = [
  _Pagina('Encontre', 'Profissionais de confiança perto de você, em Brasília e no Entorno.', Symbols.location_on_rounded, Cores.azul),
  _Pagina('Escolha', 'Compare avaliações, especialidades e preços. Os mais bem avaliados aparecem primeiro.', Symbols.verified_user_rounded, Cores.verde),
  _Pagina('Contrate', 'O pedido vai só para quem você escolheu. Resposta em até 5 minutos.', Symbols.bolt_rounded, Cores.laranja),
  _Pagina('Avalie', 'Sua avaliação ajuda outros clientes e valoriza o bom profissional.', Symbols.star_rounded, Cores.estrela),
];

/// Boas-vindas: Encontre, Escolha, Contrate e Avalie.
/// No computador os 4 passos aparecem juntos; no celular, um por vez.
class TelaBoasVindas extends StatelessWidget {
  const TelaBoasVindas({super.key});

  @override
  Widget build(BuildContext context) => const EntradaWeb(
    imagem: _fundoWeb,
    fimDoLogo: 400,
    fimDasPessoas: 1010,
    cartao: _CartaoWeb(),
    estreito: EntradaCelular(imagem: _fundoCelular, cartao: _CartaoCelular()),
  );
}

/// Cartão do computador: os 4 passos de uma vez.
class _CartaoWeb extends StatelessWidget {
  const _CartaoWeb();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'O profissional certo, mais perto de você.',
          style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text('Profissionais de confiança em Brasília e no Entorno, com avaliações reais.', style: t.bodyMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 18),
        for (var i = 0; i < _paginas.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                for (final n in [i, i + 1]) ...[
                  Expanded(
                    child: ItemEntrada(
                      icone: _paginas[n].icone,
                      texto: '${n + 1}. ${_paginas[n].titulo}',
                      cor: _paginas[n].cor == Cores.azul ? Cores.azulEscuroModo : _paginas[n].cor,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: BotaoPrincipal(rotulo: 'Criar minha conta', aoTocar: () => context.push('/cadastro/1')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                onPressed: () => context.go('/entrar'),
                child: const Text('Já tenho conta'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cartão do celular: um passo por vez, deslizando.
class _CartaoCelular extends StatefulWidget {
  const _CartaoCelular();

  @override
  State<_CartaoCelular> createState() => _CartaoCelularState();
}

class _CartaoCelularState extends State<_CartaoCelular> {
  final _paginador = PageController();
  int _atual = 0;

  @override
  void dispose() {
    _paginador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ultima = _atual == _paginas.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _paginador,
            itemCount: _paginas.length,
            onPageChanged: (i) => setState(() => _atual = i),
            itemBuilder: (_, i) {
              final p = _paginas[i];
              return Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: p.cor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: p.cor.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Icon(p.icone, size: 28, fill: 1, color: p.cor == Cores.azul ? Colors.white : Cores.azulEscuro),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${i + 1}. ${p.titulo}',
                    style: t.titleLarge?.copyWith(color: Cores.texto, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.texto,
                    style: t.bodyMedium?.copyWith(color: Cores.textoSuave),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _paginas.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _atual ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == _atual ? Cores.laranja : Cores.linha, borderRadius: BorderRadius.circular(8)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: BotaoPrincipal(
            rotulo: ultima ? 'Criar minha conta' : 'Continuar',
            aoTocar: () => ultima ? context.push('/cadastro/1') : _paginador.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Cores.azul),
          onPressed: () => context.go('/entrar'),
          child: const Text('Já tenho conta'),
        ),
      ],
    );
  }
}
