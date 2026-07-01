import 'package:flutter/foundation.dart';

Future<void> initCacheDir() async {}
Future<bool> tileExists(int z, int x, int y) async => false;
Future<Uint8List?> getTileBytes(int z, int x, int y) async => null;
Future<void> writeTileBytes(int z, int x, int y, Uint8List bytes) async {}
Future<int> getCacheSizeBytes() async => 0;
Future<void> clearCache() async {}
