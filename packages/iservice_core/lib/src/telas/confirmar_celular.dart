import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../util/validacao.dart';
import '../widgets/componentes.dart';

Future<void> abrirConfirmacaoCelular(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TelaConfirmarCelular()));

/// Confirma o celular com um código de 6 dígitos enviado por SMS.
class TelaConfirmarCelular extends ConsumerStatefulWidget {
  const TelaConfirmarCelular({super.key});

  @override
  ConsumerState<TelaConfirmarCelular> createState() => _TelaConfirmarCelularState();
}

class _TelaConfirmarCelularState extends ConsumerState<TelaConfirmarCelular> {
  final _mascara = mascaraTelefone();
  late final _tel = TextEditingController(text: telefoneFormatado(ref.read(meuPerfilProvider).value?.telefone ?? ''));
  final _codigo = TextEditingController();
  bool _enviado = false;
  bool _carregando = false;
  int _espera = 0;
  Timer? _relogio;

  String get _digitos => soDigitos(_tel.text);

  Future<void> _enviar() async {
    final erro = Validar.telefone(_tel.text);
    if (erro != null) {
      mostrarMensagem(context, erro);
      return;
    }
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).enviarCodigoCelular(_digitos);
      if (!mounted) return;
      setState(() {
        _enviado = true;
        _espera = 60;
      });
      _relogio?.cancel();
      _relogio = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _espera <= 1) t.cancel();
        if (mounted) setState(() => _espera = _espera > 0 ? _espera - 1 : 0);
      });
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _confirmar() async {
    if (_codigo.text.trim().length != 6) {
      mostrarMensagem(context, 'Digite os 6 números do SMS.');
      return;
    }
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).confirmarCodigoCelular(_digitos, _codigo.text);
      ref.invalidate(meuPerfilProvider);
      if (!mounted) return;
      mostrarMensagem(context, 'Celular confirmado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _tel.dispose();
    _codigo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar celular')),
      body: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
        Icon(Symbols.sms_rounded, size: 48, color: c.acaoTexto),
        const SizedBox(height: 12),
        Text('Vamos mandar um código por SMS', style: t.titleLarge),
        const SizedBox(height: 6),
        Text('Com o celular confirmado, cliente e profissional conseguem se falar com segurança.', style: t.bodyMedium),
        const SizedBox(height: 20),
        TextField(
          controller: _tel,
          enabled: !_enviado,
          keyboardType: TextInputType.phone,
          inputFormatters: [_mascara],
          autofillHints: const [AutofillHints.telephoneNumberNational],
          decoration: const InputDecoration(labelText: 'Celular com DDD'),
        ),
        if (_enviado) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _codigo,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofillHints: const [AutofillHints.oneTimeCode],
            style: t.headlineSmall?.copyWith(letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'Código de 6 números', counterText: ''),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: 16),
          BotaoPrincipal(rotulo: 'Confirmar', carregando: _carregando, aoTocar: _confirmar),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: _espera > 0 || _carregando ? null : _enviar,
              child: Text(_espera > 0 ? 'Reenviar em ${_espera}s' : 'Reenviar código'),
            ),
            TextButton(onPressed: _carregando ? null : () => setState(() => _enviado = false), child: const Text('Trocar número')),
          ]),
        ] else ...[
          const SizedBox(height: 20),
          BotaoPrincipal(rotulo: 'Enviar código', icone: Symbols.send_rounded, carregando: _carregando, aoTocar: _enviar),
        ],
      ]),
    );
  }
}
