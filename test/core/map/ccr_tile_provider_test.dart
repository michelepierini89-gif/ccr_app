/// Step 49, Parte 1e — verifica end-to-end nel modo più diretto possibile
/// senza un device fisico (nessun hardware collegato in questo ambiente,
/// stesso limite già annotato in PROGETTO_CCR.md per gli altri test su
/// device reale): "rete assente" è simulata con un host che rifiuta la
/// connessione istantaneamente (niente attesa di timeout/DNS, deterministico
/// invece che affidarsi a toggle di rete del sistema operativo, non
/// controllabili da questo ambiente). "Area scaricata" è simulata scrivendo
/// nella cache con lo stesso identico metodo (`writeTileBytes`) che
/// `downloadTile` usa a valle di un vero download — l'unica cosa che NON
/// viene esercitata qui è la chiamata HTTP reale del download stesso (già
/// verificata manualmente in questa sessione con curl su tile reali).
///
/// Prossimo step — da fare su un device reale quando disponibile: scaricare
/// un'area dalla UI, attivare la modalità aereo, verificare visivamente la
/// mappa in navigazione.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/map/ccr_tile_provider.dart';
import 'package:ccr_app/core/services/offline_tile_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Porta locale che rifiuta la connessione all'istante (nessun servizio in
/// ascolto) — simula "rete assente" senza i tempi morti di un vero timeout.
const _unreachableUrlTemplate = 'http://127.0.0.1:9/{z}/{x}/{y}.png';

Future<ImageInfo> _resolveImage(ImageProvider provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      stream.removeListener(listener);
      completer.complete(image);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ccr_tile_provider_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await OfflineTileService.instance.init();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
      'tile PRESENTE in cache resta navigabile anche con la rete assente '
      '(risolve dalla cache, mai dalla rete irraggiungibile)', () async {
    // "Area scaricata": stesso metodo che usa downloadTile a valle di un
    // vero download HTTP.
    await OfflineTileService.instance
        .writeTileBytes('osm', 8, 5, 5, TileProvider.transparentImage);

    final tileProvider = CcrTileProvider(styleId: 'osm');
    final layer = TileLayer(urlTemplate: _unreachableUrlTemplate);
    final image =
        tileProvider.getImage(const TileCoordinates(5, 5, 8), layer);

    final info = await _resolveImage(image);
    expect(info.image.width, greaterThan(0));
    expect(OfflineTileService.instance.lastServeSource.value,
        TileServeSource.cache);
  });

  test(
      'tile ASSENTE sia in cache che in rete non lascia un riquadro vuoto: '
      'sfondo neutro, la navigazione (traccia/marker) resta comunque possibile',
      () async {
    final tileProvider = CcrTileProvider(styleId: 'osm');
    final layer = TileLayer(urlTemplate: _unreachableUrlTemplate);
    // Coordinate mai scritte in cache in questo test.
    final image =
        tileProvider.getImage(const TileCoordinates(9, 9, 8), layer);

    final info = await _resolveImage(image);
    expect(info.image.width, greaterThan(0));
    expect(OfflineTileService.instance.lastServeSource.value,
        TileServeSource.placeholder);
    expect(OfflineTileService.instance.networkReachable.value, isFalse);
  });
}
