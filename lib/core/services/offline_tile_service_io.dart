import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Directory? _cacheDir;

Future<void> initCacheDir() async {
  final base = await getApplicationDocumentsDirectory();
  _cacheDir = Directory('${base.path}/osm_tiles');
  if (!_cacheDir!.existsSync()) _cacheDir!.createSync(recursive: true);
  await _migrateLegacyTiles();
}

/// Bug segnalato dopo il primo test sul campo (22/08/2026, punto 4b): prima
/// dello Step 49 i tile erano scritti direttamente sotto
/// `osm_tiles/{z}/{x}/{y}.png` (nessuna cartella di stile). Dallo Step 49 il
/// path è `osm_tiles/{styleId}/{z}/{x}/{y}.png` — senza migrazione, quei
/// tile restavano fisicamente sul disco (contavano nella dimensione cache
/// mostrata in "Mappe offline") ma [tileExists]/[getTileBytes] non li
/// avrebbero mai trovati: invisibili sia alla UI (nessuna regione dichiarata
/// per loro) sia alla navigazione. Eseguita una sola volta ad ogni avvio
/// (idempotente: dopo la prima esecuzione le cartelle legacy non esistono
/// più), assegnati allo stile 'osm' — l'unico esistente prima dello Step 49.
/// Un eventuale manifest v1 (`OfflineRegionInfo` senza `styleId`) non è
/// recuperabile (la chiave SharedPreferences è cambiata in
/// `offline_regions_meta_v2`): i tile tornano utilizzabili in navigazione,
/// ma non compaiono come una card "regione scaricata" in "Mappe offline"
/// finché non vengono ri-scaricati (a quel punto sovrascrivono gli stessi
/// file, nessun duplicato).
Future<void> _migrateLegacyTiles() async {
  final dir = _cacheDir;
  if (dir == null) return;
  try {
    final entries = dir.listSync();
    for (final entity in entries) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      // Le cartelle di stile ('osm'/'opentopomap') non sono mai numeriche —
      // solo le vecchie cartelle di zoom lo sono.
      if (int.tryParse(name) == null) continue;
      final z = name;
      final targetZDir = Directory('${dir.path}/osm/$z');
      if (!targetZDir.existsSync()) targetZDir.createSync(recursive: true);
      for (final xEntity in entity.listSync()) {
        if (xEntity is! Directory) continue;
        final x = xEntity.path.split(Platform.pathSeparator).last;
        final targetXDir = Directory('${targetZDir.path}/$x');
        if (!targetXDir.existsSync()) targetXDir.createSync(recursive: true);
        for (final yEntity in xEntity.listSync()) {
          if (yEntity is! File) continue;
          final y = yEntity.path.split(Platform.pathSeparator).last;
          final target = File('${targetXDir.path}/$y');
          if (!target.existsSync()) {
            try {
              await yEntity.copy(target.path);
            } catch (_) {
              continue;
            }
          }
        }
      }
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {
    // Best-effort: se la migrazione fallisce a metà, i tile legacy restano
    // semplicemente inutilizzabili come prima (nessuna perdita rispetto allo
    // stato attuale) — mai bloccare l'avvio della cache per questo.
  }
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
