import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

class TelaAbertura extends StatelessWidget {
  const TelaAbertura({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: Cores.fundoMarca(escurecer: .7),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LogoIService(tamanho: 40, claro: true),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Cores.laranja, borderRadius: BorderRadius.circular(8)),
                child: const Text('PROFISSIONAL', style: TextStyle(color: Cores.azulEscuro, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12)),
              ),
              const SizedBox(height: 40),
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
            ]),
          ),
        ),
      );
}

/// "Mais trabalho, mais conquistas": chamada para novos profissionais.
class TelaBoasVindas extends StatelessWidget {
  const TelaBoasVindas({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const vantagens = [
      (Symbols.near_me_rounded, 'Clientes perto de você', 'Pedidos só da sua área de atendimento.'),
      (Symbols.sell_rounded, 'Você define o preço', 'Sem leilão nem disputa de preço.'),
      (Symbols.money_off_rounded, 'Grátis no lançamento', 'Sem mensalidade nem comissão por enquanto.'),
      (Symbols.emoji_events_rounded, 'Bom trabalho aparece', 'Os mais bem avaliados ficam no topo.'),
    ];
    return Scaffold(
      body: FundoMarca(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Medidas.margemTela),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LogoIService(tamanho: 24, claro: true),
              const Spacer(),
              Text('Mais trabalho,\nmais conquistas.', style: t.displaySmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 10),
              Text('Receba pedidos de clientes de Brasília e do Entorno direto no celular.', style: t.bodyLarge?.copyWith(color: Colors.white70)),
              const SizedBox(height: 28),
              for (final (icone, titulo, texto) in vantagens)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Cores.laranja.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icone, color: Cores.laranja),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(titulo, style: t.titleSmall?.copyWith(color: Colors.white)),
                        Text(texto, style: t.bodySmall?.copyWith(color: Colors.white70)),
                      ]),
                    ),
                  ]),
                ),
              const Spacer(),
              BotaoPrincipal(rotulo: 'Quero me cadastrar', aoTocar: () => context.push('/cadastro/1')),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                onPressed: () => context.go('/entrar'),
                child: const Text('Já tenho cadastro'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
