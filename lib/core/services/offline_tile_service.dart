import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/map_style.dart';
import 'offline_tile_service_io.dart'
    if (dart.library.html) 'offline_tile_service_web.dart' as platform;

/// Da dove è stato effettivamente servito l'ultimo tile richiesto dal
/// [CcrTileProvider] — usato dall'indicatore discreto in navigazione
/// (Step 49, Parte 1c).
enum TileServeSource { cache, network, placeholder }

/// Una regione scaricata per la navigazione offline: un evento, uno stile
/// (Step 49 — cache separata per stile, vedi Parte 2c), l'intervallo di
/// zoom e quanti tile contiene realmente. Persistita separatamente dai
/// byte dei tile (che vivono su file) perché "quanti tile a quali zoom"
/// non è ricavabile in modo univoco dal solo contenuto della cartella
/// quando più regioni si sovrappongono sullo stesso stile.
class OfflineRegionInfo {
  final String eventId;
  final String eventNome;
  final String styleId;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final DateTime downloadedAt;

  const OfflineRegionInfo({
    required this.eventId,
    required this.eventNome,
    required this.styleId,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'eventNome': eventNome,
        'styleId': styleId,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tileCount': tileCount,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  static OfflineRegionInfo fromJson(Map<String, dynamic> j) =>
      OfflineRegionInfo(
        eventId: j['eventId'] as String,
        eventNome: j['eventNome'] as String,
        styleId: j['styleId'] as String,
        minZoom: j['minZoom'] as int,
        maxZoom: j['maxZoom'] as int,
        tileCount: j['tileCount'] as int,
        downloadedAt: DateTime.parse(j['downloadedAt'] as String),
      );
}

class OfflineTileService {
  OfflineTileService._();
  static final OfflineTileService instance = OfflineTileService._();

  static const _regionsKey = 'offline_regions_meta_v2';

  bool _initialized = false;
  SharedPreferences? _prefs;

  /// Sorgente dell'ultimo tile servito dal [CcrTileProvider] — aggiornato
  /// ad ogni richiesta, letto dall'indicatore discreto in navigazione.
  final ValueNotifier<TileServeSource?> lastServeSource =
      ValueNotifier<TileServeSource?>(null);

  /// `false` dopo l'ultimo tentativo di rete fallito (timeout/eccezione),
  /// torna `true` al primo tentativo riuscito. Combinato con
  /// [lastServeSource] per capire quando la mappa sta girando sulla sola
  /// cache (Step 49, Parte 1c).
  final ValueNotifier<bool> networkReachable = ValueNotifier<bool>(true);

  Future<void> init() async {
    if (_initialized) return;
    if (!kIsWeb) await platform.initCacheDir();
    _prefs ??= await SharedPreferences.getInstance();
    _initialized = true;
  }

  Future<bool> tileExists(String styleId, int z, int x, int y) async {
    if (kIsWeb) return false;
    return platform.tileExists(styleId, z, x, y);
  }

  Future<Uint8List?> getTileBytes(String styleId, int z, int x, int y) async {
    if (kIsWeb) return null;
    return platform.getTileBytes(styleId, z, x, y);
  }

  Future<void> writeTileBytes(
      String styleId, int z, int x, int y, Uint8List bytes) async {
    if (kIsWeb) return;
    await platform.writeTileBytes(styleId, z, x, y, bytes);
  }

  Future<void> downloadTile(String styleId, int z, int x, int y) async {
    if (kIsWeb) return;
    if (await tileExists(styleId, z, x, y)) return;
    final style = MapStyle.fromId(styleId);
    final url = _urlFor(style, z, x, y);
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'CCRRallyApp/1.0',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        await platform.writeTileBytes(styleId, z, x, y, res.bodyBytes);
      }
    } catch (_) {}
  }

  String _urlFor(MapStyle style, int z, int x, int y) {
    var url = style.urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
    if (style.subdomains.isNotEmpty) {
      final s = style.subdomains[(x + y) % style.subdomains.length];
      url = url.replaceAll('{s}', s);
    }
    return url;
  }

