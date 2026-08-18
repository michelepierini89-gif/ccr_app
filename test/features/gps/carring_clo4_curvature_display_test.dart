/// Seguito allo Step 45/46 sui dati reali del test "Carring CLO 4" (stessi
/// fixture: `test/fixtures/carring_clo4_20260817_*`). Tre verifiche
/// richieste dall'utente dopo il primo report:
///
/// A) Confronto soglia accuracy 6m (nuovo default) vs 8m (precedente):
///    percentuale di fix scartati, per verificare che il nuovo default non
///    apra buchi di traccia significativi.
/// B) Griglia sul fattore di adattamento alla curvatura
///    ([GpsPipelineConfig.curvatureAdaptationFactor], Step 46): metrica
///    sui tratti ad alta velocità angolare (>15°/s) prima/dopo, e verifica
///    che non peggiori la precisione di aggancio delle porte virtuali.
/// C) Posizione di DISPLAY (quella che vede il pilota: Kalman + dead
///    reckoning + predizione) contro quella REGISTRATA (solo Kalman) —
///    finora la griglia misurava solo la seconda.
///
/// Nota metodologica su (C): non è un replay dei sensori reali (nessun
/// accelerometro/giroscopio/bussola esiste per una sessione storica, solo
/// fix GPS). Ricostruisce la GEOMETRIA del dead reckoning di
/// [ImuFusionService] (stessi parametri: blend GPS 95%/5%
/// [kGpsWeight], finestra massima di predizione 800ms
/// [kMaxPredictionWindowMs], soglia minima 5km/h
/// [kMinPredictionSpeedKmh], proiezione rettilinea via
/// [LocationUtils.destinationPoint] — analoga a
/// [ImuFusionService._movePosition]) alimentata da velocità/bearing
/// derivati dai fix GPS invece che da accelerometro reale, usando SEMPRE
/// e SOLO l'ultimo bearing/velocità OSSERVATI prima del fix corrente (mai
/// il segmento del fix stesso, che il sistema reale non può conoscere in
/// anticipo) — isola esattamente l'ipotesi di moto rettilineo che produce
/// l'artefatto "taglio in curva" descritto.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/gps_service.dart';
import 'package:ccr_app/core/services/imu_fusion_service.dart';
import 'package:ccr_app/core/services/offline_queue_service.dart';
import 'package:ccr_app/core/services/track_replay_service.dart';
import 'package:ccr_app/core/services/track_smoother.dart';
import 'package:ccr_app/core/utils/location_utils.dart';

class _Stats {
  final double mean, median, p95, max;
  const _Stats(this.mean, this.median, this.p95, this.max);

  static _Stats of(List<double> values) {
    if (values.isEmpty) return const _Stats(0, 0, 0, 0);
    final sorted = [...values]..sort();
    final n = sorted.length;
    final mean = sorted.reduce((a, b) => a + b) / n;
    final median =
        n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
    final p95Idx = (n * 0.95).floor().clamp(0, n - 1);
    return _Stats(mean, median, sorted[p95Idx], sorted.last);
  }

  @override
  String toString() => 'media=${mean.toStringAsFixed(1)}m '
      'mediana=${median.toStringAsFixed(1)}m '
      'p95=${p95.toStringAsFixed(1)}m max=${max.toStringAsFixed(1)}m';
}

double _distanceToReferenceMeters(LatLng p, List<LatLng> reference) {
  var best = double.infinity;
  for (var i = 0; i < reference.length - 1; i++) {
    final d = LocationUtils.distanceToSegmentMeters(
      p.latitude,
      p.longitude,
      reference[i].latitude,
      reference[i].longitude,
      reference[i + 1].latitude,
      reference[i + 1].longitude,
    );
    if (d < best) best = d;
  }
  return best;
}

