import 'package:latlong2/latlong.dart';
import 'location_utils.dart';

/// Esito della proiezione di un punto sulla polilinea (Step 47).
class ChainageProjection {
  /// Progressiva chilometrica (metri dall'inizio della traccia) del punto
  /// proiettato sul segmento più vicino.
  final double progressiveM;

  /// Distanza perpendicolare (metri) dal punto originale alla traccia —
  /// oltre una soglia (150m, vedi GpsService) il punto è considerato
  /// "fuori traccia": la progressiva non è più affidabile.
  final double perpendicularDistanceM;

  /// Indice del segmento (track[i] -> track[i+1]) su cui è caduta la
  /// proiezione migliore — usato come centro della finestra di ricerca
  /// per la proiezione successiva.
  final int segmentIndex;

  const ChainageProjection({
    required this.progressiveM,
    required this.perpendicularDistanceM,
    required this.segmentIndex,
  });
}

/// Progressiva chilometrica lungo una polilinea di riferimento (Step 47) —
/// sostituisce la distanza in linea d'aria per gli avvisi vocali/banner
/// (pericoli, inizio/fine PS, zone velocità, punto ristoro): su un
/// percorso di montagna un punto vicino in linea d'aria può essere
/// lontanissimo da percorrere (tornante) o viceversa (oltre una valle).
///
/// Costruita UNA VOLTA al caricamento del tracciato evento
/// ([GpsService._referenceTrack]); ogni punto annunciabile (waypoint
/// inizio/fine PS, zona velocità, punto ristoro, punto pericolo) vi si
/// proietta UNA VOLTA per ottenere la propria progressiva fissa; il
/// pilota vi si proietta AD OGNI FIX ACCETTATO (finestra di ricerca
/// attorno all'ultimo indice noto, per non agganciarsi al segmento
/// sbagliato dove il percorso passa vicino a sé stesso — es. un
/// tornante stretto). La distanza da percorrere è poi la differenza fra
/// le due progressive.
class TrackChainage {
  final List<LatLng> track;
  final List<double> _cumulativeM;

  TrackChainage._(this.track, this._cumulativeM);

  /// `track.length < 2` produce una chainage degenere (nessuna
  /// proiezione possibile, [project] ritorna sempre null) — capita per
  /// eventi senza tracciato caricato, non un errore da propagare.
  factory TrackChainage.build(List<LatLng> track) {
    final cum = <double>[0.0];
    for (var i = 1; i < track.length; i++) {
      cum.add(cum[i - 1] +
          LocationUtils.haversineDistance(track[i - 1].latitude,
              track[i - 1].longitude, track[i].latitude, track[i].longitude));
    }
    return TrackChainage._(track, cum);
  }

  double get totalLengthM => _cumulativeM.isEmpty ? 0.0 : _cumulativeM.last;

  /// Proietta [point] sulla traccia. Con [searchStartIdx] nullo (prima
  /// proiezione di un punto fisso, o del pilota a inizio sessione) cerca
  /// su TUTTA la traccia; altrimenti limita la ricerca a
  /// `[searchStartIdx-searchWindow, searchStartIdx+searchWindow]` — se la
  /// finestra locale non trova nulla entro [maxLocalDistanceM] (percorso
  /// perso/salto GPS), ripete la ricerca su tutta la traccia invece di
  /// restare agganciata a un segmento ormai lontano.
  ChainageProjection? project(
    LatLng point, {
    int? searchStartIdx,
    int searchWindow = 80,
    double maxLocalDistanceM = 150.0,
  }) {
    if (track.length < 2) return null;

    // Finestra locale attorno all'ultimo segmento noto: O(searchWindow)
    // invece di scandire l'intera traccia ad ogni fix (4Hz live, tracce
    // anche di migliaia di punti). Solo se assente/fuori soglia si ricade
    // sulla ricerca completa (prima proiezione della sessione, o percorso
    // perso/salto GPS — meglio la proiezione più vicina in assoluto che
    // una finestra locale ormai priva di senso).
    if (searchStartIdx != null) {
      final lo = (searchStartIdx - searchWindow).clamp(0, track.length - 2);
      final hi = (searchStartIdx + searchWindow).clamp(0, track.length - 2);
      final local = _projectInRange(point, lo, hi);
      if (local != null && local.perpendicularDistanceM <= maxLocalDistanceM) {
        return local;
      }
    }
    return _projectInRange(point, 0, track.length - 2);
  }

  ChainageProjection? _projectInRange(LatLng point, int lo, int hi) {
    double bestDist = double.infinity;
    int bestSegIdx = lo;
    double bestT = 0.0;
    for (var i = lo; i <= hi; i++) {
      final a = track[i];
      final b = track[i + 1];
      final (distM, t) = LocationUtils.projectOntoSegment(
        point.latitude,
        point.longitude,
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (distM < bestDist) {
        bestDist = distM;
        bestSegIdx = i;
        bestT = t;
      }
    }
    final segLenM = _cumulativeM[bestSegIdx + 1] - _cumulativeM[bestSegIdx];
    final progressiveM = _cumulativeM[bestSegIdx] + segLenM * bestT;
    return ChainageProjection(
      progressiveM: progressiveM,
      perpendicularDistanceM: bestDist,
      segmentIndex: bestSegIdx,
    );
  }
}
