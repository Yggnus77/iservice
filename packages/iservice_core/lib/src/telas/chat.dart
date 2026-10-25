import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../widgets/componentes.dart';

final _mensagensProvider = StreamProvider.autoDispose.family<List<Mensagem>, String>((ref, pedidoId) => ref.read(chatRepo).mensagens(pedidoId));

/// Conversa do pedido, em tempo real, igual nos dois apps.
class TelaChat extends ConsumerStatefulWidget {
  const TelaChat({super.key, required this.pedidoId, required this.nomeOutro, this.fotoOutro, this.subtitulo});
  final String pedidoId;
  final String nomeOutro;
  final String? fotoOutro;
  final String? subtitulo;

  @override
  ConsumerState<TelaChat> createState() => _TelaChatState();
}

class _TelaChatState extends ConsumerState<TelaChat> {
  final _texto = TextEditingController();
  bool _enviando = false;

  static const _rapidas = ['Estou a caminho', 'Cheguei', 'Pode me passar o ponto de referência?', 'Obrigado!'];

  Future<void> _enviar([String? pronta]) async {
    final t = (pronta ?? _texto.text).trim();
    if (t.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await ref.read(chatRepo).enviar(widget.pedidoId, t);
      if (pronta == null) _texto.clear();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = ref.watch(usuarioIdProvider);
    final msgs = ref.watch(_mensagensProvider(widget.pedidoId));
    ref.listen(_mensagensProvider(widget.pedidoId), (_, prox) {
      if (prox.value?.any((m) => m.autorId != eu && m.lidaEm == null) ?? false) {
        ref.read(chatRepo).marcarLidas(widget.pedidoId);
      }
    });
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(nome: widget.nomeOutro, url: widget.fotoOutro, tamanho: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.nomeOutro, style: t.titleSmall),
              if (widget.subtitulo != null) Text(widget.subtitulo!, style: t.bodySmall),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: msgs.when(
            loading: () => const Carregando(),
            error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(_mensagensProvider(widget.pedidoId))),
            data: (lista) => lista.isEmpty
                ? const EstadoVazio(icone: Symbols.chat_rounded, titulo: 'Nenhuma mensagem ainda', texto: 'Combine os detalhes do serviço por aqui. Para sua segurança, mantenha a conversa no app.')
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: lista.length,
                    itemBuilder: (_, i) {
                      final m = lista[lista.length - 1 - i];
                      final minha = m.autorId == eu;
                      return Align(
                        alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            color: minha ? c.acao : Theme.of(context).colorScheme.surface,
                            border: minha ? null : Border.all(color: c.linha),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(minha ? 18 : 4),
                              bottomRight: Radius.circular(minha ? 4 : 18),
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(m.texto, style: t.bodyMedium?.copyWith(color: minha ? c.textoNaAcao : null)),
                            const SizedBox(height: 2),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(hora(m.criadaEm), style: t.labelSmall?.copyWith(color: minha ? c.textoNaAcao.withValues(alpha: .75) : c.textoSuave)),
                              if (minha) ...[
                                const SizedBox(width: 4),
                                Icon(m.lidaEm == null ? Symbols.done_rounded : Symbols.done_all_rounded, size: 14, color: c.textoNaAcao.withValues(alpha: .8)),
                              ],
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final r in _rapidas)
              Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(r), onPressed: () => _enviar(r))),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _texto,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escreva uma mensagem',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Medidas.raioPilula)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Medidas.raioPilula), borderSide: BorderSide(color: c.linha)),
                  ),
                  onSubmitted: (_) => _enviar(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: _enviando ? null : _enviar,
                style: IconButton.styleFrom(backgroundColor: c.acao, foregroundColor: c.textoNaAcao, minimumSize: const Size(48, 48)),
                icon: const Icon(Symbols.send_rounded, fill: 1),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
