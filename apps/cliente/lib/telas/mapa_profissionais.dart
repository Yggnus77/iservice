import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

typedef _Ponto = ({double lat, double lng});

/// Posições aproximadas dos profissionais da lista (ids separados por vírgula).
final _posicoesProvider = FutureProvider.autoDispose.family<Map<String, _Ponto>, String>(
    (ref, ids) => ref.read(buscaRepo).posicoesMapa(ids.isEmpty ? const [] : ids.split(',')));

/// O banco devolve o centro da área de cada um numa grade de ~1 km, então
/// vários caem no mesmo ponto. Abre esses em leque (até ~300 m) para que
/// cada pin dê para tocar, sem revelar a posição real de ninguém.
Map<String, LatLng> _espalhar(List<ProfissionalResumo> lista, Map<String, _Ponto> pos) {
  final vistos = <String, int>{};
  final r = <String, LatLng>{};
  for (final p in lista) {
    final o = pos[p.id];
    if (o == null) continue;
    final chave = '${o.lat.toStringAsFixed(4)},${o.lng.toStringAsFixed(4)}';
    final k = vistos[chave] = (vistos[chave] ?? -1) + 1;
    if (k == 0) {
      r[p.id] = LatLng(o.lat, o.lng);
    } else {
      final raio = 0.0012 * math.sqrt(k);
      final ang = k * 2.39996; // ângulo de ouro: espalha sem sobrepor
      r[p.id] = LatLng(o.lat + raio * math.sin(ang), o.lng + raio * math.cos(ang));
    }
  }
  return r;
}

/// Busca no mapa (app Cliente): pins dos profissionais disponíveis perto do
/// local de busca e, embaixo, uma folha com os cartões, mais bem avaliados
/// primeiro. "Chamar" abre o pedido direcionado só para aquele profissional.
class TelaMapaProfissionais extends ConsumerStatefulWidget {
  const TelaMapaProfissionais({super.key, required this.profissaoId, this.especialidadeId, this.urgencia24h = false});
  final String profissaoId;
  final int? especialidadeId;

  /// Veio do botão Urgência 24h: só quem atende a qualquer hora.
  final bool urgencia24h;

  @override
  ConsumerState<TelaMapaProfissionais> createState() => _TelaMapaProfissionaisState();
}

class _TelaMapaProfissionaisState extends ConsumerState<TelaMapaProfissionais> {
  final _mapa = MapController();
  final _folha = DraggableScrollableController();
  final _chaves = <String, GlobalKey>{};
  final _rodizio = DateTime.now().millisecondsSinceEpoch ~/ 60000;
  bool _mapaPronto = false;
  bool _enquadrado = false;
  String? _selecionado;

  static const _folhaInicial = .46;

  FiltroBusca get _filtro => FiltroBusca(
        profissaoId: widget.profissaoId,
        especialidadeId: widget.especialidadeId,
        rodizio: _rodizio,
        urgencia24h: widget.urgencia24h,
      );

  /// Filtros da busca para levar à lista: especialidade e urgência.
  String get _query {
    final q = [
      if (widget.especialidadeId != null) 'esp=${widget.especialidadeId}',
      if (widget.urgencia24h) 'urgencia=1',
    ];
    return q.isEmpty ? '' : '?${q.join('&')}';
  }

  @override
  void dispose() {
    _folha.dispose();
    super.dispose();
  }

  /// Mostra o local de busca e todos os pins, acima da folha.
  void _enquadrar(Local local, Iterable<LatLng> pins) {
    if (!_mapaPronto) return;
    final altura = MediaQuery.sizeOf(context).height;
    final pontos = [LatLng(local.lat, local.lng), ...pins];
    if (pontos.length == 1) {
      _mapa.move(pontos.first, 14);
      return;
    }
    _mapa.fitCamera(CameraFit.coordinates(
      coordinates: pontos,
      padding: EdgeInsets.fromLTRB(40, 200, 40, altura * _folhaInicial + 24),
      maxZoom: 15,
    ));
  }

