import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../services/offline_tile_service.dart';

/// [TileProvider] cache-first per la navigazione (Step 49, Parte 1):
/// prima di ogni richiesta di rete consulta [OfflineTileService] (la
/// cartella scaricata da "Mappe offline", scaricata proprio per essere
/// usata quando la copertura manca) — la rete è solo il fallback per i
/// tile non presenti in cache.
///
/// Se nessuna delle due fonti restituisce un'immagine valida, il tile
/// diventa uno sfondo neutro invece di un buco/riquadro rotto (Parte 1d):
/// la navigazione (traccia, freccia, marker) deve restare leggibile anche
/// senza sfondo cartografico.
class CcrTileProvider extends TileProvider {
  final String styleId;

  CcrTileProvider({required this.styleId, super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CcrTileImage(
      styleId: styleId,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      url: getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}

class _CcrTileImage extends ImageProvider<_CcrTileImage> {
  final String styleId;
  final int z;
  final int x;
  final int y;
  final String url;
  final Map<String, String> headers;

  const _CcrTileImage({
    required this.styleId,
    required this.z,
    required this.x,
    required this.y,
    required this.url,
    required this.headers,
  });

  @override
  Future<_CcrTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _CcrTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: '$styleId/$z/$x/$y',
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final service = OfflineTileService.instance;

    final cached = await service.getTileBytes(styleId, z, x, y);
    if (cached != null) {
      service.reportTileServed(TileServeSource.cache);
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(cached));
      } catch (_) {
        // Cache corrotta: prosegue verso la rete come se non ci fosse.
      }
    }

    try {
      final res = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        service.reportNetworkResult(true);
        service.reportTileServed(TileServeSource.network);
        // Opportunistico: un tile arrivato dalla rete durante la
        // navigazione finisce comunque in cache, non solo quelli
        // scaricati esplicitamente da "Mappe offline".
        unawaited(service.writeTileBytes(styleId, z, x, y, res.bodyBytes));
        return await decode(
            await ui.ImmutableBuffer.fromUint8List(res.bodyBytes));
      }
      service.reportNetworkResult(false);
    } catch (_) {
      service.reportNetworkResult(false);
    }

    service.reportTileServed(TileServeSource.placeholder);
    final neutral = await _neutralTileBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(neutral));
  }

  @override
  bool operator ==(Object other) =>
      other is _CcrTileImage &&
      styleId == other.styleId &&
      z == other.z &&
      x == other.x &&
      y == other.y;

  @override
  int get hashCode => Object.hash(styleId, z, x, y);
}

Uint8List? _neutralTileCache;
Future<Uint8List>? _neutralTileFuture;

/// Un piccolo PNG a tinta unita generato una volta sola e riusato per ogni
/// tile mancante — vedi [_CcrTileImage._load]. Grigio-blu chiaro deliberato
/// (non un grigio scuro vicino al background app, non il nero): fra le
/// palette di traccia/freccia in "Aspetto traccia" il nero è un'opzione
/// selezionabile, quindi lo sfondo deve restare leggibilmente più chiaro di
/// qualunque colore lì presente, non solo "diverso" dal nero dell'app.
Future<Uint8List> _neutralTileBytes() {
  final cached = _neutralTileCache;
  if (cached != null) return SynchronousFuture(cached);
  return _neutralTileFuture ??= () async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xFF4a5568);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    _neutralTileCache = bytes;
    return bytes;
  }();
}
