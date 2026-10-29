import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Avaliação com nota, comentário e fotos do serviço.
class TelaAvaliar extends ConsumerStatefulWidget {
  const TelaAvaliar({super.key, required this.pedidoId});
  final String pedidoId;

  @override
  ConsumerState<TelaAvaliar> createState() => _TelaAvaliarState();
}

class _TelaAvaliarState extends ConsumerState<TelaAvaliar> {
  int _nota = 0;
  final _comentario = TextEditingController();
  final _fotos = <String>[];
  bool _enviando = false;

  static const _rotulos = ['', 'Péssimo', 'Ruim', 'Regular', 'Bom', 'Excelente!'];

  Future<void> _adicionarFoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (img == null) return;
    setState(() => _enviando = true);
    try {
      final arq = ref.read(arquivosRepo);
      final caminho = await arq.enviar(bucket: 'avaliacoes', nome: '${widget.pedidoId}/${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: await img.readAsBytes());
      setState(() => _fotos.add(arq.urlPublica('avaliacoes', caminho)));
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      await ref.read(pedidosRepo).avaliar(widget.pedidoId, _nota, comentario: _comentario.text, fotos: _fotos);
      ref.invalidate(pedidosClienteProvider);
      if (!mounted) return;
      mostrarMensagem(context, 'Obrigado! Sua avaliação ajuda outros clientes.');
      context.go('/pedidos');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Avaliar serviço')),
      body: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: c.sucessoSuave, shape: BoxShape.circle),
            child: Icon(Symbols.task_alt_rounded, size: 44, color: c.sucesso),
          ),
        ),
        const SizedBox(height: 12),
        Text('Como foi o serviço?', style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(child: Estrelas(valor: _nota.toDouble(), tamanho: 40, aoEscolher: (n) => setState(() => _nota = n))),
        const SizedBox(height: 4),
        Text(_rotulos[_nota], style: t.titleSmall?.copyWith(color: c.acaoTexto), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _comentario,
          minLines: 3,
          maxLines: 6,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Conte como foi sua experiência (opcional)'),
        ),
        const SizedBox(height: 8),
        Text('Fotos do serviço (opcional)', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in _fotos)
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(f, width: 72, height: 72, fit: BoxFit.cover)),
          if (_fotos.length < 4)
            InkWell(
              onTap: _enviando ? null : _adicionarFoto,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(border: Border.all(color: c.linha, width: 1.5), borderRadius: BorderRadius.circular(10)),
                child: Icon(Symbols.add_a_photo_rounded, color: c.acaoTexto),
              ),
            ),
        ]),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 12),
          child: BotaoPrincipal(rotulo: 'Enviar avaliação', carregando: _enviando, aoTocar: _nota == 0 ? null : _enviar),
        ),
      ),
    );
  }
}
