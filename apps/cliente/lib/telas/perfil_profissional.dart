import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Perfil público do profissional: nota, especialidades com preço, portfólio e avaliações.
class TelaPerfilProfissional extends ConsumerStatefulWidget {
  const TelaPerfilProfissional({super.key, required this.id, this.profissaoId});
  final String id;
  final String? profissaoId;

  @override
  ConsumerState<TelaPerfilProfissional> createState() => _TelaPerfilProfissionalState();
}

class _TelaPerfilProfissionalState extends ConsumerState<TelaPerfilProfissional> {
  bool? _favorito;

  Future<void> _alternarFavorito(bool atual) async {
    setState(() => _favorito = !atual);
    try {
      await ref.read(buscaRepo).favoritar(widget.id, !atual);
      ref.invalidate(favoritosProvider);
    } catch (e) {
      setState(() => _favorito = atual);
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProfissionalProvider(widget.id));
    return perfil.when(
      loading: () => const Scaffold(body: Carregando()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErroNaTela(erro: e, aoTentar: () => ref.invalidate(perfilProfissionalProvider(widget.id)))),
      data: (p) => p == null
          ? Scaffold(appBar: AppBar(), body: const EstadoVazio(icone: Symbols.person_off_rounded, titulo: 'Perfil indisponível'))
          : _conteudo(context, p),
    );
  }

  Widget _conteudo(BuildContext context, PerfilProfissional p) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final favorito = _favorito ?? p.favorito;
    final profissao = p.profissoes.where((x) => x.id == widget.profissaoId).firstOrNull ?? p.profissoes.firstOrNull;
    final arquivos = ref.read(arquivosRepo);

