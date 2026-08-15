/// Test di regressione (Step 43bis, "velocità display instabile") —
/// verifica la finestra mobile di [GpsService.displaySpeedKmh]
/// (`debugFeedDisplaySpeedSample`, hook di test che isola
/// `_updateDisplaySpeed` dal resto della pipeline Kalman/filtro jump) senza
/// toccare [GpsService.geometricSpeedKmh], che resta la velocità
/// istantanea usata dalla logica interna (filtro jump, sigmaAccel,
/// freeze bearing, dead reckoning) — vedi il commento in cima al getter.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/gps_service.dart';
import 'package:ccr_app/core/services/imu_fusion_service.dart';
import 'package:ccr_app/core/services/offline_queue_service.dart';

/// Sposta [from] di [distanceM] metri verso est (bearing 90°) — sufficiente
/// per generare una traccia rettilinea sintetica senza dipendere dalla
/// geometria completa usata altrove.
LatLng _moveEastMeters(LatLng from, double distanceM) {
  const earthRadiusM = 6371000.0;
  final dLng = (distanceM / earthRadiusM) * (180 / pi) /
      cos(from.latitude * pi / 180);
  return LatLng(from.latitude, from.longitude + dLng);
}

Future<GpsService> _buildGpsService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return GpsService(
    FirestoreService(),
    OfflineQueueService(prefs),
    ImuFusionService(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('da fermo, con jitter GPS entro pochi metri, il display mostra 0',
      () async {
    final gps = await _buildGpsService();
    final rnd = Random(42);
    final base = LatLng(45.0, 9.0);
    var ts = DateTime(2026, 1, 1, 10, 0, 0);

    // ~1.5m di jitter casuale attorno al punto fermo, un fix ogni 250ms:
    // esattamente lo scenario del bug (rumore GPS da fermo interpretato
    // come velocità apparente).
    for (var i = 0; i < 20; i++) {
      final jitterM = (rnd.nextDouble() - 0.5) * 3.0;
      gps.debugFeedDisplaySpeedSample(
          _moveEastMeters(base, jitterM), ts);
      ts = ts.add(const Duration(milliseconds: 250));
    }

    expect(gps.displaySpeedKmh, 0.0);
  });

  test('a velocità costante rumorosa, il display converge vicino al valore '
      'vero con oscillazioni molto minori della velocità istantanea',
      () async {
    final gps = await _buildGpsService();
    const trueSpeedKmh = 30.0;
    const trueSpeedMs = trueSpeedKmh / 3.6;
    const intervalMs = 250;
    final stepM = trueSpeedMs * (intervalMs / 1000.0);

    var pos = LatLng(45.0, 9.0);
    var ts = DateTime(2026, 1, 1, 10, 0, 0);
    final instantSpeeds = <double>[];
    final displaySpeeds = <double>[];

    // Rumore alternato di ampiezza paragonabile al passo vero: produce una
    // velocità istantanea punto-a-punto molto volatile (lo stesso ordine di
    // grandezza descritto nel bug reale), mentre la media sulla finestra
    // deve restare vicina al valore vero.
    for (var i = 0; i < 40; i++) {
      final noiseM = (i.isEven ? 1.4 : -1.4);
      final nextPos = _moveEastMeters(pos, stepM + noiseM);
      final nextTs = ts.add(const Duration(milliseconds: intervalMs));

      final instDistM = const Distance().as(LengthUnit.Meter, pos, nextPos);
      instantSpeeds.add((instDistM / (intervalMs / 1000.0)) * 3.6);

      gps.debugFeedDisplaySpeedSample(nextPos, nextTs);
      displaySpeeds.add(gps.displaySpeedKmh);

      pos = nextPos;
      ts = nextTs;
    }

    double stdDev(List<double> xs) {
      final mean = xs.reduce((a, b) => a + b) / xs.length;
      final variance =
          xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
              xs.length;
      return sqrt(variance);
    }

    // Solo la seconda metà: la finestra mobile deve essersi già riempita.
    final steadyInstant = instantSpeeds.sublist(20);
    final steadyDisplay = displaySpeeds.sublist(20);

    final instantStdDev = stdDev(steadyInstant);
    final displayStdDev = stdDev(steadyDisplay);

    expect(displayStdDev, lessThan(instantStdDev * 0.5));
    final displayMean =
        steadyDisplay.reduce((a, b) => a + b) / steadyDisplay.length;
    expect(displayMean, closeTo(trueSpeedKmh, 5.0));
  });
}
