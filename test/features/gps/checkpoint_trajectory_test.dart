/// Test di regressione (Fix 1, 09/08/2026) — rigioca la traccia reale del
/// test in moto usata anche da `gate_replay_test.dart` ("Enduro test 01":
/// 6022 punti GPS, 5 speciali con 20 checkpoint in totale) attraverso
/// [TrackReplayService.runFullPipeline] DUE VOLTE sugli stessi campioni:
/// una con [legacyCheckpointDetection] true (raggio 20m + doppia conferma,
/// il comportamento in produzione prima di questo fix) e una con il nuovo
/// rilevamento su traiettoria (segmento, no doppia conferma, soglia 35m di
/// default) — per quantificare l'effetto del fix sugli stessi dati GPS
/// reali, senza bisogno di accesso a Firestore di produzione.
///
/// Non è la traccia dell'evento "Carring Clo 2 HB" (non disponibile in
/// questo ambiente di sviluppo, che non ha credenziali per Firestore di
/// produzione) — è comunque una traiettoria di guida reale, non sintetica,
/// quindi esercita davvero il caso "il passaggio più vicino cade tra due
/// fix consecutivi" o "appena oltre il vecchio raggio" che il fix indirizza.
/// Il confronto sull'evento reale va rieseguito dall'admin sullo schermo
/// "Replay traccia" (sorgente Firestore, entrambi i piloti) prima di
/// considerare il fix validato sul test del 09/08.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/track_replay_service.dart';
import 'package:ccr_app/core/services/track_smoother.dart';

List<LatLng> _loadFlatLatLng(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  final pts = <LatLng>[];
  for (var i = 0; i < raw.length; i += 2) {
    pts.add(LatLng((raw[i] as num).toDouble(), (raw[i + 1] as num).toDouble()));
  }
  return pts;
}

List<SpecialModel> _loadSpecials(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  return raw.map((e) => SpecialModel.fromMap(e as Map<String, dynamic>)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<RawTrackSample> samples;
  late List<SpecialModel> specials;
  late List<LatLng> referenceTrack;
  late ReplayConfigResult legacy;
  late ReplayConfigResult fixed;

  setUpAll(() async {
    final fixturesDir = '${Directory.current.path}/test/fixtures';
    final pilotTrack =
        _loadFlatLatLng('$fixturesDir/enduro_test_01_track.json');
    referenceTrack =
        _loadFlatLatLng('$fixturesDir/enduro_test_01_reference_track.json');
    specials = _loadSpecials('$fixturesDir/enduro_test_01_speciali.json');

    final sessionStart = DateTime(2026, 1, 1, 9, 0, 0);
    samples = [
      for (var i = 0; i < pilotTrack.length; i++)
        RawTrackSample(
          lat: pilotTrack[i].latitude,
          lng: pilotTrack[i].longitude,
          accuracy: 5.0,
          timestamp: sessionStart.add(Duration(seconds: i)),
        ),
    ];

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    legacy = await TrackReplayService.runFullPipeline(
      configNome: 'Legacy (raggio 20m + doppia conferma)',
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
      firestoreService: FirestoreService(),
      prefs: prefs,
      legacyCheckpointDetection: true,
    );
    fixed = await TrackReplayService.runFullPipeline(
      configNome: 'Fix 1 (traiettoria, no doppia conferma, 35m)',
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
      firestoreService: FirestoreService(),
      prefs: prefs,
    );
  });

  test('fixture: 20 checkpoint configurati su 5 speciali', () {
    final total =
        specials.fold<int>(0, (sum, s) => sum + s.controlPoints.length);
    expect(total, 20);
    // cpTotal è il conteggio dei CP CONFIGURATI (via gps.isWaypointPassed),
    // identico nelle due modalità — solo cpPassedCount cambia.
    expect(legacy.cpTotal, 20);
    expect(fixed.cpTotal, 20);
  });

  test('il Fix 1 non aggancia MENO checkpoint del comportamento storico', () {
    expect(fixed.cpPassedCount, greaterThanOrEqualTo(legacy.cpPassedCount));
  });

  test(
      'risultato empirico su questa fixture: legacy 15/20, fixed 16/20 '
      '— documentato, non un fallimento', () {
    // Su QUESTA traccia (campionamento sintetico 1Hz, non i 250ms reali in
    // speciale) il Fix 1 non guadagna CP aggiuntivi rispetto al proprio
    // 16/20: dei 4 CP mancati da `fixed`, 2 (track_pt_1028 a 314m,
    // track_pt_1105 a 595m) sono fuori traiettoria per un taglio di
    // percorso reale in questo test (stesso evento documentato in
    // gate_replay_test.dart per PS3), non un problema di campionamento;
    // gli altri 2 (track_pt_719 a 65m, track_pt_630 a 38m) restano oltre
    // la soglia anche a 35m.
    //
    // `legacy` è sceso da 16 a 15 allo Step 46 (soglia accuracy 8m→6m +
    // sigmaAccel adattivo alla curvatura, `gps_service.dart`): entrambe le
    // modalità leggono la STESSA traiettoria Kalman-filtrata (solo
    // l'algoritmo di detection cambia tra legacy/fixed), e lo spostamento
    // — di pochi metri, atteso e verificato utile sui dati reali "Carring
    // CLO 4" (vedi PROGETTO_CCR.md Step 46) — ha portato UN CP appena
    // sotto il raggio puntuale 20m del legacy leggermente oltre. `fixed`
    // (l'algoritmo realmente in uso oggi, soglia 35m su segmento) non ne
    // risente: resta 16/20, invariato. Nessuna azione richiesta: `legacy`
    // è mantenuto solo per il confronto A/B storico, non è mai eseguito
    // in produzione.
    expect(legacy.cpPassedCount, 15);
    expect(fixed.cpPassedCount, 16);
  });

  test('nessun checkpoint del Fix 1 rilevato oltre la soglia configurata',
      () {
    // Verifica di sanità sulla soglia: ogni CP EFFETTIVAMENTE AGGANCIATO
    // (cpPassedIds) dal nuovo percorso deve avere una distanza minima
    // <= 35m (default) — se questo fallisse vorrebbe dire che la soglia
    // non viene applicata. I CP non agganciati possono legittimamente
    // avere una distanza minima superiore (non sono stati registrati
    // proprio per questo).
    for (final id in fixed.cpPassedIds) {
      final dist = fixed.cpMinDistanceMeters[id];
      expect(dist, isNotNull, reason: 'checkpoint $id');
      expect(dist!, lessThanOrEqualTo(35.0), reason: 'checkpoint $id');
    }
  });
}
