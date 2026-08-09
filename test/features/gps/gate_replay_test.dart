/// Test di regressione (Fix 5) — rigioca la traccia reale del test in moto
/// (evento "Enduro test 01": 6022 punti GPS del pilota, traccia di
/// riferimento KML da 1280 punti, 5 speciali con i loro waypoint) attraverso
/// [TrackReplayService.runFullPipeline] — la STESSA pipeline usata in
/// diretta e dal banco di replay admin, nessuna logica duplicata — e
/// verifica che le porte virtuali continuino ad agganciare esattamente come
/// nella validazione empirica di questo step.
///
/// Serve da rete di sicurezza: una futura modifica alla pipeline GPS/timing
/// (Kalman, filtro jump, porte virtuali, recovery) che silenziosamente
/// smettesse di agganciare una di queste porte farebbe fallire questo test
/// PRIMA di arrivare in produzione.
///
/// Nota sui timestamp: la traccia salvata per questo evento è `pilotTrack`
/// (solo lat/lng), antecedente all'introduzione di `pilotTrackFull` con
/// timestamp reali (Step 35) — non esiste una registrazione con timestamp
/// veri per questo test. Si usano timestamp sintetici a 1 secondo costante,
/// stessa scelta della validazione originale (Step 37 Parte 1E): geometria
/// reale, tempistica sintetica. I metodi di rilevamento verificati qui sono
/// quindi relativi a QUESTA cadenza campionaria.
///
/// PS3 FINE non aggancia per un motivo LEGITTIMO, confermato dall'utente:
/// durante questo test la squadra ha volutamente tagliato il percorso per
/// un problema in gara. La traiettoria reale (verificata anche sulla
/// traccia grezza, senza alcun gap GPS nelle vicinanze) non passa mai a
/// meno di ~386m dal waypoint di fine PS3 in tutta la sessione: è un fatto
/// reale, non un difetto della pipeline. Non deve MAI essere "risolto" —
/// se un cambiamento futuro lo facesse agganciare, sarebbe un segnale che
/// qualcosa nella logica di rilevamento è diventato troppo permissivo.
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
  late ReplayConfigResult result;

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
    result = await TrackReplayService.runFullPipeline(
      configNome: TrackReplayService.configGateRadius,
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
      firestoreService: FirestoreService(),
      prefs: prefs,
    );
  });

  ReplaySpecialResult forSpecial(String nome) =>
      result.speciali.firstWhere((s) => s.specialeNome == nome);

  test('fixture: 6022 punti pilota, 1280 punti traccia di riferimento, 5 speciali',
      () {
    expect(samples.length, 6022);
    expect(referenceTrack.length, 1280);
    expect(specials.length, 5);
  });

  test('PS1 inizio e fine agganciano con porta virtuale (metodo gate)', () {
    final ps1 = forSpecial('PS1');
    expect(ps1.metodoIngresso, 'gate');
    expect(ps1.metodoUscita, 'gate');
    expect(ps1.tempo, isNotNull);
  });

  test('PS2 inizio aggancia con porta, fine no — multipath documentato (Causa B)',
      () {
    final ps2 = forSpecial('PS2');
    expect(ps2.metodoIngresso, 'gate');
    // Cluster di jump GPS consecutivi con posizione sistematicamente
    // 65-100m fuori corridoio a ridosso della porta di fine: nessun
    // bridging può recuperare un dato mai misurato. Il tempo resta
    // comunque disponibile via il fallback esistente.
    expect(ps2.metodoUscita, isNot(anyOf('gate', 'gate_gap')));
    expect(ps2.tempo, isNotNull);
  });

  test(
      'PS3 inizio aggancia con porta, fine NON aggancia — ATTESO: taglio di '
      'percorso volontario in gara, non un difetto (vedi commento in cima al file)',
      () {
    final ps3 = forSpecial('PS3');
    expect(ps3.metodoIngresso, 'gate');
    expect(ps3.metodoUscita, isNot(anyOf('gate', 'gate_gap')));
    // Il tempo resta comunque calcolato (fallback), solo non affidabile:
    // ClassificaEngine lo marca con timingError per la verifica admin.
    expect(ps3.tempo, isNotNull);
  });

  test(
      'PS4 fine aggancia con porta virtuale a ~22m e NON viene sovrascritta '
      'da una recovery meno precisa (Fix 1/2)', () {
    final ps4 = forSpecial('PS4');
    expect(ps4.metodoUscita, anyOf('gate', 'gate_gap'));
    expect(ps4.distanzaUscitaM, isNotNull);
    expect(ps4.distanzaUscitaM!, lessThan(25.0));
  });

  test(
      'PS4 inizio resta a raggio/recovery — limite noto, non risolto dal Fix 3 '
      'su questi dati (il vero bearing locale, a finestra larga o stretta, è lo '
      'stesso entro 1°: il mismatch non è di orientamento)', () {
    final ps4 = forSpecial('PS4');
    expect(ps4.metodoIngresso, isNot(anyOf('gate', 'gate_gap')));
    expect(ps4.tempo, isNotNull);
  });

  test('PS5 inizio e fine agganciano con porta virtuale (metodo gate)', () {
    final ps5 = forSpecial('PS5');
    expect(ps5.metodoIngresso, 'gate');
    expect(ps5.metodoUscita, 'gate');
    expect(ps5.tempo, isNotNull);
  });

  test('almeno 7 porte su 10 agganciano con porta virtuale (gate/gate_gap)',
      () {
    var count = 0;
    for (final s in result.speciali) {
      if (s.metodoIngresso == 'gate' || s.metodoIngresso == 'gate_gap') {
        count++;
      }
      if (s.metodoUscita == 'gate' || s.metodoUscita == 'gate_gap') count++;
    }
    expect(count, greaterThanOrEqualTo(7));
  });

  test('tutte le 5 speciali producono comunque un tempo (nessun buco totale)',
      () {
    for (final s in result.speciali) {
      expect(s.tempo, isNotNull, reason: '${s.specialeNome} senza tempo');
    }
  });
}
