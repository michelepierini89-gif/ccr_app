/// Step 49, Parte 1 — la cache offline scaricava tile su disco ma il
/// `TileLayer` in navigazione non li leggeva mai a runtime: la funzione
/// "Mappe offline" non serviva a nulla. Questo file verifica la parte che
/// causava il problema:
/// 1) lo schema di denominazione/cartelle scritto da [OfflineTileService]
///    è lo STESSO letto da [CcrTileProvider] (stesso metodo, quindi per
///    costruzione — qui si verifica il round-trip byte-per-byte);
/// 2) la cache è separata per stile (Step 49, Parte 2c): un tile scritto
///    per uno stile non deve mai risultare "presente" per l'altro;
/// 3) lo zoom oltre il nativo dello stile viene limitato (Parte 2d), non
///    scaricato/cachato inutilmente.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/map/map_style.dart';
import 'package:ccr_app/core/services/offline_tile_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ccr_offline_tiles_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await OfflineTileService.instance.init();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('cappedMaxZoomFor (Parte 2d — zoom oltre il nativo)', () {
    // Punto 4c del test sul campo 22/08/2026 — OSM è ora limitato a 17
    // come OpenTopoMap (era 19): con un nativo più alto del massimo
    // effettivamente scaricato da "Mappe offline", il TileLayer richiedeva
    // tile nativi mai scaricati, cadendo sul placeholder ("zone grigie")
    // anche dentro una regione dichiarata "scaricata". Vedi MapStyle.osm.
    test('OSM Standard è limitato a 17 come OpenTopoMap', () {
      expect(MapStyle.osm.maxNativeZoom, 17);
      expect(OfflineTileService.cappedMaxZoomFor('osm', 16), 16);
      expect(OfflineTileService.cappedMaxZoomFor('osm', 19), 17);
    });

    test(
        'OpenTopoMap viene limitato a 17 — verificato empiricamente: oltre, '
        'il server risponde con lo stesso tile upscalato', () {
      expect(MapStyle.openTopoMap.maxNativeZoom, 17);
      expect(OfflineTileService.cappedMaxZoomFor('opentopomap', 16), 16);
      expect(OfflineTileService.cappedMaxZoomFor('opentopomap', 19), 17);
    });
  });

  group('tilesForBoundingBox (schema z/x/y usato sia da download che da lettura)', () {
    test('un intervallo di zoom più ampio produce più tile, mai meno', () {
      const sw = LatLng(44.0, 10.0);
      const ne = LatLng(44.2, 10.2);
      final narrow = OfflineTileService.tilesForBoundingBox(
          sw: sw, ne: ne, minZoom: 12, maxZoom: 12);
      final wide = OfflineTileService.tilesForBoundingBox(
          sw: sw, ne: ne, minZoom: 12, maxZoom: 14);
      expect(wide.length, greaterThan(narrow.length));
    });

    test('stesso bbox e zoom produce sempre lo stesso elenco (deterministico)', () {
      const sw = LatLng(44.0, 10.0);
      const ne = LatLng(44.05, 10.05);
      final a = OfflineTileService.tilesForBoundingBox(
          sw: sw, ne: ne, minZoom: 13, maxZoom: 13);
      final b = OfflineTileService.tilesForBoundingBox(
          sw: sw, ne: ne, minZoom: 13, maxZoom: 13);
      expect(a, equals(b));
    });
  });

  group('cache su disco: round-trip e separazione per stile (Parte 1b/2c)', () {
    test('un tile scritto viene riletto identico dallo stesso path (z,x,y)', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await OfflineTileService.instance.writeTileBytes('osm', 5, 10, 20, bytes);
      final read = await OfflineTileService.instance.getTileBytes('osm', 5, 10, 20);
      expect(read, isNotNull);
      expect(read, bytes);
    });

    test(
        'un tile scritto per lo stile OSM NON risulta presente per '
        'OpenTopoMap alle stesse coordinate (z,x,y) — cache separata', () async {
      await OfflineTileService.instance
          .writeTileBytes('osm', 6, 1, 1, Uint8List.fromList([9, 9, 9]));
      final existsOsm = await OfflineTileService.instance.tileExists('osm', 6, 1, 1);
      final existsOtm =
          await OfflineTileService.instance.tileExists('opentopomap', 6, 1, 1);
      expect(existsOsm, isTrue);
      expect(existsOtm, isFalse);
    });
  });

  group('OfflineRegionInfo — round-trip di serializzazione', () {
    test('toJson/fromJson preserva tutti i campi mostrati in "Mappe offline"', () {
      final info = OfflineRegionInfo(
        eventId: 'ev1',
        eventNome: 'Rally Test',
        styleId: 'opentopomap',
        minZoom: 10,
        maxZoom: 16,
        tileCount: 1234,
        downloadedAt: DateTime(2026, 8, 20, 9, 30),
      );
      final roundTripped = OfflineRegionInfo.fromJson(info.toJson());
      expect(roundTripped.eventId, info.eventId);
      expect(roundTripped.eventNome, info.eventNome);
      expect(roundTripped.styleId, info.styleId);
      expect(roundTripped.minZoom, info.minZoom);
      expect(roundTripped.maxZoom, info.maxZoom);
      expect(roundTripped.tileCount, info.tileCount);
      expect(roundTripped.downloadedAt, info.downloadedAt);
    });
  });
}
