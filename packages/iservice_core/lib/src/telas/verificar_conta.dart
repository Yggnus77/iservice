import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../dados/repositorios.dart';
import '../estado/provedores.dart';
import '../push.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../util/validacao.dart';
import '../widgets/componentes.dart';

enum _Etapa { escolha, email, sms, pronto }

/// Logo depois de criar a conta: a pessoa escolhe receber o código por e-mail
/// ou por SMS e só continua o cadastro depois de digitar o código.
/// No fim mostra o aviso de conta confirmada, com a marca; o botão Continuar
/// recarrega o perfil e as rotas seguem para o próximo passo.
class TelaVerificarConta extends ConsumerStatefulWidget {
  const TelaVerificarConta({super.key});

  @override
  ConsumerState<TelaVerificarConta> createState() => _TelaVerificarContaState();
}

class _TelaVerificarContaState extends ConsumerState<TelaVerificarConta> {
  var _etapa = _Etapa.escolha;
  var _peloSms = false;
  final _mascara = mascaraTelefone();
  late final _tel = TextEditingController(text: telefoneFormatado(ref.read(meuPerfilProvider).value?.telefone ?? ''));
  final _codigo = TextEditingController();
  bool _enviado = false;
  bool _carregando = false;
  int _espera = 0;
  Timer? _relogio;
  String? _emailEnviado;

  MeuPerfil? get _perfil => ref.read(meuPerfilProvider).value;

  @override
  void dispose() {
    _relogio?.cancel();
    _tel.dispose();
    _codigo.dispose();
    super.dispose();
  }

