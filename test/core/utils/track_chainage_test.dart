/// Test per [TrackChainage] (Step 47) — le distanze usate per avvisi
/// vocali/banner devono essere quelle REALI da percorrere lungo la
/// traccia, non in linea d'aria: su un percorso di montagna un punto
/// vicino d'aria può essere lontanissimo da percorrere (tornante) e uno
/// oltre una valle può essere vicinissimo d'aria e lontanissimo da
/// raggiungere.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccr_app/core/utils/track_chainage.dart';
import 'package:ccr_app/core/utils/location_utils.dart';

void main() {
  // Tornante stretto: gamba 1 verso est (~79m), tornante verso nord
  // (~56m), gamba 2 verso ovest parallela alla gamba 1 (~79m) — un punto
  // sulla gamba 2 è vicinissimo IN LINEA D'ARIA a un punto sulla gamba 1
  // (solo i ~56m del tornante), ma per percorrerlo bisogna fare tutto il
  // giro (gamba1 + tornante + gamba2).
  final hairpinTrack = <LatLng>[
    for (var i = 0; i <= 10; i++) LatLng(45.0, 7.0 + i * 0.0001), // gamba 1
    for (var i = 1; i <= 5; i++)
      LatLng(45.0 + i * 0.0001, 7.001), // tornante
    for (var i = 1; i <= 10; i++)
      LatLng(45.0005, 7.001 - i * 0.0001), // gamba 2 (parallela, verso ovest)
  ];

  late TrackChainage chainage;

  setUp(() {
    chainage = TrackChainage.build(hairpinTrack);
  });

  test('la progressiva cresce lungo la traccia (monotona)', () {
    final pStart = chainage.project(hairpinTrack.first);
    final pEnd = chainage.project(hairpinTrack.last);
    expect(pStart, isNotNull);
    expect(pEnd, isNotNull);
    expect(pEnd!.progressiveM, greaterThan(pStart!.progressiveM));
    expect(pStart.progressiveM, closeTo(0, 0.5));
    expect(pEnd.progressiveM, closeTo(chainage.totalLengthM, 0.5));
  });

  test(
      'un punto oltre il tornante ha distanza di PERCORSO molto maggiore '
      'della distanza IN LINEA D\'ARIA', () {
    // Pilota all'inizio della gamba 1.
    final pilot = hairpinTrack.first;
    // Punto di interesse alla fine della gamba 2 — geograficamente vicino
    // al pilota (dall'altra parte del tornante), ma raggiungibile solo
    // percorrendo l'intero giro.
    final point = hairpinTrack.last;

    final airDistanceM = LocationUtils.haversineDistance(
        pilot.latitude, pilot.longitude, point.latitude, point.longitude);

    final pilotProj = chainage.project(pilot);
    final pointProj = chainage.project(point);
    expect(pilotProj, isNotNull);
    expect(pointProj, isNotNull);
    final pathDistanceM = pointProj!.progressiveM - pilotProj!.progressiveM;

    // La distanza d'aria è piccola (solo l'ampiezza del tornante, ~56m);
    // quella di percorso è l'intero giro (~213m) — un rapporto netto,
    // non un margine di arrotondamento.
    expect(airDistanceM, lessThan(80));
    expect(pathDistanceM, greaterThan(190));
    expect(pathDistanceM, greaterThan(airDistanceM * 2));
  });

  test(
      'un punto già superato dal pilota risulta a distanza NEGATIVA (non '
      'va annunciato)', () {
    // Pilota avanzato quasi in fondo alla gamba 2.
    final pilot = hairpinTrack[hairpinTrack.length - 2];
    // Punto di interesse indietro, sulla gamba 1 — già superato.
    final point = hairpinTrack[2];

    final pilotProj = chainage.project(pilot, searchStartIdx: hairpinTrack.length - 3);
    final pointProj = chainage.project(point);
    expect(pilotProj, isNotNull);
    expect(pointProj, isNotNull);

    final signedDistanceM = pointProj!.progressiveM - pilotProj!.progressiveM;
    expect(signedDistanceM, lessThan(0));

    // La regola applicativa ("annuncia solo i punti davanti") si traduce
    // in questo controllo lato chiamante (GpsService._chainageDistanceTo
    // + i call site in _onPosition: `if (d != null && d > 0)`).
    final wouldAnnounce = signedDistanceM > 0;
    expect(wouldAnnounce, isFalse);
  });

  test('un punto ancora davanti al pilota risulta a distanza POSITIVA', () {
    final pilot = hairpinTrack.first;
    final point = hairpinTrack[5]; // più avanti sulla gamba 1

    final pilotProj = chainage.project(pilot);
    final pointProj = chainage.project(point);
    final signedDistanceM = pointProj!.progressiveM - pilotProj!.progressiveM;

    expect(signedDistanceM, greaterThan(0));
  });

  test('la ricerca con finestra locale non si aggancia al segmento sbagliato '
      'dove il percorso passa vicino a sé stesso', () {
    // Un punto sulla gamba 2, proiettato con una finestra di ricerca
    // centrata sull'indice della gamba 2 (non della gamba 1, anche se
    // geograficamente più vicina in alcuni tratti) deve restare sulla
    // gamba 2 — verificato controllando che l'indice di segmento
    // risultante sia effettivamente quello della gamba 2, non della gamba 1.
    final leg2StartIdx = 15; // indice approssimativo di inizio gamba 2
    final point = hairpinTrack[18]; // sulla gamba 2

    final proj = chainage.project(point, searchStartIdx: leg2StartIdx, searchWindow: 5);
    expect(proj, isNotNull);
    expect(proj!.segmentIndex, greaterThanOrEqualTo(leg2StartIdx - 5));
  });

  test('traccia con meno di 2 punti: nessuna proiezione possibile', () {
    final degenerate = TrackChainage.build([hairpinTrack.first]);
    expect(degenerate.project(hairpinTrack.first), isNull);
  });

  test('perpendicularDistanceM riflette lo scostamento dalla traccia', () {
    // Punto esattamente su un vertice della traccia: distanza perpendicolare ~0.
    final onTrack = chainage.project(hairpinTrack[3]);
    expect(onTrack!.perpendicularDistanceM, lessThan(1.0));

    // Punto spostato di ~330m dalla traccia: distanza perpendicolare
    // consistente (usata da GpsService per sospendere gli avvisi oltre
    // 150m) — margine ampio rispetto alla soglia per non dipendere da
    // arrotondamenti/geometria dell'estremo della traccia.
    final offTrackPoint = LatLng(45.0 + 0.003, 7.0005); // ~330m a nord
    final off = chainage.project(offTrackPoint);
    expect(off!.perpendicularDistanceM, greaterThan(150.0));
  });
}