  void _selecionar(String id, {LatLng? centralizar, bool rolarLista = false}) {
    setState(() => _selecionado = id);
    if (centralizar != null && _mapaPronto) {
      // Centraliza o pin na faixa do mapa que fica acima da folha.
      final altura = MediaQuery.sizeOf(context).height;
      final deslocamento = Offset(0, -(altura * _folhaInicial) / 2 + 60);
      _mapa.move(centralizar, math.max(_mapa.camera.zoom, 14), offset: deslocamento);
    }
    if (rolarLista) {
      final ctx = _chaves[id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: .05);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profissao = ref.watch(profissaoPorIdProvider(widget.profissaoId));
    final especialidade = profissao?.especialidades.where((e) => e.id == widget.especialidadeId).firstOrNull;
    final local = ref.watch(localBuscaProvider);
    final lista = ref.watch(buscaProvider(_filtro));
    final profissionais = lista.value ?? const <ProfissionalResumo>[];
    final ids = profissionais.map((p) => p.id).join(',');
    final posicoes = _espalhar(profissionais, ref.watch(_posicoesProvider(ids)).value ?? const {});

    ref.listen(_posicoesProvider(ids), (_, prox) {
      final p = prox.value;
      if (p == null || _enquadrado) return;
      _enquadrado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enquadrar(local, _espalhar(profissionais, p).values);
      });
    });

    final selecionado = profissionais.where((p) => p.id == _selecionado).firstOrNull ?? profissionais.firstOrNull;
    final nomeBusca = especialidade?.nome ?? profissao?.nome ?? '';

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapa,
            options: MapOptions(
              initialCenter: LatLng(local.lat, local.lng),
              initialZoom: 14,
              onMapReady: () {
                _mapaPronto = true;
                if (posicoes.isNotEmpty) {
                  _enquadrado = true;
                  _enquadrar(local, posicoes.values);
                }
              },
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(urlTemplate: urlMapa, userAgentPackageName: 'br.app.iservice'),
              MarkerLayer(markers: [
                Marker(point: LatLng(local.lat, local.lng), width: 40, height: 40, child: const _VoceAqui()),
                for (final p in profissionais)
                  if (posicoes[p.id] != null && p.id != selecionado?.id)
                    Marker(
                      point: posicoes[p.id]!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: _Pin(
                        rotulo: '${p.nome}, ${p.novo ? 'novo' : 'nota ${nota(p.notaMedia)}'}',
                        aoTocar: () => _selecionar(p.id, centralizar: posicoes[p.id], rolarLista: true),
                      ),
                    ),
                // O selecionado por último, para ficar por cima dos outros.
                if (selecionado != null && posicoes[selecionado.id] != null)
                  Marker(
                    point: posicoes[selecionado.id]!,
                    width: 160,
                    height: 92,
                    alignment: Alignment.topCenter,
                    child: _PinSelecionado(
                      rotulo: '${primeiroNome(selecionado.nome)} · ${selecionado.novo ? 'Novo' : nota(selecionado.notaMedia)}',
                    ),
                  ),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap')),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Cabecalho(
              local: local,
              busca: nomeBusca,
              aoTrocarLocal: () => context.push('/enderecos'),
              aoBuscar: () => context.push('/busca'),
              aoAbrirFiltros: () => context.push(
                  '/profissao/${widget.profissaoId}/lista$_query'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (lista.hasValue) _SeloQuantos(n: profissionais.length),
                const Spacer(),
                _BotaoRedondo(
                  icone: Symbols.my_location_rounded,
                  rotulo: 'Mostrar todos no mapa',
                  aoTocar: () => _enquadrar(local, posicoes.values),
                ),
              ]),
            ),
          ]),
        ),
        DraggableScrollableSheet(
          controller: _folha,
          initialChildSize: _folhaInicial,
          minChildSize: .2,
          maxChildSize: .88,
          snap: true,
          snapSizes: const [_folhaInicial],
          builder: (context, rolagem) => _Folha(
            rolagem: rolagem,
            titulo: widget.urgencia24h
                ? 'Urgência 24h${profissao == null ? '' : ' · ${_plural(profissao.nome)}'}'
                : profissao == null
                    ? 'Profissionais perto de você'
                    : '${_plural(profissao.nome)} perto de você',
            subtitulo: widget.urgencia24h ? 'Atendem a qualquer hora · mais bem avaliados primeiro' : 'Mais bem avaliados primeiro',
            lista: lista,
            selecionadoId: selecionado?.id,
            profissaoNome: profissao?.nome ?? '',
            chave: (id) => _chaves.putIfAbsent(id, GlobalKey.new),
            aoTentar: () => ref.invalidate(buscaProvider(_filtro)),
            aoSelecionar: (p) {
              if (p.id == selecionado?.id) {
                unawaited(context.push('/profissional/${p.id}?profissao=${widget.profissaoId}'));
              } else {
                _selecionar(p.id, centralizar: posicoes[p.id]);
              }
            },
            aoChamar: (p) => context.push(
                '/solicitar/${p.id}?profissao=${widget.profissaoId}${widget.especialidadeId == null ? '' : '&esp=${widget.especialidadeId}'}'),
            aoVerLista: () => context.push(
                '/profissao/${widget.profissaoId}/lista$_query'),
          ),
        ),
      ]),
    );
  }
}