  void _contar() {
    setState(() => _espera = 60);
    _relogio?.cancel();
    _relogio = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _espera <= 1) t.cancel();
      if (mounted) setState(() => _espera = _espera > 0 ? _espera - 1 : 0);
    });
  }

  void _escolher(_Etapa etapa) {
    setState(() {
      _etapa = etapa;
      _enviado = false;
      _codigo.clear();
    });
    if (etapa == _Etapa.email) unawaited(_enviarEmail());
  }

  Future<void> _enviarEmail() async {
    setState(() => _carregando = true);
    try {
      final email = await ref.read(contaRepo).pedirCodigoEmail();
      if (!mounted) return;
      setState(() {
        _emailEnviado = email;
        _enviado = true;
      });
      _contar();
    } catch (e) {
      if (!mounted) return;
      // Já confirmado (por exemplo, em outro aparelho): segue em frente.
      if (e is ErroIService && e.codigo == 'ja_verificado') {
        setState(() => _etapa = _Etapa.pronto);
        return;
      }
      mostrarErro(context, e);
      // Pedido repetido antes de 1 minuto: o código anterior ainda vale.
      if (e is ErroIService && e.codigo == 'aguarde') setState(() => _enviado = true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _enviarSms() async {
    final erro = Validar.telefone(_tel.text);
    if (erro != null) {
      mostrarMensagem(context, erro);
      return;
    }
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).enviarCodigoCelular(soDigitos(_tel.text));
      if (!mounted) return;
      setState(() => _enviado = true);
      _contar();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _confirmar() async {
    final codigo = soDigitos(_codigo.text);
    if (codigo.length != 6) {
      mostrarMensagem(context, 'Digite os 6 números do código.');
      return;
    }
    setState(() => _carregando = true);
    try {
      final conta = ref.read(contaRepo);
      if (_etapa == _Etapa.email) {
        final ok = await conta.confirmarCodigoEmail(codigo);
        if (!ok) {
          if (mounted) mostrarMensagem(context, 'Código incorreto. Confira o e-mail e tente de novo.');
          return;
        }
      } else {
        await conta.confirmarCodigoCelular(soDigitos(_tel.text), codigo);
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _peloSms = _etapa == _Etapa.sms;
        _etapa = _Etapa.pronto;
      });
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _sair() async {
    await sairDaConta(ref);
  }

  @override
  Widget build(BuildContext context) {
    // O celular do cadastro preenche o campo assim que o perfil chega.
    ref.listen(meuPerfilProvider, (_, novo) {
      final tel = novo.value?.telefone;
      if (_tel.text.isEmpty && tel != null) _tel.text = telefoneFormatado(tel);
    });
    final conteudo = switch (_etapa) {
      _Etapa.escolha => _escolha(context),
      _Etapa.email || _Etapa.sms => _codigoTela(context),
      _Etapa.pronto => _pronto(context),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (podeVoltar, _) {
        if (!podeVoltar && (_etapa == _Etapa.email || _etapa == _Etapa.sms) && !_carregando) {
          setState(() => _etapa = _Etapa.escolha);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(_etapa), child: conteudo)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topo(BuildContext context, {bool voltar = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          if (voltar)
            IconButton(
              tooltip: 'Voltar',
              onPressed: _carregando ? null : () => setState(() => _etapa = _Etapa.escolha),
              icon: const Icon(Symbols.arrow_back_rounded),
            )
          else
            const SizedBox(width: 12),
          const LogoIService(tamanho: 22),
          const Spacer(),
          TextButton(onPressed: _carregando ? null : _sair, child: const Text('Sair')),
        ]),
      );

  Widget _escolha(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final p = ref.watch(meuPerfilProvider).value;
    final email = p?.email ?? '';
    final tel = p?.telefone ?? '';
    return ListView(padding: EdgeInsets.zero, children: [
      _topo(context),
      Padding(
        padding: const EdgeInsets.all(Medidas.margemTela),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.acaoSuave, borderRadius: BorderRadius.circular(20)),
            child: Icon(Symbols.verified_user_rounded, size: 34, fill: 1, color: c.acaoTexto),
          ),
          const SizedBox(height: 18),
          Text('Verifique sua conta', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Para a segurança de clientes e profissionais, confirme que é você. Escolha como quer receber o código de 6 números.',
            style: t.bodyMedium?.copyWith(color: c.textoSuave),
          ),
          const SizedBox(height: 24),
          _Opcao(
            icone: Symbols.mail_rounded,
            titulo: 'Por e-mail',
            texto: email.isEmpty ? 'Enviamos o código para o seu e-mail' : 'Enviamos o código para ${emailMascarado(email)}',
            aoTocar: email.isEmpty ? null : () => _escolher(_Etapa.email),
          ),
          const SizedBox(height: 12),
          _Opcao(
            icone: Symbols.sms_rounded,
            titulo: 'Por SMS',
            texto: tel.isEmpty ? 'Enviamos o código para o seu celular' : 'Enviamos o código para ${telefoneMascarado(tel)}',
            aoTocar: () => _escolher(_Etapa.sms),
          ),
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.lock_rounded, size: 18, color: c.textoSuave),
            const SizedBox(width: 8),
            Expanded(
              child: Text('A equipe do iService nunca pede esse código. Não compartilhe com ninguém.',
                  style: t.bodySmall?.copyWith(color: c.textoSuave)),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _codigoTela(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final email = _etapa == _Etapa.email;
    final destino = email ? (_emailEnviado ?? _perfil?.email ?? '') : _tel.text;
    final campoCodigo = TextField(
      controller: _codigo,
      autofocus: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofillHints: const [AutofillHints.oneTimeCode],
      style: t.headlineSmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
      decoration: const InputDecoration(labelText: 'Código de 6 números', counterText: ''),
      onChanged: (v) {
        if (v.length == 6 && !_carregando) unawaited(_confirmar());
      },
      onSubmitted: (_) => _confirmar(),
    );
    return ListView(padding: EdgeInsets.zero, children: [
      _topo(context, voltar: true),
      Padding(
        padding: const EdgeInsets.all(Medidas.margemTela),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Icon(email ? Symbols.mark_email_unread_rounded : Symbols.sms_rounded, size: 48, color: c.acaoTexto),
          const SizedBox(height: 12),
          Text(email ? 'Confira seu e-mail' : 'Confirme pelo SMS', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          if (email)
            Text(
              _enviado ? 'Enviamos um código para $destino. Ele vale por 15 minutos. Confira também a caixa de spam.' : 'Enviando o código para $destino…',
              style: t.bodyMedium?.copyWith(color: c.textoSuave),
              textAlign: TextAlign.center,
            )
          else
            Text(
              _enviado ? 'Enviamos um código por SMS para $destino.' : 'Confira o número do seu celular. Vamos mandar um código por SMS.',
              style: t.bodyMedium?.copyWith(color: c.textoSuave),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 20),
          if (!email) ...[
            TextField(
              controller: _tel,
              enabled: !_enviado,
              keyboardType: TextInputType.phone,
              inputFormatters: [_mascara],
              autofillHints: const [AutofillHints.telephoneNumberNational],
              decoration: const InputDecoration(labelText: 'Celular com DDD'),
            ),
            const SizedBox(height: 16),
          ],
          if (_enviado) ...[
            campoCodigo,
            const SizedBox(height: 16),
            BotaoPrincipal(rotulo: 'Confirmar', carregando: _carregando, aoTocar: _confirmar),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, children: [
              TextButton(
                onPressed: _espera > 0 || _carregando ? null : (email ? _enviarEmail : _enviarSms),
                child: Text(_espera > 0 ? 'Reenviar em ${_espera}s' : 'Reenviar código'),
              ),
              if (!email)
                TextButton(onPressed: _carregando ? null : () => setState(() => _enviado = false), child: const Text('Trocar número')),
              TextButton(
                onPressed: _carregando ? null : () => _escolher(email ? _Etapa.sms : _Etapa.email),
                child: Text(email ? 'Prefiro por SMS' : 'Prefiro por e-mail'),
              ),
            ]),
          ] else if (email)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            BotaoPrincipal(rotulo: 'Enviar código', icone: Symbols.send_rounded, carregando: _carregando, aoTocar: _enviarSms),
        ]),
      ),
    ]);
  }

  Widget _pronto(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(Medidas.margemTela),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const LogoIService(tamanho: 30),
              const SizedBox(height: 36),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .6, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (_, v, filho) => Transform.scale(scale: v, child: filho),
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(color: c.sucessoSuave, shape: BoxShape.circle),
                  child: Icon(Symbols.check_circle_rounded, size: 72, fill: 1, color: c.sucesso),
                ),
              ),
              const SizedBox(height: 28),
              Text(_peloSms ? 'Celular confirmado!' : 'E-mail confirmado!',
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'Sua conta no iService está verificada. Agora é só terminar o cadastro.',
                style: t.bodyLarge?.copyWith(color: c.textoSuave),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              BotaoPrincipal(
                rotulo: 'Continuar',
                icone: Symbols.arrow_forward_rounded,
                aoTocar: () => ref.invalidate(meuPerfilProvider),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({required this.icone, required this.titulo, required this.texto, required this.aoTocar});
  final IconData icone;
  final String titulo;
  final String texto;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioCartao), side: BorderSide(color: c.linha)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.acaoSuave, borderRadius: BorderRadius.circular(14)),
              child: Icon(icone, color: c.acaoTexto, fill: 1),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(texto, style: t.bodySmall?.copyWith(color: c.textoSuave)),
              ]),
            ),
            Icon(Symbols.chevron_right_rounded, color: c.textoSuave),
          ]),
        ),
      ),
    );
  }
}

/// "jo•••@gmail.com": mostra só o começo do e-mail.
String emailMascarado(String email) {
  final i = email.indexOf('@');
  if (i <= 0) return email;
  final nome = email.substring(0, i);
  final visivel = nome.length <= 2 ? nome.substring(0, 1) : nome.substring(0, 2);
  return '$visivel•••${email.substring(i)}';
}

/// "(61) 9 ••••-1234": mostra só o DDD e o fim do número.
String telefoneMascarado(String tel) {
  final d = soDigitos(tel);
  if (d.length < 10) return telefoneFormatado(tel);
  return '(${d.substring(0, 2)}) ${d.length == 11 ? '${d[2]} ' : ''}••••-${d.substring(d.length - 4)}';
}
