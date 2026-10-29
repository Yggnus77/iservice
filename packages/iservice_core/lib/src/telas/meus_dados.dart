import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../widgets/componentes.dart';

const _diasExclusao = 30;

/// Perfil > Meus dados: os dados da conta e o botão "Excluir conta"
/// (exigido pela App Store e pelo Google Play).
class TelaMeusDados extends ConsumerWidget {
  const TelaMeusDados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider);
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Scaffold(
      appBar: AppBar(title: const Text('Meus dados')),
      body: perfil.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(meuPerfilProvider)),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          final cpf = p.cpf;
          return ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 32), children: [
            if (p.exclusaoSolicitadaEm != null) ...[
              AvisoExclusaoAgendada(solicitadaEm: p.exclusaoSolicitadaEm!),
              const SizedBox(height: 16),
            ],
            Card(
              child: Column(children: [
                _Dado(Symbols.person_rounded, 'Nome', p.nome),
                _Dado(Symbols.mail_rounded, 'E-mail', p.email ?? '—'),
                _Dado(Symbols.call_rounded, 'Celular', p.telefone == null ? '—' : telefoneFormatado(p.telefone!)),
                // CPF mascarado: só os 3 primeiros e os 2 últimos dígitos.
                _Dado(Symbols.badge_rounded, 'CPF', cpf == null || cpf.length != 11 ? '—' : '${cpf.substring(0, 3)}.***.***-${cpf.substring(9)}'),
                _Dado(Symbols.cake_rounded, 'Nascimento', p.nascimento == null ? '—' : dataCurta(p.nascimento!)),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Para corrigir algum dado, fale com o suporte.', style: t.bodySmall),
            const SizedBox(height: 32),
            Text('Excluir conta', style: t.titleSmall?.copyWith(color: c.perigo)),
            const SizedBox(height: 6),
            Text(
              'Sua conta sai do ar na hora e seus dados pessoais são apagados em até $_diasExclusao dias. '
              'Os registros dos serviços feitos ficam guardados sem os seus dados, como manda a lei.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            if (p.exclusaoSolicitadaEm == null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: c.perigo, side: BorderSide(color: c.perigo), minimumSize: const Size.fromHeight(Medidas.alturaBotao)),
                onPressed: () => _confirmarExclusao(context, ref),
                icon: const Icon(Symbols.delete_forever_rounded),
                label: const Text('Excluir conta'),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _confirmarExclusao(BuildContext context, WidgetRef ref) async {
    final data = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FolhaExcluir(),
    );
    if (data == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Symbols.check_circle_rounded, size: 36),
        title: const Text('Exclusão solicitada'),
        content: Text('Sua conta saiu do ar. Os dados serão apagados até ${dataCurta(data)}. '
            'Se mudar de ideia, é só entrar de novo antes dessa data e cancelar.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
      ),
    );
  }
}

class _Dado extends StatelessWidget {
  const _Dado(this.icone, this.rotulo, this.valor);
  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icone, color: context.cores.textoSuave),
        title: Text(rotulo, style: Theme.of(context).textTheme.bodySmall),
        subtitle: Text(valor, style: Theme.of(context).textTheme.bodyLarge),
      );
}

class _FolhaExcluir extends ConsumerStatefulWidget {
  const _FolhaExcluir();

  @override
  ConsumerState<_FolhaExcluir> createState() => _FolhaExcluirState();
}

class _FolhaExcluirState extends ConsumerState<_FolhaExcluir> {
  final _senha = TextEditingController();
  String? _motivo;
  bool _ciente = false;
  bool _ocultar = true;
  bool _enviando = false;