    void solicitar([int? esp]) {
      if (profissao == null) return;
      context.push('/solicitar/${p.id}?profissao=${profissao.id}${esp == null ? '' : '&esp=$esp'}');
    }

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 250,
          foregroundColor: Colors.white,
          backgroundColor: Cores.azulEscuro,
          actions: [
            IconButton(
              tooltip: favorito ? 'Remover dos favoritos' : 'Salvar nos favoritos',
              onPressed: () => _alternarFavorito(favorito),
              icon: Icon(Symbols.favorite_rounded, fill: favorito ? 1 : 0, color: favorito ? const Color(0xFFFF5A6A) : Colors.white),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: DecoratedBox(
              decoration: const BoxDecoration(gradient: Cores.gradienteMarca),
              child: SafeArea(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Avatar(nome: p.nome, url: p.fotoUrl, tamanho: 96, online: p.disponivel),
                  const SizedBox(height: 10),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.nome, style: t.headlineSmall?.copyWith(color: Colors.white)),
                    if (p.verificado) ...[const SizedBox(width: 6), const Icon(Symbols.verified_rounded, fill: 1, color: Color(0xFF7FB2FF))],
                  ]),
                  Text([profissao?.nome, p.regiao].whereType<String>().join(' · '), style: t.bodySmall?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 18),
                ]),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  _Numero(valor: p.novo ? 'Novo' : nota(p.notaMedia), rotulo: p.novo ? 'no iService' : '${p.totalAvaliacoes} avaliações', icone: Symbols.star_rounded),
                  _Numero(valor: '${p.servicosConcluidos}', rotulo: 'serviços', icone: Symbols.task_alt_rounded),
                  _Numero(valor: '${p.anosExperiencia ?? 0}', rotulo: 'anos de experiência', icone: Symbols.workspace_premium_rounded),
                ]),
              ),
            ),
          ),
        ),
        if (p.verificado)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 12, Medidas.margemTela, 0),
              child: Row(children: [
                Icon(Symbols.shield_rounded, size: 18, color: c.sucesso, fill: 1),
                const SizedBox(width: 6),
                Expanded(child: Text('Documento e selfie conferidos pela equipe iService', style: t.bodySmall?.copyWith(color: c.sucesso))),
              ]),
            ),
          ),
        if ((p.bio ?? '').isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
              child: Text(p.bio!, style: t.bodyMedium),
            ),
          ),
        for (final prof in p.profissoes) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
              child: TituloSecao(titulo: p.profissoes.length > 1 ? 'Especialidades: ${prof.nome}' : 'Especialidades e preços'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
            sliver: SliverList.separated(
              itemCount: prof.especialidades.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = prof.especialidades[i];
                return Card(
                  child: ListTile(
                    title: Text(e.nome, style: t.titleSmall),
                    subtitle: e.preco == null ? const Text('Valor combinado no local') : Text('A partir de ${reais(e.preco)}'),
                    trailing: Icon(Symbols.arrow_forward_rounded, color: c.acaoTexto),
                    onTap: p.disponivel && prof.id == profissao?.id ? () => solicitar(e.id) : null,
                  ),
                );
              },
            ),
          ),
        ],
        if (p.certificacoes.isNotEmpty) ...[
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0), child: TituloSecao(titulo: 'Certificações'))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final cert in p.certificacoes) Chip(avatar: Icon(Symbols.workspace_premium_rounded, size: 18, color: c.acaoTexto), label: Text(cert)),
              ]),
            ),
          ),
        ],
        if (p.portfolio.isNotEmpty) ...[
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0), child: TituloSecao(titulo: 'Trabalhos (antes e depois)'))),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
                itemCount: p.portfolio.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = p.portfolio[i];
                  Widget foto(String caminho, String etiqueta) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(children: [
                          CachedNetworkImage(imageUrl: arquivos.urlPublica('portfolio', caminho), width: 110, height: 150, fit: BoxFit.cover),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Selo(texto: etiqueta, cor: Colors.white, fundo: Colors.black54),
                          ),
                        ]),
                      );
                  return Row(children: [
                    if (item.antesPath != null) ...[foto(item.antesPath!, 'Antes'), const SizedBox(width: 4)],
                    foto(item.depoisPath, 'Depois'),
                  ]);
                },
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
            child: TituloSecao(titulo: 'Avaliações'),
          ),
        ),
        if (p.avaliacoes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
              child: Text('Ainda sem avaliações. Profissionais novos passam pela mesma verificação de documentos.', style: t.bodySmall),
            ),
          )
        else ...[
          SliverToBoxAdapter(child: _Distribuicao(p: p)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 0),
            sliver: SliverList.separated(
              itemCount: p.avaliacoes.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (_, i) => _ItemAvaliacao(a: p.avaliacoes[i]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ]),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(Medidas.margemTela, 12, Medidas.margemTela, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: c.linha))),
        child: p.disponivel
            ? BotaoPrincipal(rotulo: 'Solicitar serviço', icone: Symbols.bolt_rounded, aoTocar: () => solicitar())
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Atendendo outro cliente agora', style: t.titleSmall),
                Text('Escolha outro profissional ou volte mais tarde.', style: t.bodySmall),
              ]),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.valor, required this.rotulo, required this.icone});
  final String valor;
  final String rotulo;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 18, fill: 1, color: icone == Symbols.star_rounded ? Cores.estrela : context.cores.acaoTexto),
          const SizedBox(width: 4),
          Text(valor, style: t.titleMedium),
        ]),
        Text(rotulo, style: t.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _Distribuicao extends StatelessWidget {
  const _Distribuicao({required this.p});
  final PerfilProfissional p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final total = p.distribuicaoNotas.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
      child: Row(children: [
        Column(children: [
          Text(nota(p.notaMedia), style: t.displaySmall),
          Estrelas(valor: p.notaMedia, tamanho: 16),
          Text('${p.totalAvaliacoes} avaliações', style: t.bodySmall),
        ]),
        const SizedBox(width: 20),
        Expanded(
          child: Column(children: [
            for (var n = 5; n >= 1; n--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 14, child: Text('$n', style: t.labelSmall)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : (p.distribuicaoNotas[n] ?? 0) / total,
                        minHeight: 6,
                        color: Cores.estrela,
                        backgroundColor: c.superficieSuave,
                      ),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ItemAvaliacao extends StatelessWidget {
  const _ItemAvaliacao({required this.a});
  final Avaliacao a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Avatar(nome: a.clienteNome, url: a.clienteFoto, tamanho: 36),
        const SizedBox(width: 10),
        Expanded(child: Text(a.clienteNome, style: t.titleSmall)),
        Text(quandoFoi(a.criadaEm), style: t.bodySmall),
      ]),
      const SizedBox(height: 6),
      Estrelas(valor: a.nota.toDouble(), tamanho: 16),
      if (a.comentario != null) ...[const SizedBox(height: 4), Text(a.comentario!)],
      if (a.fotos.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in a.fotos)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: f, width: 72, height: 72, fit: BoxFit.cover)),
              ),
          ]),
        ),
      ],
      if (a.resposta != null)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.superficieSuave, borderRadius: BorderRadius.circular(10)),
          child: Text('Resposta do profissional: ${a.resposta}', style: t.bodySmall),
        ),
    ]);
  }
}
