import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Directory? _cacheDir;

Future<void> initCacheDir() async {
  final base = await getApplicationDocumentsDirectory();
  _cacheDir = Directory('${base.path}/osm_tiles');
  if (!_cacheDir!.existsSync()) _cacheDir!.createSync(recursive: true);
}

File _tileFile(int z, int x, int y) {
  final dir = Directory('${_cacheDir!.path}/$z/$x');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/$y.png');
}

Future<bool> tileExists(int z, int x, int y) async {
  if (_cacheDir == null) return false;
  return _tileFile(z, x, y).existsSync();
}

Future<Uint8List?> getTileBytes(int z, int x, int y) async {
  if (_cacheDir == null) return null;
  final f = _tileFile(z, x, y);
  if (!f.existsSync()) return null;
  return f.readAsBytes();
}

Future<void> writeTileBytes(int z, int x, int y, Uint8List bytes) async {
  if (_cacheDir == null) return;
  await _tileFile(z, x, y).writeAsBytes(bytes);
}

Future<int> getCacheSizeBytes() async {
  if (_cacheDir == null || !_cacheDir!.existsSync()) return 0;
  int total = 0;
  await for (final entity in _cacheDir!.list(recursive: true)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

Future<void> clearCache() async {
  if (_cacheDir == null) return;
  if (_cacheDir!.existsSync()) await _cacheDir!.delete(recursive: true);
  await _cacheDir!.create(recursive: true);
}
