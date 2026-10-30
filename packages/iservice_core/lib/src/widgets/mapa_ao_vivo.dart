import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import 'componentes.dart';

/// Endereço dos "azulejos" do mapa. O padrão é o OpenStreetMap, bom para testes;
/// no lançamento troque por um provedor com contrato (MapTiler, Stadia, Mapbox)
/// passando URL_MAPA na compilação.
const _urlMapa = String.fromEnvironment('URL_MAPA', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

final _posicaoProvider = StreamProvider.autoDispose.family<PosicaoAoVivo?, String>(
  (ref, pedidoId) => ref.read(pedidosRepo).posicaoAoVivo(pedidoId),
);

/// App Cliente: mapa com o profissional a caminho, distância e tempo estimado.
class MapaAoVivo extends ConsumerStatefulWidget {
  const MapaAoVivo({super.key, required this.pedidoId, required this.nomeProfissional, this.fotoProfissional});
  final String pedidoId;
  final String nomeProfissional;
  final String? fotoProfissional;

  @override
  ConsumerState<MapaAoVivo> createState() => _MapaAoVivoState();
}

class _MapaAoVivoState extends ConsumerState<MapaAoVivo> {
  final _mapa = MapController();
  bool _pronto = false;

  void _enquadrar(PosicaoAoVivo p) {
    if (!_pronto) return;
    _mapa.fitCamera(CameraFit.coordinates(
      coordinates: [LatLng(p.lat, p.lng), LatLng(p.destinoLat, p.destinoLng)],
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 48),
      maxZoom: 16,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    ref.listen(_posicaoProvider(widget.pedidoId), (_, prox) {
      final p = prox.value;
      if (p != null) _enquadrar(p);
    });
    final pos = ref.watch(_posicaoProvider(widget.pedidoId)).value;

    final primeiroNome = widget.nomeProfissional.split(' ').first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Icon(Symbols.near_me_rounded, fill: 1, color: c.acaoTexto),
            const SizedBox(width: 8),
            Expanded(
              child: pos == null
                  ? Text('Aguardando a localização de $primeiroNome…', style: t.titleSmall)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Chega em cerca de ${pos.minutosEstimados} min', style: t.titleSmall),
                      Text('${_km(pos.distanciaKm)} de você · atualizado ${_ha(pos.atualizadoEm)}', style: t.bodySmall),
                    ]),
            ),
          ]),
        ),
        SizedBox(
          height: 240,
          child: pos == null
              ? Container(color: c.superficieSuave, child: const Center(child: CircularProgressIndicator()))
              : FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                      coordinates: [LatLng(pos.lat, pos.lng), LatLng(pos.destinoLat, pos.destinoLng)],
                      padding: const EdgeInsets.all(48),
                      maxZoom: 16,
                    ),
                    onMapReady: () => _pronto = true,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    TileLayer(urlTemplate: _urlMapa, userAgentPackageName: 'br.app.iservice'),
                    PolylineLayer(polylines: [
                      Polyline(
                        points: [LatLng(pos.lat, pos.lng), LatLng(pos.destinoLat, pos.destinoLng)],
                        color: c.acao.withValues(alpha: .6),
                        strokeWidth: 3,
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(pos.destinoLat, pos.destinoLng),
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(Symbols.location_on_rounded, fill: 1, size: 40, color: Cores.perigo),
                      ),
                      Marker(
                        point: LatLng(pos.lat, pos.lng),
                        width: 48,
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
                          ),
                          child: Avatar(nome: widget.nomeProfissional, url: widget.fotoProfissional, tamanho: 42),
                        ),
                      ),
                    ]),
                    const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                  ],
                ),
        ),
      ]),
    );
  }

  static String _km(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

  static String _ha(DateTime d) {
    final s = DateTime.now().difference(d.toLocal()).inSeconds;
    if (s < 30) return 'agora';
    if (s < 90) return 'há 1 min';
    return 'há ${(s / 60).round()} min';
  }
}

/// App Profissional: enquanto [ativo], manda a posição do GPS para o cliente ver
/// no mapa (a cada ~25 m ou 10 s, o que vier depois). Mostra um aviso discreto.
class TransmissorPosicao extends ConsumerStatefulWidget {
  const TransmissorPosicao({super.key, required this.pedidoId, required this.ativo});
  final String pedidoId;
  final bool ativo;

  @override
  ConsumerState<TransmissorPosicao> createState() => _TransmissorPosicaoState();
}

class _TransmissorPosicaoState extends ConsumerState<TransmissorPosicao> {
  StreamSubscription<Position>? _gps;
  DateTime _ultimoEnvio = DateTime.fromMillisecondsSinceEpoch(0);
  bool _semPermissao = false;

  @override
  void initState() {
    super.initState();
    if (widget.ativo) _ligar();
  }

  @override
  void didUpdateWidget(TransmissorPosicao antigo) {
    super.didUpdateWidget(antigo);
    if (widget.ativo && !antigo.ativo) _ligar();
    if (!widget.ativo && antigo.ativo) _desligar();
  }

  Future<void> _ligar() async {
    final inicial = await lerLocalizacaoAtual().catchError((_) => null);
    if (!mounted || !widget.ativo) return;
    if (inicial == null) {
      setState(() => _semPermissao = true);
      return;
    }
    setState(() => _semPermissao = false);
    _enviar(inicial, forcar: true);
    await _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
    ).listen(_enviar, onError: (_) {});
  }

  void _desligar() {
    _gps?.cancel();
    _gps = null;
  }

  void _enviar(Position p, {bool forcar = false}) {
    final agora = DateTime.now();
    if (!forcar && agora.difference(_ultimoEnvio) < const Duration(seconds: 10)) return;
    _ultimoEnvio = agora;
    ref.read(pedidosRepo).enviarPosicao(widget.pedidoId, lat: p.latitude, lng: p.longitude, precisao: p.accuracy).ignore();
  }

  @override
  void dispose() {
    _desligar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ativo) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _semPermissao ? Cores.perigo.withValues(alpha: .1) : c.acaoSuave,
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
      ),
      child: Row(children: [
        Icon(_semPermissao ? Symbols.location_off_rounded : Symbols.share_location_rounded,
            color: _semPermissao ? Cores.perigo : c.acaoTexto),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _semPermissao
                ? 'Ative a localização para o cliente ver você chegando.'
                : 'O cliente vê sua posição no mapa até você chegar. Mantenha o app aberto.',
            style: t.bodySmall,
          ),
        ),
        if (_semPermissao) TextButton(onPressed: _ligar, child: const Text('Ativar')),
      ]),
    );
  }
}