  static const _motivos = ['Não uso mais o app', 'Tive um problema com um serviço', 'Preocupação com meus dados', 'Outro motivo'];

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _excluir() async {
    if (_senha.text.isEmpty) {
      mostrarMensagem(context, 'Digite sua senha para confirmar.');
      return;
    }
    setState(() => _enviando = true);
    try {
      final data = await ref.read(contaRepo).solicitarExclusao(senha: _senha.text, motivo: _motivo);
      if (mounted) Navigator.pop(context, data);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Padding(
      padding: EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Excluir sua conta?', style: t.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Você sai do app, deixa de aparecer para outras pessoas e perde seus pontos, favoritos e histórico. '
            'Pedidos em andamento precisam ser concluídos ou cancelados antes.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _motivo,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            items: [for (final m in _motivos) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _motivo = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _senha,
            obscureText: _ocultar,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Sua senha',
              suffixIcon: IconButton(
                tooltip: _ocultar ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () => setState(() => _ocultar = !_ocultar),
                icon: Icon(_ocultar ? Symbols.visibility_rounded : Symbols.visibility_off_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ciente,
            onChanged: (v) => setState(() => _ciente = v ?? false),
            title: Text('Entendo que meus dados serão apagados em até $_diasExclusao dias.', style: t.bodyMedium),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.perigo, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(Medidas.alturaBotao)),
            onPressed: !_ciente || _enviando ? null : _excluir,
            child: _enviando
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Excluir minha conta'),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: _enviando ? null : () => Navigator.pop(context), child: const Text('Voltar')),
        ]),
      ),
    );
  }
}

/// Cartão de "exclusão agendada", com o botão para cancelar.
class AvisoExclusaoAgendada extends ConsumerStatefulWidget {
  const AvisoExclusaoAgendada({super.key, required this.solicitadaEm});
  final DateTime solicitadaEm;

  @override
  ConsumerState<AvisoExclusaoAgendada> createState() => _AvisoExclusaoAgendadaState();
}

class _AvisoExclusaoAgendadaState extends ConsumerState<AvisoExclusaoAgendada> {
  bool _cancelando = false;

  Future<void> _cancelar() async {
    setState(() => _cancelando = true);
    try {
      await ref.read(contaRepo).cancelarExclusao();
      ref.invalidate(meuPerfilProvider);
      if (mounted) mostrarMensagem(context, 'Exclusão cancelada. Sua conta continua ativa.');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final data = widget.solicitadaEm.add(const Duration(days: _diasExclusao));
    return Card(
      color: c.perigoSuave,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.schedule_rounded, color: c.perigo),
            const SizedBox(width: 8),
            Expanded(child: Text('Exclusão agendada', style: t.titleSmall?.copyWith(color: c.perigo))),
          ]),
          const SizedBox(height: 6),
          Text('Seus dados serão apagados até ${dataCurta(data)}. Enquanto isso, sua conta não aparece para ninguém.', style: t.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _cancelando ? null : _cancelar, child: Text(_cancelando ? 'Cancelando…' : 'Cancelar exclusão')),
        ]),
      ),
    );
  }
}

/// Ao entrar com uma exclusão pendente, pergunta uma vez se quer manter a conta.
Future<void> perguntarSeMantemConta(BuildContext context, WidgetRef ref, MeuPerfil perfil) async {
  final pedida = perfil.exclusaoSolicitadaEm;
  if (pedida == null) return;
  final data = pedida.add(const Duration(days: _diasExclusao));
  final manter = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sua conta está para ser excluída'),
      content: Text('Você pediu para excluir a conta. Os dados serão apagados até ${dataCurta(data)}. Quer manter a conta?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar com a exclusão')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Manter minha conta')),
      ],
    ),
  );
  if (manter == true) {
    try {
      await ref.read(contaRepo).cancelarExclusao();
      ref.invalidate(meuPerfilProvider);
      if (context.mounted) mostrarMensagem(context, 'Que bom que ficou! Sua conta continua ativa.');
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  } else if (manter == false) {
    await ref.read(contaRepo).sair();
  }
}

/// Mostra [perguntarSeMantemConta] uma vez por sessão, quando o perfil carrega.
class VigiaExclusaoConta extends ConsumerStatefulWidget {
  const VigiaExclusaoConta({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<VigiaExclusaoConta> createState() => _VigiaExclusaoContaState();
}

class _VigiaExclusaoContaState extends ConsumerState<VigiaExclusaoConta> {
  String? _perguntadoPara;

  @override
  void initState() {
    super.initState();
    ref.listenManual(meuPerfilProvider, (_, prox) {
      final p = prox.value;
      if (p == null || p.exclusaoSolicitadaEm == null || _perguntadoPara == p.id) return;
      _perguntadoPara = p.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) perguntarSeMantemConta(context, ref, p);
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
