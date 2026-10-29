import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Cadastro enviado: aguardando a equipe conferir os documentos.
class TelaAnalise extends ConsumerWidget {
  const TelaAnalise({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(meuPerfilProvider).value?.profissional;
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final recusado = pro?.status == StatusCadastro.recusado;
    final suspenso = pro?.status == StatusCadastro.suspenso;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(meuPerfilProvider);
            ref.invalidate(pendenciasProvider);
          },
          child: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(color: recusado || suspenso ? c.perigoSuave : c.acaoSuave, shape: BoxShape.circle),
                child: Icon(
                  recusado ? Symbols.error_rounded : (suspenso ? Symbols.block_rounded : Symbols.hourglass_top_rounded),
                  size: 52,
                  color: recusado || suspenso ? c.perigo : c.acaoTexto,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              recusado ? 'Seu cadastro precisa de ajustes' : (suspenso ? 'Conta suspensa' : 'Cadastro em análise'),
              style: t.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              recusado
                  ? (pro?.motivoStatus ?? 'Confira os documentos e envie de novo.')
                  : suspenso
                      ? 'Fale com o suporte para entender o motivo.'
                      : 'Nossa equipe confere seus documentos e sua selfie em até 2 dias úteis. Avisamos por aqui assim que for aprovado.',
              style: t.bodyMedium?.copyWith(color: c.textoSuave),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (!recusado && !suspenso)
              Card(
                child: Column(children: [
                  for (final (feito, texto) in const [(true, 'Dados pessoais e endereço'), (true, 'Profissões, especialidades e preços'), (true, 'Documento e selfie enviados'), (false, 'Conferência pela equipe iService')])
                    ListTile(
                      leading: Icon(feito ? Symbols.check_circle_rounded : Symbols.pending_rounded, fill: 1, color: feito ? c.sucesso : c.alerta),
                      title: Text(texto),
                    ),
                ]),
              ),
            const SizedBox(height: 20),
            if (recusado) BotaoPrincipal(rotulo: 'Corrigir cadastro', aoTocar: () => context.go('/cadastro/5')),
            TextButton(onPressed: () => sairDaConta(ref), child: const Text('Sair')),
          ]),
        ),
      ),
    );
  }
}
