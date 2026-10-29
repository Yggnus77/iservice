import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../widgets/componentes.dart';

const _motivos = [
  'Comportamento inadequado ou assédio',
  'Golpe ou cobrança indevida',
  'Perfil falso ou dados errados',
  'Não apareceu ou abandonou o serviço',
  'Serviço mal feito ou dano',
  'Outro motivo',
];

/// Botão de menu "Denunciar" para a barra do perfil ou do pedido.
class BotaoDenunciar extends ConsumerWidget {
  const BotaoDenunciar({super.key, required this.alvoId, required this.alvoNome, this.pedidoId, this.corIcone});
  final String alvoId;
  final String alvoNome;
  final String? pedidoId;
  final Color? corIcone;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<void>(
        tooltip: 'Mais opções',
        icon: Icon(Symbols.more_vert_rounded, color: corIcone),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => abrirDenuncia(context, alvoId: alvoId, alvoNome: alvoNome, pedidoId: pedidoId),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.flag_rounded, color: Cores.perigo),
              title: Text('Denunciar'),
            ),
          ),
        ],
      );
}

Future<void> abrirDenuncia(BuildContext context, {required String alvoId, required String alvoNome, String? pedidoId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaDenuncia(alvoId: alvoId, alvoNome: alvoNome, pedidoId: pedidoId),
    );

class _FolhaDenuncia extends ConsumerStatefulWidget {
  const _FolhaDenuncia({required this.alvoId, required this.alvoNome, this.pedidoId});
  final String alvoId;
  final String alvoNome;
  final String? pedidoId;

  @override
  ConsumerState<_FolhaDenuncia> createState() => _FolhaDenunciaState();
}

class _FolhaDenunciaState extends ConsumerState<_FolhaDenuncia> {
  String? _motivo;
  final _descricao = TextEditingController();
  bool _enviando = false;

  Future<void> _enviar() async {
    if (_motivo == null) {
      mostrarMensagem(context, 'Escolha o motivo.');
      return;
    }
    setState(() => _enviando = true);
    try {
      await ref.read(contaRepo).denunciar(alvoId: widget.alvoId, motivo: _motivo!, descricao: _descricao.text, pedidoId: widget.pedidoId);
      if (!mounted) return;
      Navigator.pop(context);
      mostrarMensagem(context, 'Denúncia enviada. A equipe iService vai analisar.');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Denunciar ${widget.alvoNome.split(' ').first}', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('A pessoa não fica sabendo quem denunciou. Em perigo, use o botão de emergência ou ligue 190.', style: t.bodySmall),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _motivo,
              onChanged: (v) => setState(() => _motivo = v),
              child: Column(children: [
                for (final m in _motivos) RadioListTile<String>(value: m, title: Text(m), contentPadding: EdgeInsets.zero, dense: true),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descricao,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Conte o que aconteceu (opcional)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Cores.perigo, foregroundColor: Colors.white),
              onPressed: _enviando ? null : _enviar,
              child: const Text('Enviar denúncia'),
            ),
          ]),
        ),
      ),
    );
  }
}
