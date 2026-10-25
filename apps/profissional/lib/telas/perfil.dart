import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cadastro.dart' show EditorPrecos;

final _portfolioProvider = FutureProvider.autoDispose((ref) => ref.read(profissionalRepo).portfolio());

/// O perfil como o cliente vê (avaliações recentes vêm daqui).
final _perfilPublicoProvider = FutureProvider.autoDispose((ref) {
  final id = ref.watch(usuarioIdProvider);
  return id == null ? Future.value(null) : ref.read(buscaRepo).perfil(id);
});

/// Perfil do profissional: foto, sobre, preços, área, portfólio, avaliações, acessibilidade e ajuda.
class TelaPerfilPro extends ConsumerWidget {
  const TelaPerfilPro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider);
    final config = ref.watch(configProvider).value ?? const {};
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: perfil.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(meuPerfilProvider)),
        data: (p) {
          final pro = p?.profissional;
          if (p == null || pro == null) return const SizedBox.shrink();
          final zap = (config['whatsapp_suporte'] as String?) ?? '';
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(meuPerfilProvider);
              ref.invalidate(_portfolioProvider);
              ref.invalidate(_perfilPublicoProvider);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 32), children: [
              Row(children: [
                _FotoEditavel(nome: p.nome, url: p.fotoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.nome, style: t.titleLarge),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (pro.verificado) Selo(texto: 'Verificado', icone: Symbols.verified_rounded, cor: c.sucesso, fundo: c.sucessoSuave),
                      if (pro.totalAvaliacoes > 0) NotaCompacta(nota: pro.notaMedia, total: pro.totalAvaliacoes) else Text('Novo no iService', style: t.bodySmall),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),
              _Grupo(titulo: 'Seu trabalho', itens: [
                ListTile(
                  leading: const Icon(Symbols.badge_rounded),
                  title: const Text('Sobre você'),
                  subtitle: Text((pro.bio ?? '').trim().isEmpty ? 'Conte sua experiência aos clientes' : pro.bio!, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Symbols.edit_rounded, size: 20),
                  onTap: () => _editarSobre(context, ref, pro),
                ),
                ListTile(
                  leading: const Icon(Symbols.sell_rounded),
                  title: const Text('Especialidades e preços'),
                  subtitle: const Text('Você define o valor; mostramos a média da região.'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _TelaPrecos())),
                ),
                ListTile(
                  leading: const Icon(Symbols.radar_rounded),
                  title: const Text('Área de atendimento'),
                  subtitle: Text('Até ${pro.areaRaioKm.round()} km de onde você está'),
                  trailing: const Icon(Symbols.edit_rounded, size: 20),
                  onTap: () => _editarArea(context, ref, pro),
                ),
              ]),
              const TituloSecao(titulo: 'Portfólio (antes e depois)'),
              const _Portfolio(),
              const TituloSecao(titulo: 'Avaliações'),
              const _Avaliacoes(),
              const SizedBox(height: 16),
              _Grupo(titulo: 'Conta', itens: [
                ListTile(
                  leading: const Icon(Symbols.notifications_rounded),
                  title: const Text('Notificações'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/notificacoes'),
                ),
                SwitchListTile(
                  secondary: const Icon(Symbols.format_size_rounded),
                  title: const Text('Letra grande'),
                  subtitle: const Text('Aumenta os textos do app.'),
                  value: p.letraGrande,
                  onChanged: (v) async {
                    try {
                      await ref.read(contaRepo).definirLetraGrande(v);
                      ref.invalidate(meuPerfilProvider);
                    } catch (e) {
                      if (context.mounted) mostrarErro(context, e);
                    }
                  },
                ),
                if (p.codigoIndicacao != null)
                  ListTile(
                    leading: const Icon(Symbols.redeem_rounded),
                    title: Text('Indique colegas: ${p.codigoIndicacao}'),
                    subtitle: const Text('Toque para copiar o convite.'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: 'Trabalhe com o iService! Use meu código ${p.codigoIndicacao} no cadastro.'));
                      mostrarMensagem(context, 'Convite copiado.');
                    },
                  ),
              ]),
              const SizedBox(height: 16),
              _Grupo(titulo: 'Ajuda', itens: [
                ListTile(
                  leading: const Icon(Symbols.support_agent_rounded, color: Cores.verdeTexto),
                  title: const Text('Falar com o iService no WhatsApp'),
                  trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                  onTap: zap.isEmpty
                      ? () => mostrarMensagem(context, 'O atendimento pelo WhatsApp começa no lançamento.')
                      : () => launchUrl(Uri.parse('https://wa.me/$zap'), mode: LaunchMode.externalApplication),
                ),
                const ListTile(
                  leading: Icon(Symbols.work_rounded),
                  title: Text('Mudar de profissão'),
                  subtitle: Text('Fale com o suporte: a nova profissão passa por conferência.'),
                ),
              ]),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: c.perigo),
                onPressed: () => ref.read(contaRepo).sair(),
                icon: const Icon(Symbols.logout_rounded),
                label: const Text('Sair'),
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _editarSobre(BuildContext context, WidgetRef ref, MeuCadastroProfissional pro) async {
    final bio = TextEditingController(text: pro.bio);
    final anos = TextEditingController(text: pro.anosExperiencia?.toString());
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Sobre você', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: bio,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ex.: Eletricista há 12 anos, especialista em quadros e chuveiros. Atendo com garantia.'),
          ),
          TextField(
            controller: anos,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            decoration: const InputDecoration(labelText: 'Anos de experiência'),
          ),
          const SizedBox(height: 20),
          BotaoPrincipal(rotulo: 'Salvar', aoTocar: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(profissionalRepo).salvarSobre(bio: bio.text.trim().isEmpty ? null : bio.text.trim(), anosExperiencia: int.tryParse(anos.text));
      ref.invalidate(meuPerfilProvider);
      if (context.mounted) mostrarMensagem(context, 'Perfil atualizado.');
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  Future<void> _editarArea(BuildContext context, WidgetRef ref, MeuCadastroProfissional pro) async {
    if (pro.areaLat == null || pro.areaLng == null) {
      mostrarMensagem(context, 'Cadastre seu endereço para definir a área.');
      return;
    }
    var raio = pro.areaRaioKm;
    final novo = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Área de atendimento', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Até ${raio.round()} km do seu endereço. Pedidos de mais longe não chegam a você.', style: Theme.of(ctx).textTheme.bodySmall),
              Slider(value: raio, min: 1, max: 50, divisions: 49, label: '${raio.round()} km', onChanged: (v) => set(() => raio = v)),
              const SizedBox(height: 8),
              BotaoPrincipal(rotulo: 'Salvar', aoTocar: () => Navigator.pop(ctx, raio)),
            ]),
          ),
        ),
      ),
    );
    if (novo == null) return;
    try {
      await ref.read(profissionalRepo).definirArea(lat: pro.areaLat!, lng: pro.areaLng!, raioKm: novo.roundToDouble(), regiaoId: pro.regiaoId);
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({required this.titulo, required this.itens});
  final String titulo;
  final List<Widget> itens;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: t.titleSmall?.copyWith(color: context.cores.textoSuave)),
      const SizedBox(height: 6),
      Card(
        child: Column(children: [
          for (final (i, w) in itens.indexed) ...[if (i > 0) const Divider(indent: 56), w],
        ]),
      ),
    ]);
  }
}