Position _toPosition(RawTrackSample s) => Position(
      latitude: s.lat,
      longitude: s.lng,
      timestamp: s.timestamp,
      accuracy: s.accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Esegue la pipeline completa con [config] e ritorna la traccia REGISTRATA
/// (`fullTrackSamples`, un punto per OGNI fix accettato — non
/// `localTrack`, che è ulteriormente filtrata dall'anchor display: qui
/// serve la serie completa per l'allineamento 1:1 col dead reckoning in
/// (C) e per un conteggio accettati/scartati esatto in (A)).
Future<List<RawTrackSample>> _runAndGetAccepted(
  List<RawTrackSample> samples,
  List<SpecialModel> specials,
  List<LatLng> referenceTrack,
  FirestoreService fs,
  SharedPreferences prefs,
  GpsPipelineConfig config,
) async {
  final allWaypoints = [
    for (final s in specials) ...[
      s.waypointInizio,
      s.waypointFine,
      ...s.controlPoints,
    ],
  ];
  final gps = GpsService(
    fs,
    OfflineQueueService(prefs),
    ImuFusionService(),
    null,
    null,
    null,
    null,
    config,
  );
  gps.startReplaySession(
    waypoints: allWaypoints,
    specials: specials,
    referenceTrack: referenceTrack,
    sessionStart: samples.first.timestamp,
  );
  for (final s in samples) {
    await gps.ingestReplaySample(_toPosition(s), s.timestamp);
  }
  await gps.closeAllOpenSpecialsAt(samples.last.timestamp);
  gps.endReplaySession();
  final accepted = gps.fullTrackSamples;
  gps.dispose();
  return accepted;
}

/// (C) — vedi nota metodologica in cima al file. Ritorna la posizione
/// PREDETTA (pre-ancora GPS) per ogni intervallo: è quella che il pilota
/// vede sullo schermo per TUTTA la durata del gap fra un fix e il
/// successivo (fino all'istante prima della correzione) — il momento di
/// massima estrapolazione, il più visibile. La posizione post-blend serve
/// solo come punto di partenza per la predizione successiva (continuità),
/// non è quello che si confronta col percorso di riferimento.
List<LatLng> _reconstructDisplayTrack(List<RawTrackSample> accepted,
    {bool deadReckoningEnabled = true}) {
  if (accepted.length < 2) {
    return accepted.map((s) => LatLng(s.lat, s.lng)).toList();
  }
  const kGpsWeight = 0.95; // ImuFusionService.updateWithGps
  const kMaxPredictionWindowS = 0.8; // ImuFusionService.kMaxPredictionWindowMs
  const kMinPredictionSpeedKmh = 5.0; // ImuFusionService.kMinPredictionSpeedKmh

  // predicted[i]: posizione mostrata appena PRIMA che arrivi accepted[i]
  // (per accepted[0] non c'è predizione: è l'anchor iniziale).
  final predicted = <LatLng>[LatLng(accepted.first.lat, accepted.first.lng)];
  var correctedPos = predicted.first; // per la continuità della predizione
  double? lastKnownBearingDeg;
  double lastKnownSpeedKmh = 0.0;

  for (var i = 1; i < accepted.length; i++) {
    final prev = accepted[i - 1];
    final curr = accepted[i];
    final dtS = curr.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;

    // Predizione dalla posizione CORRETTA precedente, usando SOLO ciò che
    // era noto PRIMA di questo fix (bearing/velocità del segmento
    // precedente) — questo è il valore che finisce nel confronto. Con
    // [deadReckoningEnabled]=false resta ancorata (solo blend GPS sotto,
    // nessuna estrapolazione) — la stessa disattivazione richiesta.
    var predictedPos = correctedPos;
    if (deadReckoningEnabled &&
        lastKnownBearingDeg != null &&
        lastKnownSpeedKmh >= kMinPredictionSpeedKmh &&
        dtS > 0) {
      final predictS = dtS.clamp(0.0, kMaxPredictionWindowS);
      final distM = (lastKnownSpeedKmh / 3.6) * predictS;
      final dest = LocationUtils.destinationPoint(
          correctedPos.latitude, correctedPos.longitude, lastKnownBearingDeg, distM);
      predictedPos = LatLng(dest[0], dest[1]);
    }
    predicted.add(predictedPos);

    // Ancora GPS (stesso blend 95/5 del codice reale) — solo per il punto
    // di partenza della PROSSIMA predizione, non per il confronto di
    // questo punto.
    correctedPos = LatLng(
      kGpsWeight * curr.lat + (1 - kGpsWeight) * predictedPos.latitude,
      kGpsWeight * curr.lng + (1 - kGpsWeight) * predictedPos.longitude,
    );

    // Ora "impariamo" bearing/velocità di QUESTO segmento — usati per
    // predire il PROSSIMO, mai per il corrente (niente preveggenza).
    if (dtS > 0) {
      lastKnownBearingDeg =
          LocationUtils.bearingDegrees(prev.lat, prev.lng, curr.lat, curr.lng);
      final distM =
          LocationUtils.haversineDistance(prev.lat, prev.lng, curr.lat, curr.lng);
      lastKnownSpeedKmh = (distM / dtS) * 3.6;
    }
  }
  return predicted;
}

/// Marca gli indici (nella stessa serie di [accepted]) che cadono su un
/// tratto ad alta velocità angolare (>15°/s tra bearing di segmenti
/// adiacenti) — stessa definizione della griglia Step 45.
Set<int> _highCurvatureIndices(List<RawTrackSample> accepted) {
  final idx = <int>{};
  for (var i = 1; i < accepted.length - 1; i++) {
    final b1 = LocationUtils.bearingDegrees(accepted[i - 1].lat,
        accepted[i - 1].lng, accepted[i].lat, accepted[i].lng);
    final b2 = LocationUtils.bearingDegrees(
        accepted[i].lat, accepted[i].lng, accepted[i + 1].lat, accepted[i + 1].lng);
    var diff = (b2 - b1).abs();
    if (diff > 180) diff = 360 - diff;
    final dtS = accepted[i + 1]
            .timestamp
            .difference(accepted[i].timestamp)
            .inMilliseconds /
        1000.0;
    if (dtS > 0 && diff / dtS > 15.0) idx.add(i);
  }
  return idx;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixturesDir = '${Directory.current.path}/test/fixtures';
  late List<RawTrackSample> samples;
  late List<SpecialModel> specials;
  late List<LatLng> referenceTrack;

  setUpAll(() {
    final rawTrack = jsonDecode(
        File('$fixturesDir/carring_clo4_20260817_track.json')
            .readAsStringSync()) as List<dynamic>;
    samples = rawTrack.map((e) {
      final m = e as Map<String, dynamic>;
      return RawTrackSample(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        accuracy: (m['accuracy'] as num).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((m['ts'] as num).toInt()),
      );
    }).toList();

    final rawSpecials = jsonDecode(
        File('$fixturesDir/carring_clo4_20260817_speciali.json')
            .readAsStringSync()) as List<dynamic>;
    specials = rawSpecials
        .map((e) => SpecialModel.fromMap(e as Map<String, dynamic>))
        .toList();

    final flatRef = jsonDecode(
        File('$fixturesDir/carring_clo4_20260817_reference_track.json')
            .readAsStringSync()) as List<dynamic>;
    referenceTrack = [
      for (var i = 0; i < flatRef.length; i += 2)
        LatLng((flatRef[i] as num).toDouble(),
            (flatRef[i + 1] as num).toDouble()),
    ];
  });

  test('A) confronto fix scartati: soglia accuracy 6m (nuovo) vs 8m (precedente)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fs = FirestoreService();

    final results = <double, List<RawTrackSample>>{};
    for (final acc in [6.0, 8.0]) {
      results[acc] = await _runAndGetAccepted(
        samples,
        specials,
        referenceTrack,
        fs,
        prefs,
        GpsPipelineConfig(
            maxAccuracyDisplayMeters: acc, curvatureAdaptationFactor: 0.0),
      );
    }

    final total = samples.length;
    final accepted6 = results[6.0]!.length;
    final accepted8 = results[8.0]!.length;
    final discard6 = (total - accepted6) * 100.0 / total;
    final discard8 = (total - accepted8) * 100.0 / total;

    // ignore: avoid_print
    print('--- A) Confronto soglia accuracy ---\n'
        'totale campioni: $total\n'
        '6m: accettati=$accepted6 (${(100 - discard6).toStringAsFixed(1)}%) '
        'scartati=${discard6.toStringAsFixed(1)}%\n'
        '8m: accettati=$accepted8 (${(100 - discard8).toStringAsFixed(1)}%) '
        'scartati=${discard8.toStringAsFixed(1)}%\n'
        'differenza scarto: ${(discard6 - discard8).toStringAsFixed(1)} punti percentuali');

    expect(accepted6, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('B) griglia fattore di curvatura: metrica alta-curvatura + precisione porte',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fs = FirestoreService();

    const factors = [0.0, 0.02, 0.035, 0.05, 0.08, 0.15];
    final rows = <String>[];
    rows.add('fattore  scostamento-generale                          '
        'alta-curvatura(>15°/s)                            gate-precision');

    for (final factor in factors) {
      final config = GpsPipelineConfig(
        maxAccuracyDisplayMeters: 6.0,
        curvatureAdaptationFactor: factor,
      );
      final accepted = await _runAndGetAccepted(
          samples, specials, referenceTrack, fs, prefs, config);

      final highCurv = _highCurvatureIndices(accepted);
      final allDev = <double>[];
      final curvDev = <double>[];
      for (var i = 0; i < accepted.length; i++) {
        final d = _distanceToReferenceMeters(
            LatLng(accepted[i].lat, accepted[i].lng), referenceTrack);
        allDev.add(d);
        if (highCurv.contains(i)) curvDev.add(d);
      }

      // Precisione porte virtuali: media delle distanze di aggancio gate
      // disponibili per questa config (stesso identico banco di replay
      // "Porta + raggio" — nessuna logica duplicata).
      final gateResult = await TrackReplayService.runFullPipeline(
        configNome: 'curvature-$factor',
        samples: samples,
        specials: specials,
        referenceTrack: referenceTrack,
        firestoreService: fs,
        prefs: prefs,
        pipelineConfig: config,
      );
      final gateDistances = <double>[
        for (final s in gateResult.speciali) ...[
          if (s.distanzaIngressoM != null) s.distanzaIngressoM!,
          if (s.distanzaUscitaM != null) s.distanzaUscitaM!,
        ],
      ];
      final gateCount = gateResult.speciali
          .where((s) =>
              s.metodoIngresso == 'gate' || s.metodoIngresso == 'gate_gap')
          .length +
          gateResult.speciali
              .where((s) =>
                  s.metodoUscita == 'gate' || s.metodoUscita == 'gate_gap')
              .length;
      final gateDistAvg = gateDistances.isEmpty
          ? null
          : gateDistances.reduce((a, b) => a + b) / gateDistances.length;

      rows.add('${factor.toStringAsFixed(3).padRight(8)} '
          '${_Stats.of(allDev).toString().padRight(53)} '
          '${_Stats.of(curvDev).toString().padRight(51)} '
          'porte-agganciate=$gateCount distMedia=${gateDistAvg?.toStringAsFixed(1) ?? '-'}m');
    }

    // ignore: avoid_print
    print('--- B) Griglia fattore di curvatura ---\n${rows.join('\n')}');
    expect(rows.length, greaterThan(1));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('C) posizione di DISPLAY (Kalman+dead reckoning) vs REGISTRATA (solo Kalman)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fs = FirestoreService();

    // Config di produzione decisa oggi (accuracy 6m, curvatura 0.035).
    final config = GpsPipelineConfig(
      maxAccuracyDisplayMeters: 6.0,
      curvatureAdaptationFactor: GpsService.kDefaultCurvatureAdaptationFactor,
    );
    final accepted = await _runAndGetAccepted(
        samples, specials, referenceTrack, fs, prefs, config);
    // Tre serie sugli stessi punti: REGISTRATA (solo Kalman, mai mostrata
    // al pilota, è il dato usato per timing/griglia Step 45), DISPLAY con
    // dead reckoning (quello che il pilota vede oggi), DISPLAY senza dead
    // reckoning (solo ancora GPS — la disattivazione richiesta).
    final displayDrOn = _reconstructDisplayTrack(accepted);
    final displayDrOff =
        _reconstructDisplayTrack(accepted, deadReckoningEnabled: false);
    final highCurv = _highCurvatureIndices(accepted);

    final registeredAll = <double>[];
    final drOnAll = <double>[];
    final drOffAll = <double>[];
    final registeredCurv = <double>[];
    final drOnCurv = <double>[];
    final drOffCurv = <double>[];

    for (var i = 0; i < accepted.length; i++) {
      final regDev = _distanceToReferenceMeters(
          LatLng(accepted[i].lat, accepted[i].lng), referenceTrack);
      final drOnDev = _distanceToReferenceMeters(displayDrOn[i], referenceTrack);
      final drOffDev =
          _distanceToReferenceMeters(displayDrOff[i], referenceTrack);
      registeredAll.add(regDev);
      drOnAll.add(drOnDev);
      drOffAll.add(drOffDev);
      if (highCurv.contains(i)) {
        registeredCurv.add(regDev);
        drOnCurv.add(drOnDev);
        drOffCurv.add(drOffDev);
      }
    }

    final regAllStats = _Stats.of(registeredAll);
    final drOnAllStats = _Stats.of(drOnAll);
    final drOffAllStats = _Stats.of(drOffAll);
    final regCurvStats = _Stats.of(registeredCurv);
    final drOnCurvStats = _Stats.of(drOnCurv);
    final drOffCurvStats = _Stats.of(drOffCurv);

    String pctRel(double display, double baseline) =>
        baseline == 0 ? '-' : ((display - baseline) * 100 / baseline).toStringAsFixed(0);

    // ignore: avoid_print
    print('--- C) Display vs Registrata (config: accuracy 6m, curvatura '
        '${GpsService.kDefaultCurvatureAdaptationFactor}) ---\n'
        'REGISTRATA (solo Kalman, mai mostrata al pilota) — generale: $regAllStats\n'
        'DISPLAY con dead reckoning (oggi)                — generale: $drOnAllStats '
        '(${pctRel(drOnAllStats.mean, regAllStats.mean)}% vs registrata)\n'
        'DISPLAY senza dead reckoning (solo ancora GPS)    — generale: $drOffAllStats '
        '(${pctRel(drOffAllStats.mean, regAllStats.mean)}% vs registrata)\n'
        '\n'
        'REGISTRATA                    — alta curvatura (>15°/s): $regCurvStats\n'
        'DISPLAY con dead reckoning     — alta curvatura (>15°/s): $drOnCurvStats '
        '(${pctRel(drOnCurvStats.mean, regCurvStats.mean)}% vs registrata)\n'
        'DISPLAY senza dead reckoning   — alta curvatura (>15°/s): $drOffCurvStats '
        '(${pctRel(drOffCurvStats.mean, regCurvStats.mean)}% vs registrata)\n'
        'guadagno disattivando DR in curva: '
        '${(drOnCurvStats.mean - drOffCurvStats.mean).toStringAsFixed(1)}m\n'
        'punti totali: ${accepted.length}, punti alta curvatura: ${highCurv.length}');

    expect(displayDrOn.length, accepted.length);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
