/// Griglia parametrica (Blocco E, richiesta 17/08) sui dati REALI del test
/// "Carring CLO 4": traccia completa del pilota DOOGEE Blade20 Pro
/// (`test/fixtures/carring_clo4_20260817_track.json`, 2809 campioni con
/// timestamp reali, source=fullTrackChunks — la stessa identica traccia
/// usata da [GpsService.fullTrackSamples]/`_recoveryTrack`, non un
/// sottoinsieme filtrato) contro il percorso di riferimento reale
/// (`carring_clo4_20260817_reference_track.json`, dal KML caricato
/// dall'admin per l'evento, 740 punti).
///
/// NON è un test di regressione (nessuna soglia pass/fail sui numeri): gira
/// la griglia e STAMPA i risultati — la tabella e la raccomandazione vanno
/// nel report all'utente, non ancora nei default di produzione (vedi
/// GpsPipelineConfig — additivo, i default restano quelli di sempre finché
/// non decisi altrimenti).
///
/// Assi coperti — solo quelli effettivamente parametrizzabili nella
/// pipeline reale (vedi GpsPipelineConfig, gps_service.dart):
///   - sigmaAccelScale: moltiplicatore sui 3 livelli di sigmaAccel esistenti
///   - maxAccuracyDisplayMeters: soglia accuracy (fase stabile)
///   - maxSpeedFilterKmh: soglia filtro jump
///   - RTS: on (config "Porta + RTS", TrackSmoother) / off (config
///     "Porta + raggio", pipeline Kalman standard) — asse completamente
///     indipendente e già disponibile, nessuna modifica necessaria.
///
/// NON incluso nella griglia:
///   - anchorThresholdScale: parametrizzato in GpsPipelineConfig ma escluso
///     da questa griglia per contenerne la dimensione (isolato a 1.0).
///   - un "fattore di adattamento alla curvatura" per sigmaAccel NON esiste
///     nel codice attuale (sigmaAccel dipende solo da 3 fasce di velocità
///     geometrica, mai dalla curvatura/velocità angolare) — vedi report,
///     nessun numero fabbricato per un meccanismo che non esiste.
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

class _GridResult {
  final _Stats overall;
  final _Stats highCurvature;
  final double implausiblePct;
  final int trackPoints;
  const _GridResult(
      this.overall, this.highCurvature, this.implausiblePct, this.trackPoints);
}

/// Analizza [track] (la polyline display — [GpsService.localTrack] a fine
/// run, cioè esattamente ciò che verrebbe salvato/mostrato al pilota) con
/// [ts] (un timestamp per ogni punto di [track], vedi [_alignTimestamps])
/// contro [reference]: scostamento punto-poligonale per ogni punto, quali
/// punti cadono su un tratto ad alta velocità angolare (>15°/s tra i
/// bearing dei segmenti adiacenti), e percentuale di segmenti con velocità
/// implicita > [evalMaxKmh] (soglia di VALUTAZIONE fissa, indipendente
/// dalla soglia jump della config in prova — misura il danno reale
/// sull'output di averla allentata, non solo se il filtro l'ha bloccata).
_GridResult _analyze(
    List<LatLng> track, List<DateTime> ts, List<LatLng> reference,
    {double evalMaxKmh = 120.0}) {
  if (track.length < 3) {
    return const _GridResult(_Stats(0, 0, 0, 0), _Stats(0, 0, 0, 0), 0, 0);
  }
  final allDev = <double>[];
  final curvDev = <double>[];
  var implausible = 0;
  var speedSamples = 0;

  for (var i = 0; i < track.length; i++) {
    allDev.add(_distanceToReferenceMeters(track[i], reference));

    if (i > 0) {
      final dtS = ts[i].difference(ts[i - 1]).inMilliseconds / 1000.0;
      if (dtS > 0) {
        final distM = LocationUtils.haversineDistance(track[i - 1].latitude,
            track[i - 1].longitude, track[i].latitude, track[i].longitude);
        speedSamples++;
        if ((distM / dtS) * 3.6 > evalMaxKmh) implausible++;
      }
    }

    if (i > 0 && i < track.length - 1) {
      final b1 = LocationUtils.bearingDegrees(track[i - 1].latitude,
          track[i - 1].longitude, track[i].latitude, track[i].longitude);
      final b2 = LocationUtils.bearingDegrees(track[i].latitude,
          track[i].longitude, track[i + 1].latitude, track[i + 1].longitude);
      var diff = (b2 - b1).abs();
      if (diff > 180) diff = 360 - diff;
      final dtS = ts[i + 1].difference(ts[i]).inMilliseconds / 1000.0;
      if (dtS > 0 && diff / dtS > 15.0) curvDev.add(allDev.last);
    }
  }

  return _GridResult(
    _Stats.of(allDev),
    _Stats.of(curvDev),
    speedSamples == 0 ? 0 : implausible * 100.0 / speedSamples,
    track.length,
  );
}

