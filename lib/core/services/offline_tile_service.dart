import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'offline_tile_service_io.dart'
    if (dart.library.html) 'offline_tile_service_web.dart' as platform;

class OfflineTileService {
  OfflineTileService._();
  static final OfflineTileService instance = OfflineTileService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    await platform.initCacheDir();
    _initialized = true;
  }

  Future<bool> tileExists(int z, int x, int y) async {
    if (kIsWeb) return false;
    return platform.tileExists(z, x, y);
  }

  Future<Uint8List?> getTileBytes(int z, int x, int y) async {
    if (kIsWeb) return null;
    return platform.getTileBytes(z, x, y);
  }

  Future<void> downloadTile(int z, int x, int y) async {
    if (kIsWeb) return;
    if (await tileExists(z, x, y)) return;
    final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'CCRRallyApp/1.0',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        await platform.writeTileBytes(z, x, y, res.bodyBytes);
      }
    } catch (_) {}
  }

  /// Downloads all OSM tiles for the bounding box at zoom levels [minZoom]..[maxZoom].
  Future<void> downloadBoundingBox({
    required LatLng sw,
    required LatLng ne,
    int minZoom = 10,
    int maxZoom = 16,
    void Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) return;
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
    int done = 0;
    for (final (z, x, y) in tiles) {
      await downloadTile(z, x, y);
      done++;
      onProgress?.call(done, tiles.length);
    }
  }

  Future<int> getCacheSizeBytes() async {
    if (kIsWeb) return 0;
    return platform.getCacheSizeBytes();
  }

  Future<void> clearCache() async {
    if (kIsWeb) return;
    await platform.clearCache();
  }

  static int _lonToX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _latToY(double lat, int z) {
    final latR = lat * math.pi / 180.0;
    final n = (1.0 - math.log(math.tan(latR) + 1.0 / math.cos(latR)) / math.pi) / 2.0;
    return (n * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }
}
