/// Test di regressione (Fix 17/08 — PS1 test "Carring CLO 4", provider
/// fused, DOOGEE Blade20 Pro): il log diagnostico di quel test mostrava un
/// recovery di inizio speciale scattato durante un tratto a segnale debole
/// (fix radi ogni 5-7s), tre secondi prima del primo fix realmente buono.
/// Un singolo fix accettato entro il raggio di recovery bastava a far
/// scattare l'apertura della PS, anche se isolato e non rappresentativo
/// della posizione reale.
///
/// Riproduce lo scenario con [TrackReplayService.runFullPipeline] — la
/// STESSA pipeline usata in diretta — verificando che il recovery richieda
/// ora un buffer di fix accettati denso e recente
/// ([GpsService.kMinRecoveryBufferFixes]/[GpsService.kMaxRecoveryLastFixAgeSeconds]),
/// non un singolo punto isolato.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/track_replay_service.dart';
import 'package:ccr_app/core/services/track_smoother.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const startLat = 43.91100;
  const startLng = 12.91700;
  // ~80m ad est del punto di inizio: dentro il raggio di recovery (120m) e
  // di trigger (3x120m), ma FUORI dal raggio di rilevamento diretto (10m)
  // — solo il recovery può "vedere" un fix qui, mai una detection diretta.
  const nearLat = 43.91100;
  const nearLng = 12.91790;

  final special = SpecialModel(
    id: 'ps-test',
    nome: 'PS Test',
    colorIndex: 0,
    ordine: 1,
    waypointInizio: const WaypointModel(
      id: 'wp-inizio',
      nome: 'Inizio',
      lat: startLat,
      lng: startLng,
      type: WaypointType.inizio,
    ),
    waypointFine: const WaypointModel(
      id: 'wp-fine',
      nome: 'Fine',
      lat: 43.91500,
      lng: 12.92100,
      type: WaypointType.fine,
    ),
  );

  Future<ReplayConfigResult> runScenario(List<RawTrackSample> samples) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return TrackReplayService.runFullPipeline(
      configNome: 'test-recovery-precondition',
      samples: samples,
      specials: [special],
      referenceTrack: const [], // nessuna porta virtuale: solo raggio/recovery
      firestoreService: FirestoreService(),
      prefs: prefs,
    );
  }

  List<RawTrackSample> buildSamples({required int acceptedCount}) {
    final sessionStart = DateTime(2026, 1, 1, 9, 0, 0);
    final samples = <RawTrackSample>[];

    // Fase 1 — 12 fix SCARTATI per accuratezza (200m, come il fix da cella
    // del log reale del 17/08), già vicino alla PS: non devono MAI entrare
    // nel buffer di recovery, indipendentemente da quanti sono. Copre anche
    // i primi 10s dall'avvio (nessuna detection/recovery in quella
    // finestra) — nessun fix accettato prima di questo punto, quindi
    // niente anchor precedente per il filtro jump (STEP 2), che lo salta
    // se [_lastAcceptedRawPos] è ancora null.
    for (var i = 0; i < 12; i++) {
      samples.add(RawTrackSample(
        lat: nearLat,
        lng: nearLng,
        accuracy: 200.0,
        timestamp: sessionStart.add(Duration(seconds: i)),
      ));
    }

    // Fase 2 — fix ACCETTATI (accuracy buona), stessa posizione a ~80m
    // dalla porta: prima di questo fix, uno solo di questi bastava a far
    // scattare il recovery.
    for (var i = 0; i < acceptedCount; i++) {
      samples.add(RawTrackSample(
        lat: nearLat,
        lng: nearLng,
        accuracy: 8.0,
        timestamp: sessionStart.add(Duration(seconds: 12 + i)),
      ));
    }
    return samples;
  }

  test(
      'nessun recovery si attiva su soli fix scartati per accuratezza '
      '(0 fix accettati)', () async {
    final result = await runScenario(buildSamples(acceptedCount: 0));
    expect(result.speciali.first.metodoIngresso, isNull);
  });

  test(
      'nessun recovery si attiva con meno di kMinRecoveryBufferFixes (5) '
      'fix accettati recenti (qui: 4)', () async {
    final result = await runScenario(buildSamples(acceptedCount: 4));
    expect(result.speciali.first.metodoIngresso, isNot('recovery'));
  });

  test(
      'il recovery si attiva non appena il buffer raggiunge '
      'kMinRecoveryBufferFixes (5) fix accettati, tutti recenti', () async {
    final result = await runScenario(buildSamples(acceptedCount: 5));
    expect(result.speciali.first.metodoIngresso, 'recovery');
  });
}