  /// Downloads all tiles for [styleId] within the bounding box, at zoom
  /// levels [minZoom]..[maxZoom]. [maxZoom] viene comunque limitato al
  /// [MapStyle.maxNativeZoom] dello stile — oltre, il server restituisce lo
  /// stesso identico tile upscalato (verificato empiricamente allo Step
  /// 49): scaricarlo sarebbe solo spazio sprecato, flutter_map fa lo
  /// stesso upscale client-side dal tile nativo già in cache.
  ///
  /// Al termine salva/aggiorna l'[OfflineRegionInfo] per (eventId, styleId)
  /// — quanti tile e a quali zoom, mostrato in "Mappe offline" (Parte 1c).
  Future<void> downloadBoundingBox({
    required String eventId,
    required String eventNome,
    required String styleId,
    required LatLng sw,
    required LatLng ne,
    int minZoom = 10,
    int maxZoom = 16,
    void Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) return;
    await init();
    final cappedMaxZoom = cappedMaxZoomFor(styleId, maxZoom);
    final tiles =
        tilesForBoundingBox(sw: sw, ne: ne, minZoom: minZoom, maxZoom: cappedMaxZoom);
    int done = 0;
    for (final (z, x, y) in tiles) {
      await downloadTile(styleId, z, x, y);
      done++;
      onProgress?.call(done, tiles.length);
    }
    await _saveRegionInfo(OfflineRegionInfo(
      eventId: eventId,
      eventNome: eventNome,
      styleId: styleId,
      minZoom: minZoom,
      maxZoom: cappedMaxZoom,
      tileCount: tiles.length,
      downloadedAt: DateTime.now(),
    ));
  }

  Future<int> getCacheSizeBytes([String? styleId]) async {
    if (kIsWeb) return 0;
    return platform.getCacheSizeBytes(styleId);
  }

  Future<void> clearCache([String? styleId]) async {
    if (kIsWeb) return;
    await platform.clearCache(styleId);
    if (styleId == null) {
      await _saveAllRegionInfos(const []);
    } else {
      final remaining =
          (await getRegionInfos()).where((r) => r.styleId != styleId).toList();
      await _saveAllRegionInfos(remaining);
    }
  }

  // ── Region manifest (quanti tile/zoom per regione scaricata) ───────────

  Future<List<OfflineRegionInfo>> getRegionInfos() async {
    await init();
    final raw = _prefs?.getString(_regionsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => OfflineRegionInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveRegionInfo(OfflineRegionInfo info) async {
    final current = await getRegionInfos();
    final next = [
      for (final r in current)
        if (!(r.eventId == info.eventId && r.styleId == info.styleId)) r,
      info,
    ];
    await _saveAllRegionInfos(next);
  }

  Future<void> _saveAllRegionInfos(List<OfflineRegionInfo> infos) async {
    await init();
    await _prefs?.setString(
        _regionsKey, jsonEncode(infos.map((r) => r.toJson()).toList()));
  }

  // ── Segnali per l'indicatore "sto usando la cache" in navigazione ──────

  void reportTileServed(TileServeSource source) {
    lastServeSource.value = source;
  }

  void reportNetworkResult(bool reachable) {
    if (networkReachable.value != reachable) {
      networkReachable.value = reachable;
    }
  }

  /// Limita [requestedMaxZoom] al [MapStyle.maxNativeZoom] dello stile
  /// (Step 49, Parte 2d): oltre, il server restituisce lo stesso identico
  /// tile upscalato (verificato empiricamente confrontando lo sha — vedi
  /// `MapStyle.openTopoMap`), quindi scaricarlo/cachearlo sarebbe solo
  /// spazio sprecato — flutter_map fa lo stesso upscale client-side dal
  /// tile nativo già in cache tramite `TileLayer.maxNativeZoom`.
  static int cappedMaxZoomFor(String styleId, int requestedMaxZoom) =>
      math.min(requestedMaxZoom, MapStyle.fromId(styleId).maxNativeZoom);

  /// Elenco (z,x,y) di tutti i tile nello schema slippy-map standard che
  /// coprono il bounding box, per [minZoom]..[maxZoom] — stessa formula
  /// usata da [downloadTile]/dal `TileLayer` di flutter_map per costruire
  /// gli URL, così un tile scaricato qui è esattamente lo stesso che la
  /// mappa richiederà in navigazione (nessun disallineamento di schema).
  /// Pubblico e senza I/O apposta per essere testabile senza rete/disco.
  static List<(int, int, int)> tilesForBoundingBox({
    required LatLng sw,
    required LatLng ne,
    required int minZoom,
    required int maxZoom,
  }) {
    final tiles = <(int, int, int)>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final x0 = _lonToX(sw.longitude, z);
      final x1 = _lonToX(ne.longitude, z);
      final y0 = _latToY(ne.latitude, z);
      final y1 = _latToY(sw.latitude, z);
      for (int x = x0; x <= x1; x++) {
        for (int y = y0; y <= y1; y++) {
          tiles.add((z, x, y));
        }
      }
    }
    return tiles;
  }

  static int _lonToX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _latToY(double lat, int z) {
    final latR = lat * math.pi / 180.0;
    final n = (1.0 - math.log(math.tan(latR) + 1.0 / math.cos(latR)) / math.pi) / 2.0;
    return (n * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }
}
