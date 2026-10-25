import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Abertura enquanto o app confere o login.
class TelaAbertura extends StatelessWidget {
  const TelaAbertura({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: Cores.gradienteMarca),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LogoIService(tamanho: 40, claro: true),
              SizedBox(height: 12),
              Text('O profissional certo, mais perto de você.', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 40),
              SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
            ]),
          ),
        ),
      );
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
  _Pagina('Contrate', 'O pedido vai só para quem você escolheu. Resposta em até 10 minutos.', Symbols.bolt_rounded, Cores.laranja),
  _Pagina('Avalie', 'Sua avaliação ajuda outros clientes e valoriza o bom profissional.', Symbols.star_rounded, Cores.estrela),
];

/// Boas-vindas em 4 passos: Encontre, Escolha, Contrate e Avalie.
class TelaBoasVindas extends StatefulWidget {
  const TelaBoasVindas({super.key});

  @override
  State<TelaBoasVindas> createState() => _TelaBoasVindasState();
}

class _TelaBoasVindasState extends State<TelaBoasVindas> {
  final _paginador = PageController();
  int _atual = 0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final ultima = _atual == _paginas.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              const LogoIService(tamanho: 22),
              const Spacer(),
              TextButton(onPressed: () => context.go('/entrar'), child: const Text('Entrar')),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _paginador,
              itemCount: _paginas.length,
              onPageChanged: (i) => setState(() => _atual = i),
              itemBuilder: (_, i) {
                final p = _paginas[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [p.cor.withValues(alpha: .22), p.cor.withValues(alpha: .04)]),
                      ),
                      child: Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(color: p.cor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.cor.withValues(alpha: .4), blurRadius: 30, offset: const Offset(0, 12))]),
                          child: Icon(p.icone, size: 60, fill: 1, color: p.cor == Cores.azul ? Colors.white : Cores.azulEscuro),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text('${i + 1}. ${p.titulo}', style: t.displaySmall, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(p.texto, style: t.bodyLarge?.copyWith(color: c.textoSuave), textAlign: TextAlign.center),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _paginas.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _atual ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == _atual ? c.acao : c.linha, borderRadius: BorderRadius.circular(8)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(children: [
              BotaoPrincipal(
                rotulo: ultima ? 'Criar minha conta' : 'Continuar',
                aoTocar: () => ultima
                    ? context.push('/cadastro/1')
                    : _paginador.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.go('/entrar'), child: const Text('Já tenho conta')),
            ]),
          ),
        ]),
      ),
    );
  }
}
