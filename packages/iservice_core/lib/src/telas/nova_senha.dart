import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/validacao.dart';
import '../widgets/componentes.dart';

/// Quando a pessoa abre o link de "Esqueci minha senha", mostra a tela de nova
/// senha por cima de tudo. Vai no `builder` do MaterialApp.
class VigiaRecuperacaoSenha extends ConsumerStatefulWidget {
  const VigiaRecuperacaoSenha({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<VigiaRecuperacaoSenha> createState() => _VigiaRecuperacaoSenhaState();
}

class _VigiaRecuperacaoSenhaState extends ConsumerState<VigiaRecuperacaoSenha> {
  StreamSubscription<AuthState>? _assinatura;
  bool _recuperando = false;

  @override
  void initState() {
    super.initState();
    _assinatura = ref.read(contaRepo).mudancas.listen((e) {
      if (e.event == AuthChangeEvent.passwordRecovery && mounted) setState(() => _recuperando = true);
    });
  }

  @override
  void dispose() {
    _assinatura?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _recuperando ? TelaNovaSenha(aoConcluir: () => setState(() => _recuperando = false)) : widget.child;
}

class TelaNovaSenha extends ConsumerStatefulWidget {
  const TelaNovaSenha({super.key, required this.aoConcluir});
  final VoidCallback aoConcluir;

  @override
  ConsumerState<TelaNovaSenha> createState() => _TelaNovaSenhaState();
}

class _TelaNovaSenhaState extends ConsumerState<TelaNovaSenha> {
  final _form = GlobalKey<FormState>();
  final _senha = TextEditingController();
  final _senha2 = TextEditingController();
  bool _carregando = false;

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).definirNovaSenha(_senha.text);
      if (!mounted) return;
      mostrarMensagem(context, 'Senha trocada. Use a nova senha para entrar no celular.');
      widget.aoConcluir();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  void dispose() {
    _senha.dispose();
    _senha2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
            const SizedBox(height: 24),
            Icon(Symbols.lock_reset_rounded, size: 48, color: context.cores.acaoTexto),
            const SizedBox(height: 12),
            Text('Crie uma nova senha', style: t.headlineSmall),
            const SizedBox(height: 6),
            Text('Mínimo de 8 caracteres, com letras e números.', style: t.bodyMedium),
            const SizedBox(height: 20),
            TextFormField(
              controller: _senha,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nova senha'),
              validator: Validar.senha,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _senha2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repita a nova senha'),
              validator: (v) => v == _senha.text ? null : 'As senhas não são iguais.',
            ),
            const SizedBox(height: 20),
            BotaoPrincipal(rotulo: 'Salvar nova senha', carregando: _carregando, aoTocar: _salvar),
          ]),
        ),
      ),
    );
  }
}
