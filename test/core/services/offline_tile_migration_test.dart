/// Punto 4b del test sul campo (22/08/2026) — verifica la migrazione dei
/// tile scaricati PRIMA dello Step 49, quando la cache non aveva ancora una
/// cartella per stile (`osm_tiles/{z}/{x}/{y}.png`, non
/// `osm_tiles/{styleId}/{z}/{x}/{y}.png`): senza migrazione quei tile
/// restavano fisicamente su disco ma invisibili sia a `tileExists`/
/// `getTileBytes` sia alla navigazione.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final legacyBytes = Uint8List.fromList([9, 8, 7, 6]);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir =
        await Directory.systemTemp.createTemp('ccr_offline_migration_test_');
    // Layout pre-Step-49: nessuna cartella di stile.
    final legacyDir = Directory('${tempDir.path}/osm_tiles/5/10');
    legacyDir.createSync(recursive: true);
    File('${legacyDir.path}/20.png').writeAsBytesSync(legacyBytes);

    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // La migrazione avviene dentro initCacheDir(), chiamata da init().
    await OfflineTileService.instance.init();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('un tile legacy diventa leggibile sotto lo stile osm dopo init()',
      () async {
    final exists = await OfflineTileService.instance.tileExists('osm', 5, 10, 20);
    expect(exists, isTrue);
    final bytes = await OfflineTileService.instance.getTileBytes('osm', 5, 10, 20);
    expect(bytes, legacyBytes);
  });

  test('la vecchia cartella di zoom (senza stile) non esiste più', () {
    expect(Directory('${tempDir.path}/osm_tiles/5').existsSync(), isFalse);
  });
}