/// "Chaveiro" → "Chaveiros"; nomes compostos ficam como estão.
String _plural(String nome) {
  if (nome.contains(' ')) return 'Profissionais';
  if (nome.endsWith('r')) return '${nome}es';
  if (nome.endsWith('s')) return nome;
  return '${nome}s';
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.local, required this.busca, required this.aoTrocarLocal, required this.aoBuscar, required this.aoAbrirFiltros});
  final Local local;
  final String busca;
  final VoidCallback aoTrocarLocal;
  final VoidCallback aoBuscar;
  final VoidCallback aoAbrirFiltros;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final topo = MediaQuery.paddingOf(context).top;
    return Material(
      color: Cores.azul,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, topo + 4, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            BackButton(color: Colors.white, onPressed: () => context.pop()),
            Expanded(
              child: InkWell(
                onTap: aoTrocarLocal,
                borderRadius: BorderRadius.circular(Medidas.raioControle),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    const Icon(Symbols.location_on_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('SUA LOCALIZAÇÃO', style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: .85), letterSpacing: .6)),
                        Row(children: [
                          Flexible(
                            child: Text(local.descricao,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                          const Icon(Symbols.expand_more_rounded, color: Colors.white, size: 20),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Medidas.raioControle),
              child: InkWell(
                onTap: aoBuscar,
                borderRadius: BorderRadius.circular(Medidas.raioControle),
                child: SizedBox(
                  height: 52,
                  child: Row(children: [
                    const SizedBox(width: 14),
                    const Icon(Symbols.search_rounded, color: Cores.textoSuave, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Buscar outro serviço. Busca atual: $busca',
                        child: ExcludeSemantics(
                          child: Text(busca, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(color: Cores.azulEscuro)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: IconButton(
                        tooltip: 'Abrir filtros',
                        onPressed: aoAbrirFiltros,
                        style: IconButton.styleFrom(
                          backgroundColor: Cores.azulSuave,
                          foregroundColor: Cores.azul,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Symbols.tune_rounded),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SeloQuantos extends StatelessWidget {
  const _SeloQuantos({required this.n});
  final int n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Medidas.raioPilula),
        boxShadow: const [BoxShadow(color: Color(0x290A1F44), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: n > 0 ? Cores.verde : Cores.bordaControle)),
        const SizedBox(width: 8),
        Text(n == 0 ? 'Ninguém perto agora' : '$n perto de você', style: t.labelLarge?.copyWith(color: Cores.azulEscuro)),
      ]),
    );
  }
}

class _BotaoRedondo extends StatelessWidget {
  const _BotaoRedondo({required this.icone, required this.rotulo, required this.aoTocar});
  final IconData icone;
  final String rotulo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: const Color(0x660A1F44),
        child: IconButton(tooltip: rotulo, onPressed: aoTocar, icon: const Icon(Symbols.my_location_rounded, color: Cores.azul)),
      );
}

/// Ponto azul do local de busca.
class _VoceAqui extends StatelessWidget {
  const _VoceAqui();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Você está aqui',
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Cores.azul,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Cores.azul.withValues(alpha: .25), spreadRadius: 8)],
            ),
          ),
        ),
      );
}

class _FormaPin extends CustomPainter {
  const _FormaPin(this.cor, this.miolo);
  final Color cor;
  final Color miolo;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final path = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * .5, h, 0, h * .62, 0, w / 2)
      ..arcToPoint(Offset(w, w / 2), radius: Radius.circular(w / 2))
      ..cubicTo(w, h * .62, w * .5, h, w / 2, h)
      ..close();
    canvas.drawShadow(path, const Color(0xFF0A1F44), 3, false);
    canvas.drawPath(path, Paint()..color = cor);
    canvas.drawCircle(Offset(w / 2, w / 2), w * .2, Paint()..color = miolo);
  }

  @override
  bool shouldRepaint(_FormaPin old) => old.cor != cor || old.miolo != miolo;
}

class _Pin extends StatelessWidget {
  const _Pin({required this.rotulo, required this.aoTocar});
  final String rotulo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: rotulo,
        child: GestureDetector(
          onTap: aoTocar,
          behavior: HitTestBehavior.opaque,
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: CustomPaint(size: Size(28, 38), painter: _FormaPin(Cores.azul, Colors.white)),
          ),
        ),
      );
}

class _PinSelecionado extends StatelessWidget {
  const _PinSelecionado({required this.rotulo});
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: 'Selecionado: $rotulo',
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x290A1F44), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: Cores.azulEscuro)),
        ),
        const SizedBox(height: 4),
        // Laranja com miolo azul-escuro: o laranja nunca leva branco.
        const CustomPaint(size: Size(38, 50), painter: _FormaPin(Cores.laranja, Cores.azulEscuro)),
      ]),
    );
  }
}