/// [track] ([GpsService.localTrack], post STEP4-anchor) non porta
/// timestamp propri, ma è un sottoinsieme dei valori Kalman-filtrati in
/// [fullSamples] ([GpsService.fullTrackSamples], un campione per OGNI fix
/// accettato, con timestamp) — le stesse identiche coordinate in virgola
/// mobile, mai ricalcolate, perché entrambe scrivono lo stesso `filteredPos`
/// dentro la stessa chiamata a `_onPosition`. Bastano quindi un confronto
/// diretto e un puntatore che avanza in ordine cronologico (mai
/// all'indietro, track e fullSamples condividono lo stesso ordine).
List<DateTime> _alignTimestamps(
    List<LatLng> track, List<RawTrackSample> fullSamples) {
  final out = <DateTime>[];
  var si = 0;
  for (final p in track) {
    while (si < fullSamples.length - 1 &&
        (fullSamples[si].lat != p.latitude ||
            fullSamples[si].lng != p.longitude)) {
      si++;
    }
    out.add(fullSamples[si].timestamp);
  }
  return out;
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

  test('fixture: campioni/speciali/riferimento caricati', () {
    expect(samples.length, 2809);
    expect(specials.length, 4);
    expect(referenceTrack.length, 740);
  });

  test('griglia parametrica su sigmaAccel/soglie accuracy/jump + RTS',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fs = FirestoreService();
    final allWaypoints = [
      for (final s in specials) ...[
        s.waypointInizio,
        s.waypointFine,
        ...s.controlPoints,
      ],
    ];

    // Griglia deliberatamente contenuta (27 combinazioni Kalman/soglie + 1
    // run RTS indipendente): ogni run rigioca 2809 campioni attraverso la
    // pipeline completa reale — l'obiettivo è dare numeri VERI su cui
    // decidere, non un'esplorazione esaustiva.
    const sigmaScales = [0.5, 1.0, 2.0];
    const accuracyThresholds = [6.0, 8.0, 12.0];
    const jumpThresholds = [90.0, 120.0, 160.0];

    final rows = <String>[];
    rows.add('sigmaScale  accMax(m)  jumpMax(km/h)  puntiTrack  '
        'overall (media/mediana/p95/max)                 '
        'altaCurvatura(>15°/s)                            implausibili%');

    for (final sigma in sigmaScales) {
      for (final acc in accuracyThresholds) {
        for (final jump in jumpThresholds) {
          final config = GpsPipelineConfig(
            sigmaAccelScale: sigma,
            maxAccuracyDisplayMeters: acc,
            maxSpeedFilterKmh: jump,
          );

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

          final track = gps.localTrack;
          // Letto PRIMA di dispose() (vedi doc di fullTrackSamples).
          final fullSamples = gps.fullTrackSamples;
          final ts = _alignTimestamps(track, fullSamples);
          final r = _analyze(track, ts, referenceTrack);

          rows.add(
              '${sigma.toStringAsFixed(1).padRight(11)} ${acc.toStringAsFixed(0).padRight(10)} '
              '${jump.toStringAsFixed(0).padRight(14)} ${r.trackPoints.toString().padRight(11)} '
              '${r.overall.toString().padRight(49)} ${r.highCurvature.toString().padRight(49)} '
              '${r.implausiblePct.toStringAsFixed(2)}%');

          gps.dispose();
        }
      }
    }

    // Run RTS di riferimento (indipendente dagli assi sopra: bypassa
    // Kalman/soglie, opera solo sui campioni grezzi).
    final rtsResult = await TrackReplayService.runFullPipeline(
      configNome: 'rts-reference',
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
      firestoreService: fs,
      prefs: prefs,
    );
    rows.add('--- RTS (Porta + RTS, indipendente dagli assi sopra) ---');
    rows.add('speciali con esito temporale: '
        '${rtsResult.speciali.where((s) => s.tempo != null).length}/${rtsResult.speciali.length}');

    // ignore: avoid_print
    print(rows.join('\n'));

    expect(rows.length, greaterThan(1));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
