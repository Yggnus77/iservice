import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import 'componentes.dart';
import 'mapa_ao_vivo.dart';

/// Busca de endereços da Stadia Maps (mesma conta dos mapas, base OpenStreetMap). Na web a conta
/// autoriza o domínio; no celular vai a chave CHAVE_MAPA. URL_BUSCA_ENDERECO troca o provedor.
const _chaveMapa = String.fromEnvironment('CHAVE_MAPA');
const _urlBusca = String.fromEnvironment('URL_BUSCA_ENDERECO', defaultValue: 'https://api.stadiamaps.com/geocoding/v1/search');

/// Um resultado só vale se cair a até esta distância do centro da cidade escolhida.
/// (Cristalina e Formosa são grandes; 35 km cobre os bairros afastados sem aceitar outra cidade.)
const _raioAceitoKm = 35.0;

/// Ponto achado para o endereço digitado.
class PontoEndereco {
  const PontoEndereco(this.ponto, {required this.precisao});
  final LatLng ponto;

  /// 'rua' (achou a rua ou o número), 'bairro' (só o bairro/setor) ou 'cidade' (centro da cidade).
  final String precisao;
}

String _rotuloCidade(Regiao r) => r.uf == 'DF' ? '${r.nome}, Brasília, DF' : '${r.nome}, GO';

/// Procura o endereço no mapa. Tenta rua + bairro + cidade e depois só bairro + cidade.
/// Se nada cair perto da cidade escolhida, ou sem internet, devolve o centro da cidade:
/// a pessoa ajusta o alfinete na tela "Confira no mapa".
Future<PontoEndereco> localizarEndereco({required String logradouro, String? bairro, required Regiao regiao, required LatLng centro}) async {
  final b = bairro?.trim() ?? '';
  final tentativas = <(String, String)>[
    ([logradouro.trim(), if (b.isNotEmpty) b, _rotuloCidade(regiao)].where((s) => s.isNotEmpty).join(', '), 'rua'),
    if (b.isNotEmpty) ('$b, ${_rotuloCidade(regiao)}', 'bairro'),
  ];
  for (final (texto, precisao) in tentativas) {
    final p = await _buscar(texto, centro);
    if (p != null) return PontoEndereco(p.$1, precisao: p.$2 ? precisao : 'bairro');
  }
  return PontoEndereco(centro, precisao: 'cidade');
}

/// Devolve o ponto e se ele é de rua/endereço (true) ou de área maior (false).
Future<(LatLng, bool)?> _buscar(String texto, LatLng centro) async {
  try {
    final uri = Uri.parse(_urlBusca).replace(
      queryParameters: {
        'text': texto,
        'size': '1',
        'lang': 'pt',
        'boundary.country': 'BR',
        'boundary.circle.lat': '${centro.latitude}',
        'boundary.circle.lon': '${centro.longitude}',
        'boundary.circle.radius': '$_raioAceitoKm',
        'focus.point.lat': '${centro.latitude}',
        'focus.point.lon': '${centro.longitude}',
        if (_chaveMapa != '') 'api_key': _chaveMapa,
      },
    );
    final r = await http.get(uri).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    final features = (jsonDecode(r.body) as Map<String, dynamic>)['features'] as List?;
    if (features == null || features.isEmpty) return null;
    final f = features.first as Map<String, dynamic>;
    final coords = (f['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    final ponto = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
    if (const Distance().as(LengthUnit.Kilometer, ponto, centro) > _raioAceitoKm) return null;
    final camada = (f['properties'] as Map<String, dynamic>?)?['layer'];
    // Se a busca só achou a cidade inteira, não ajuda: fica o centro que já temos.
    if (camada == 'locality' || camada == 'county' || camada == 'region' || camada == 'localadmin') return null;
    return (ponto, camada == 'address' || camada == 'street' || camada == 'venue');
  } on Object {
    return null;
  }
}

/// Fluxo usado ao salvar um endereço: acha o ponto (GPS, rua, bairro ou centro da cidade) e
/// abre "Confira no mapa". Devolve o ponto confirmado, ou null se a pessoa voltou.
Future<LatLng?> localizarEConfirmar(
  BuildContext context, {
  required Regiao regiao,
  required (double, double)? centro,
  required String logradouro,
  String? bloco,
  String? bairro,
  (double, double)? gps,
}) async {
  final meio = centro == null ? const LatLng(-15.7939, -47.8828) : LatLng(centro.$1, centro.$2);
  final inicial = gps != null
      ? PontoEndereco(LatLng(gps.$1, gps.$2), precisao: 'gps')
      : await localizarEndereco(logradouro: logradouro, bairro: bairro, regiao: regiao, centro: meio);
  if (!context.mounted) return null;
  final partes = [logradouro, bloco, bairro].map((s) => s?.trim() ?? '').where((s) => s.isNotEmpty).join(', ');
  return await confirmarNoMapa(context, inicial: inicial, endereco: '$partes · ${regiao.nomeComUf}');
}

/// Abre "Confira no mapa": o alfinete fica parado no meio e a pessoa arrasta o mapa até a casa.
/// Devolve o ponto confirmado, ou null se voltou sem confirmar.
Future<LatLng?> confirmarNoMapa(BuildContext context, {required PontoEndereco inicial, required String endereco}) => Navigator.of(context).push<LatLng>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => TelaConfirmarLocal(inicial: inicial, endereco: endereco),
  ),
);

