import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Directory? _cacheDir;

Future<void> initCacheDir() async {
  final base = await getApplicationDocumentsDirectory();
  _cacheDir = Directory('${base.path}/osm_tiles');
  if (!_cacheDir!.existsSync()) _cacheDir!.createSync(recursive: true);
}

// Rifiniture Step 49 — un livello di cartella in più per lo stile
// (`osm`/`opentopomap`): scaricare una regione con uno stile non deve mai
// far risultare "presente" un tile dell'altro stile alla stessa (z,x,y).
File _tileFile(String styleId, int z, int x, int y) {
  final dir = Directory('${_cacheDir!.path}/$styleId/$z/$x');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/$y.png');
}

Future<bool> tileExists(String styleId, int z, int x, int y) async {
  if (_cacheDir == null) return false;
  return _tileFile(styleId, z, x, y).existsSync();
}

Future<Uint8List?> getTileBytes(String styleId, int z, int x, int y) async {
  if (_cacheDir == null) return null;
  final f = _tileFile(styleId, z, x, y);
  if (!f.existsSync()) return null;
  return f.readAsBytes();
}

Future<void> writeTileBytes(
    String styleId, int z, int x, int y, Uint8List bytes) async {
  if (_cacheDir == null) return;
  await _tileFile(styleId, z, x, y).writeAsBytes(bytes);
}

Future<int> getCacheSizeBytes([String? styleId]) async {
  if (_cacheDir == null || !_cacheDir!.existsSync()) return 0;
  final root = styleId == null
      ? _cacheDir!
      : Directory('${_cacheDir!.path}/$styleId');
  if (!root.existsSync()) return 0;
  int total = 0;
  await for (final entity in root.list(recursive: true)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

Future<void> clearCache([String? styleId]) async {
  if (_cacheDir == null) return;
  if (styleId == null) {
    if (_cacheDir!.existsSync()) await _cacheDir!.delete(recursive: true);
    await _cacheDir!.create(recursive: true);
    return;
  }
  final dir = Directory('${_cacheDir!.path}/$styleId');
  if (dir.existsSync()) await dir.delete(recursive: true);
}