class _FotoEditavel extends ConsumerStatefulWidget {
  const _FotoEditavel({required this.nome, this.url});
  final String nome;
  final String? url;

  @override
  ConsumerState<_FotoEditavel> createState() => _FotoEditavelState();
}

class _FotoEditavelState extends ConsumerState<_FotoEditavel> {
  bool _enviando = false;

  Future<void> _trocar() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (img == null) return;
    setState(() => _enviando = true);
    try {
      final arq = ref.read(arquivosRepo);
      final caminho = await arq.enviar(bucket: 'fotos', nome: 'perfil-${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: await img.readAsBytes());
      await ref.read(contaRepo).salvarFoto(arq.urlPublica('fotos', caminho));
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Semantics(
      button: true,
      label: 'Trocar foto de perfil',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _enviando ? null : _trocar,
        child: Stack(children: [
          Avatar(nome: widget.nome, url: widget.url, tamanho: 76),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: c.acao, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)),
              child: _enviando
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textoNaAcao))
                  : Icon(Symbols.photo_camera_rounded, size: 14, fill: 1, color: c.textoNaAcao),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TelaPrecos extends StatelessWidget {
  const _TelaPrecos();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Especialidades e preços')),
      body: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 32), children: [
        Text('O preço é sempre seu. A faixa mostra o que a maioria cobra na sua região.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        const EditorPrecos(),
      ]),
    );
  }
}