class TelaConfirmarLocal extends StatefulWidget {
  const TelaConfirmarLocal({super.key, required this.inicial, required this.endereco});
  final PontoEndereco inicial;
  final String endereco;

  @override
  State<TelaConfirmarLocal> createState() => _TelaConfirmarLocalState();
}

class _TelaConfirmarLocalState extends State<TelaConfirmarLocal> {
  final _mapa = MapController();
  late LatLng _centro = widget.inicial.ponto;
  late String _precisao = widget.inicial.precisao;
  bool _movendo = false;
  bool _mexeu = false;
  bool _lendoGps = false;

  double get _zoomInicial => switch (widget.inicial.precisao) {
    'rua' || 'gps' => 17,
    'bairro' => 15.5,
    _ => 13.5,
  };

  Future<void> _usarGps() async {
    setState(() => _lendoGps = true);
    try {
      final p = await lerLocalizacaoAtual();
      if (!mounted) return;
      if (p == null) {
        mostrarMensagem(context, 'Não foi possível ler sua localização. Arraste o mapa até a sua casa.');
        return;
      }
      _mapa.move(LatLng(p.latitude, p.longitude), 17.5);
      setState(() {
        _centro = LatLng(p.latitude, p.longitude);
        _precisao = 'gps';
        _mexeu = true;
      });
    } finally {
      if (mounted) setState(() => _lendoGps = false);
    }
  }

  String get _aviso {
    if (_mexeu) return 'Confira se o alfinete está em cima da sua casa.';
    return switch (_precisao) {
      'rua' || 'gps' => 'Achamos este ponto. Arraste o mapa se o alfinete não estiver em cima da sua casa.',
      'bairro' => 'Achamos o bairro. Arraste o mapa até o alfinete ficar em cima da sua casa.',
      _ => 'Não achamos a rua no mapa. Arraste o mapa até a sua casa ou use a sua localização.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final precisaAtencao = !_mexeu && _precisao == 'cidade';
    return Scaffold(
      appBar: AppBar(title: const Text('Confira no mapa')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: widget.inicial.ponto,
                    initialZoom: _zoomInicial,
                    minZoom: 10,
                    maxZoom: 19,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapEvent: (e) {
                      final mexendo = e is MapEventMoveStart || e is MapEventFlingAnimationStart || e is MapEventMove;
                      final parou = e is MapEventMoveEnd || e is MapEventFlingAnimationEnd || e is MapEventFlingAnimationNotStarted;
                      if (mexendo && !_movendo && e.source != MapEventSource.mapController) setState(() => _movendo = true);
                      if (parou && _movendo) setState(() => _movendo = false);
                    },
                    onPositionChanged: (camera, gesto) {
                      _centro = camera.center;
                      if (gesto && !_mexeu) setState(() => _mexeu = true);
                    },
                  ),
                  children: [
                    TileLayer(urlTemplate: urlMapa, userAgentPackageName: 'br.app.iservice', retinaMode: RetinaMode.isHighDensity(context)),
                    creditoMapa,
                  ],
                ),
                // Alfinete fixo: a ponta fica exatamente no centro do mapa.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSlide(
                            offset: Offset(0, _movendo ? -.25 : 0),
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Symbols.location_on_rounded,
                              fill: 1,
                              size: 48,
                              color: c.acao,
                              shadows: const [Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3))],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: _movendo ? 10 : 6,
                      height: _movendo ? 4 : 3,
                      decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Usar minha localização',
                    onPressed: _lendoGps ? null : _usarGps,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: c.acaoTexto,
                    child: _lendoGps
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Symbols.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Symbols.home_pin_rounded, color: c.acaoTexto),
                        const SizedBox(width: 10),
                        Expanded(child: Text(widget.endereco, style: t.titleSmall)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: precisaAtencao ? c.alertaSuave : c.superficieSuave,
                        borderRadius: BorderRadius.circular(Medidas.raioControle),
                      ),
                      child: Row(
                        children: [
                          Icon(precisaAtencao ? Symbols.info_rounded : Symbols.pan_tool_alt_rounded, size: 20, color: precisaAtencao ? c.alerta : c.textoSuave),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_aviso, style: t.bodySmall)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    BotaoPrincipal(rotulo: 'Confirmar local', aoTocar: () => Navigator.pop(context, _centro)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
