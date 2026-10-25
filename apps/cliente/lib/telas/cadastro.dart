import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';

/// Cadastro do cliente em 4 passos: dados, endereço, e-mail e senha, foto.
/// Quem já tem conta (mas não terminou) pula o passo 3.
class TelaCadastro extends ConsumerStatefulWidget {
  const TelaCadastro({super.key, required this.passo});
  final int passo;

  @override
  ConsumerState<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends ConsumerState<TelaCadastro> {
  bool _salvando = false;

  bool get _logado => ref.read(contaRepo).sessao != null;

  Future<void> _depoisDoEndereco() async {
    if (!_logado) {
      context.push('/cadastro/3');
      return;
    }
    setState(() => _salvando = true);
    try {
      await ref.read(rascunhoCadastroProvider.notifier).gravar();
      if (mounted) context.go('/cadastro/4');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _concluir() async {
    setState(() => _salvando = true);
    try {
      final pendencias = await ref.read(contaRepo).concluirCadastroCliente();
      if (!mounted) return;
      if (pendencias.isEmpty) {
        ref.invalidate(meuPerfilProvider);
        mostrarMensagem(context, 'Tudo pronto! Bem-vindo ao iService.');
      } else {
        mostrarMensagem(context, 'Falta preencher: ${pendencias.join(', ')}.');
        context.go(pendencias.contains('endereco') ? '/cadastro/2' : '/cadastro/1');
      }
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tela = switch (widget.passo) {
      1 => PassoDadosPessoais(passo: 1, total: 4, aoContinuar: () => context.push('/cadastro/2')),
      2 => PassoEndereco(passo: 2, total: 4, aoContinuar: _depoisDoEndereco),
      3 => PassoConta(
          passo: 3,
          total: 4,
          aoCriar: () => context.go('/cadastro/4'),
          aoPrecisarConfirmar: (email) => context.go('/confirmar-email?email=${Uri.encodeComponent(email)}'),
        ),
      _ => PassoFoto(passo: 4, total: 4, aoContinuar: _concluir),
    };
    return Stack(children: [
      tela,
      if (_salvando) const ColoredBox(color: Color(0x33000000), child: Carregando()),
    ]);
  }
}
