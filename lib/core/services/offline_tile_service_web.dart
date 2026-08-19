import 'package:flutter/foundation.dart';

Future<void> initCacheDir() async {}
Future<bool> tileExists(String styleId, int z, int x, int y) async => false;
Future<Uint8List?> getTileBytes(String styleId, int z, int x, int y) async =>
    null;
Future<void> writeTileBytes(
    String styleId, int z, int x, int y, Uint8List bytes) async {}
Future<int> getCacheSizeBytes([String? styleId]) async => 0;
Future<void> clearCache([String? styleId]) async {}