class _Portfolio extends ConsumerWidget {
  const _Portfolio();

  Future<void> _adicionar(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final depois = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (depois == null || !context.mounted) return;
    final querAntes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tem a foto de antes?'),
        content: const Text('Antes e depois lado a lado mostram melhor o seu trabalho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Escolher foto de antes')),
        ],
      ),
    );
    final antes = querAntes == true ? await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85) : null;
    try {
      await ref.read(profissionalRepo).adicionarPortfolio(depois: await depois.readAsBytes(), antes: antes == null ? null : await antes.readAsBytes());
      ref.invalidate(_portfolioProvider);
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  Future<void> _remover(BuildContext context, WidgetRef ref, ItemPortfolio item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover esta foto do portfólio?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Cores.perigo), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(profissionalRepo).removerPortfolio(item.id);
      ref.invalidate(_portfolioProvider);
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itens = ref.watch(_portfolioProvider).value ?? const <ItemPortfolio>[];
    final arq = ref.read(arquivosRepo);
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 132,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Medidas.raioCartao),
          onTap: () => _adicionar(context, ref),
          child: Container(
            width: 110,
            decoration: BoxDecoration(
              color: c.acaoSuave,
              borderRadius: BorderRadius.circular(Medidas.raioCartao),
              border: Border.all(color: c.acao),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Symbols.add_photo_alternate_rounded, color: c.acaoTexto, size: 32),
              const SizedBox(height: 6),
              Text('Adicionar', style: t.labelMedium?.copyWith(color: c.acaoTexto)),
            ]),
          ),
        ),
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: GestureDetector(
              onLongPress: () => _remover(context, ref, item),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Medidas.raioCartao),
                child: Stack(children: [
                  CachedNetworkImage(imageUrl: arq.urlPublica('portfolio', item.depoisPath), width: 110, height: 132, fit: BoxFit.cover),
                  if (item.antesPath != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Selo(texto: 'Antes/depois', cor: Colors.white, fundo: Colors.black54),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton(
                      tooltip: 'Remover',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(backgroundColor: Colors.black45),
                      onPressed: () => _remover(context, ref, item),
                      icon: const Icon(Symbols.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Avaliacoes extends ConsumerWidget {
  const _Avaliacoes();

  Future<void> _responder(BuildContext context, WidgetRef ref, Avaliacao a) async {
    final texto = TextEditingController(text: a.resposta);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Responder ${a.clienteNome}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('A resposta aparece no seu perfil, para todos os clientes.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(controller: texto, autofocus: true, minLines: 2, maxLines: 5, maxLength: 300, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 12),
          BotaoPrincipal(rotulo: 'Publicar resposta', aoTocar: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (ok != true || texto.text.trim().isEmpty || a.pedidoId == null) return;
    try {
      await ref.read(profissionalRepo).responderAvaliacao(a.pedidoId!, texto.text.trim());
      ref.invalidate(_perfilPublicoProvider);
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(_perfilPublicoProvider);
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final lista = perfil.value?.avaliacoes ?? const <Avaliacao>[];
    if (perfil.isLoading && !perfil.hasValue) return const SizedBox(height: 80, child: Carregando());
    if (lista.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Suas avaliações aparecem aqui depois dos primeiros atendimentos.', style: t.bodySmall),
        ),
      );
    }
    return Card(
      child: Column(children: [
        for (final (i, a) in lista.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(nome: a.clienteNome, url: a.clienteFoto, tamanho: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(a.clienteNome, style: t.titleSmall)),
                Estrelas(valor: a.nota.toDouble(), tamanho: 14),
              ]),
              if ((a.comentario ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(a.comentario!, style: t.bodyMedium)),
              if (a.resposta != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.superficieSuave, borderRadius: BorderRadius.circular(10)),
                  child: Text('Sua resposta: ${a.resposta}', style: t.bodySmall),
                ),
              Row(children: [
                Text(quandoFoi(a.criadaEm), style: t.labelSmall?.copyWith(color: c.textoSuave)),
                const Spacer(),
                if (a.pedidoId != null) TextButton(onPressed: () => _responder(context, ref, a), child: Text(a.resposta == null ? 'Responder' : 'Editar resposta')),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }
}