class _Folha extends StatelessWidget {
  const _Folha({
    required this.rolagem,
    required this.titulo,
    required this.subtitulo,
    required this.lista,
    required this.selecionadoId,
    required this.profissaoNome,
    required this.chave,
    required this.aoTentar,
    required this.aoSelecionar,
    required this.aoChamar,
    required this.aoVerLista,
  });
  final ScrollController rolagem;
  final String titulo;
  final String subtitulo;
  final AsyncValue<List<ProfissionalResumo>> lista;
  final String? selecionadoId;
  final String profissaoNome;
  final GlobalKey Function(String id) chave;
  final VoidCallback aoTentar;
  final ValueChanged<ProfissionalResumo> aoSelecionar;
  final ValueChanged<ProfissionalResumo> aoChamar;
  final VoidCallback aoVerLista;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      elevation: 12,
      shadowColor: const Color(0x660A1F44),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(controller: rolagem, slivers: [
        SliverToBoxAdapter(
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: c.linha, borderRadius: BorderRadius.circular(Medidas.raioPilula))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: t.titleMedium),
                    Text(subtitulo, style: t.bodySmall),
                  ]),
                ),
                TextButton(onPressed: aoVerLista, child: const Text('Ver lista')),
              ]),
            ),
          ]),
        ),
        ...lista.when(
          loading: () => [const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Carregando()))],
          error: (e, _) => [SliverToBoxAdapter(child: SizedBox(height: 260, child: ErroNaTela(erro: e, aoTentar: aoTentar)))],
          data: (l) => l.isEmpty
              ? [
                  const SliverToBoxAdapter(
                    child: EstadoVazio(
                      icone: Symbols.person_search_rounded,
                      titulo: 'Ninguém disponível agora',
                      texto: 'Todos os profissionais dessa área estão atendendo ou fora do seu raio. Tente de novo em alguns minutos.',
                    ),
                  ),
                ]
              : [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
                    sliver: SliverList.separated(
                      itemCount: l.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _CartaoMapa(
                        key: chave(l[i].id),
                        p: l[i],
                        profissaoNome: profissaoNome,
                        selecionado: l[i].id == selecionadoId,
                        aoTocar: () => aoSelecionar(l[i]),
                        aoChamar: () => aoChamar(l[i]),
                      ),
                    ),
                  ),
                ],
        ),
      ]),
    );
  }
}

/// Cartão da folha: avatar, nome, "Chaveiro · 1,2 km", Disponível, nota e Chamar.
class _CartaoMapa extends StatelessWidget {
  const _CartaoMapa({super.key, required this.p, required this.profissaoNome, required this.selecionado, required this.aoTocar, required this.aoChamar});
  final ProfissionalResumo p;
  final String profissaoNome;
  final bool selecionado;
  final VoidCallback aoTocar;
  final VoidCallback aoChamar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final raio = BorderRadius.circular(Medidas.raioCartao);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: raio,
        side: selecionado ? const BorderSide(color: Cores.laranja, width: 2) : BorderSide(color: c.linha),
      ),
      elevation: selecionado ? 6 : 1,
      shadowColor: const Color(0x400A1F44),
      child: InkWell(
        onTap: aoTocar,
        borderRadius: raio,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Avatar(nome: p.nome, url: p.fotoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(p.nome, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (p.verificado) ...[
                      const SizedBox(width: 4),
                      Icon(Symbols.verified_rounded, size: 16, fill: 1, color: c.acaoTexto, semanticLabel: 'Verificado'),
                    ],
                  ]),
                  Text([profissaoNome, if (p.distanciaKm > 0) distancia(p.distanciaKm)].where((s) => s.isNotEmpty).join(' · '),
                      style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 8),
              Selo(texto: 'Disponível', icone: Symbols.circle, cor: c.sucesso, fundo: c.sucessoSuave),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: p.novo
                    ? Align(alignment: Alignment.centerLeft, child: Selo.novo(context))
                    : Row(children: [
                        const Icon(Symbols.star_rounded, fill: 1, size: 18, color: Cores.estrela),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: nota(p.notaMedia), style: t.labelLarge),
                              TextSpan(text: ' · ${p.totalAvaliacoes} ${p.totalAvaliacoes == 1 ? 'avaliação' : 'avaliações'}', style: t.bodySmall),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: aoChamar,
                style: FilledButton.styleFrom(
                  backgroundColor: Cores.azul,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: Semantics(label: 'Chamar ${primeiroNome(p.nome)}', excludeSemantics: true, child: const Text('Chamar')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
