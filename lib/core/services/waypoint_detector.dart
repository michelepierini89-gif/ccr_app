import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../models/waypoint_model.dart';
import '../utils/location_utils.dart';
import 'track_smoother.dart';

/// Ordine di precisione dal migliore al peggiore: porta interpolata > porta
/// su gap > raggio > recovery > forfait. Pubblico per essere condiviso tra
/// il ricalcolo "Tempi ufficiali" (`timing_screen.dart`, Blocco B), il banco
/// di replay (Parte 1, `track_replay_service.dart`) e la regola di
/// precedenza (Fix 1, `GpsService._registerPassage`) che impedisce a un
/// fallback di sovrascrivere un passaggio già noto più preciso.
const timingMethodRank = {
  'gate': 0,
  'gate_gap': 1,
  'radius': 2,
  'recovery': 3,
  'forfait': 4,
};

String worstTimingMethod(String a, String b) {
  final ra = timingMethodRank[a] ?? 1;
  final rb = timingMethodRank[b] ?? 1;
  return ra >= rb ? a : b;
}

/// Risultato del ricalcolo porta/raggio per una singola speciale su una
/// traccia già "pulita" (senza filtro accuracy/jump/Kalman — pensata per
/// tracce smussate con [TrackSmoother]), vedi
/// [WaypointDetector.rerunGateRadiusDetection].
class GateRadiusRerunResult {
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final String startMethod;
  final String endMethod;
  final double? startFractionT;
  final double? startDistanceMeters;
  final double? endFractionT;
  final double? endDistanceMeters;

  const GateRadiusRerunResult({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.startMethod,
    required this.endMethod,
    this.startFractionT,
    this.startDistanceMeters,
    this.endFractionT,
    this.endDistanceMeters,
  });

  int get durationMs =>
      endTimestamp.difference(startTimestamp).inMilliseconds;
  String get method => worstTimingMethod(startMethod, endMethod);
}

/// Risultato di un passaggio waypoint confermato da [WaypointDetector].
class WaypointPassageResult {
  final WaypointModel waypoint;
  final DateTime timestamp;
  // Solo per passaggi rilevati via porta virtuale (Parte 4 — log
  // diagnostico): frazione lungo il segmento prev->curr a cui avviene
  // l'attraversamento (0..1) e distanza tra il punto interpolato e il
  // waypoint. Null per i passaggi rilevati a raggio.
  final double? fractionT;
  final double? distanceMeters;
  const WaypointPassageResult({
    required this.waypoint,
    required this.timestamp,
    this.fractionT,
    this.distanceMeters,
  });
}

class WaypointDetector {
  /// Semi-larghezza di default della porta virtuale (vedi [buildGate]): il
  /// segmento perpendicolare alla traccia si estende per questa distanza su
  /// entrambi i lati del waypoint. Sovrascrivibile per singolo waypoint via
  /// [WaypointModel.gateHalfWidthMeters] (Fix 3).
  static const double kGateHalfWidthMeters = 30.0;

  /// Fix 3 — Ampiezza (metri, per lato) della finestra sulla traccia di
  /// riferimento usata per stimare il bearing locale della porta: un solo
  /// punto prima/dopo (comportamento precedente) produce una stima
  /// instabile su curve strette, dove l'arco percorso dal pilota non è
  /// rappresentato dal singolo segmento GPX adiacente.
  static const double kGateBearingWindowMeters = 30.0;

  /// Fix 3 — oltre questa variazione di bearing (gradi) tra i segmenti
  /// della finestra, la curva è troppo stretta perché un singolo bearing
  /// medio sia pienamente rappresentativo: [onUnreliableBearing] viene
  /// invocato per diagnostica/verifica admin, ma la porta viene comunque
  /// costruita con la media vettoriale — verificato empiricamente (replay
  /// sul test in moto) che rifiutarla in questi punti perde attraversamenti
  /// che la porta agganciava correttamente, senza risolvere i casi in cui
  /// il vero problema non è l'orientamento (validato su PS4 INIZIO: la
  /// media vettoriale su finestra larga dà lo stesso bearing, entro 1°, del
  /// singolo segmento adiacente — la curvatura da sola non è un buon
  /// predittore di quando la porta va scartata).
  static const double kGateMaxBearingVariationDeg = 60.0;

  /// Costruisce la porta virtuale per [wp] cercando il punto più vicino su
  /// [referenceTrack] (la polyline GPX di riferimento) e stimando il
  /// bearing locale della traccia come media vettoriale dei bearing dei
  /// segmenti in una finestra di ±[kGateBearingWindowMeters] metri attorno
  /// ad esso (Fix 3 — prima usava solo il punto immediatamente
  /// precedente/successivo, instabile sui tornanti). Ritorna null solo se
  /// la traccia ha meno di 2 punti o la finestra è degenere;
  /// [onUnreliableBearing] segnala (senza bloccare) i punti a curvatura
  /// elevata, dove il fallback a raggio resta comunque disponibile se la
  /// porta non intercetta la traiettoria reale.
  static WaypointGate? buildGate(
    WaypointModel wp,
    List<LatLng> referenceTrack, {
    double halfWidthMeters = kGateHalfWidthMeters,
    void Function(WaypointModel wp, double bearingVariationDeg)?
        onUnreliableBearing,
  }) {
    if (referenceTrack.length < 2) return null;

    var nearestIdx = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < referenceTrack.length; i++) {
      final d = LocationUtils.haversineDistance(
        wp.lat,
        wp.lng,
        referenceTrack[i].latitude,
        referenceTrack[i].longitude,
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }

    var prevIdx = nearestIdx;
    var accPrev = 0.0;
    while (prevIdx > 0 && accPrev < kGateBearingWindowMeters) {
      accPrev += LocationUtils.haversineDistance(
        referenceTrack[prevIdx].latitude,
        referenceTrack[prevIdx].longitude,
        referenceTrack[prevIdx - 1].latitude,
        referenceTrack[prevIdx - 1].longitude,
      );
      prevIdx--;
    }
    var nextIdx = nearestIdx;
    var accNext = 0.0;
    while (nextIdx < referenceTrack.length - 1 &&
        accNext < kGateBearingWindowMeters) {
      accNext += LocationUtils.haversineDistance(
        referenceTrack[nextIdx].latitude,
        referenceTrack[nextIdx].longitude,
        referenceTrack[nextIdx + 1].latitude,
        referenceTrack[nextIdx + 1].longitude,
      );
      nextIdx++;
    }
    if (prevIdx == nextIdx) return null;

    // Bearing medio vettoriale (somma dei versori, non media numerica dei
    // gradi: evita l'errore di wraparound attorno a 0°/360°) dei segmenti
    // nella finestra [prevIdx, nextIdx], e variazione massima di un
    // segmento rispetto alla media come proxy di curvatura.
    var sumX = 0.0, sumY = 0.0;
    final segmentBearings = <double>[];
    for (var i = prevIdx; i < nextIdx; i++) {
      final b = LocationUtils.bearingDegrees(
        referenceTrack[i].latitude,
        referenceTrack[i].longitude,
        referenceTrack[i + 1].latitude,
        referenceTrack[i + 1].longitude,
      );
      segmentBearings.add(b);
      final rad = b * pi / 180;
      sumX += sin(rad);
      sumY += cos(rad);
    }
    if (segmentBearings.isEmpty) return null;
    final bearing = (atan2(sumX, sumY) * 180 / pi + 360) % 360;

    var maxVariation = 0.0;
    for (final b in segmentBearings) {
      final diff = ((b - bearing + 540) % 360 - 180).abs();
      if (diff > maxVariation) maxVariation = diff;
    }
    if (maxVariation > kGateMaxBearingVariationDeg) {
      onUnreliableBearing?.call(wp, maxVariation);
    }

    final perpBearing = (bearing + 90) % 360;

    final a = LocationUtils.destinationPoint(
        wp.lat, wp.lng, perpBearing, halfWidthMeters);
    final b = LocationUtils.destinationPoint(
        wp.lat, wp.lng, (perpBearing + 180) % 360, halfWidthMeters);

    return WaypointGate(
      gateA: LatLng(a[0], a[1]),
      gateB: LatLng(b[0], b[1]),
      bearingDeg: bearing,
    );
  }

  /// Attacca una porta virtuale (vedi [buildGate]) a ciascun waypoint di
  /// [waypoints] per cui [shouldGate] ritorna true (o a tutti se
  /// [shouldGate] è null), usando [referenceTrack] come polyline di
  /// riferimento. [halfWidthMetersFor] permette la semi-larghezza
  /// personalizzata per waypoint (Fix 3, default
  /// [WaypointModel.gateHalfWidthMeters] se non fornito). Va richiamata una
  /// sola volta al caricamento dell'evento/avvio registrazione: il
  /// risultato non viene mai persistito, solo tenuto in memoria per la
  /// sessione corrente.
  static List<WaypointModel> attachGates(
    List<WaypointModel> waypoints,
    List<LatLng> referenceTrack, {
    bool Function(WaypointModel)? shouldGate,
    double Function(WaypointModel)? halfWidthMetersFor,
    void Function(WaypointModel wp, double bearingVariationDeg)?
        onUnreliableBearing,
  }) {
    return waypoints.map((w) {
      if (shouldGate != null && !shouldGate(w)) return w;
      final halfWidth =
          halfWidthMetersFor?.call(w) ?? w.gateHalfWidthMeters ?? kGateHalfWidthMeters;
      final gate = buildGate(
        w,
        referenceTrack,
        halfWidthMeters: halfWidth,
        onUnreliableBearing: onUnreliableBearing,
      );
      return gate == null ? w : w.copyWithGate(gate);
    }).toList();
  }

  /// Verifica se il segmento di traiettoria (prev->curr) attraversa la
  /// porta virtuale di uno dei [waypoints] non ancora passati, nel verso
  /// atteso. Ritorna il primo attraversamento trovato con timestamp
  /// interpolato linearmente sul segmento, o null se nessuna porta è
  /// stata attraversata in questo fix.
  ///
  /// Precedenza (vedi GpsService._onPosition): questo metodo va provato
  /// PRIMA del metodo a raggio ([detectPassage]); se non trova nulla, il
  /// chiamante deve ricadere sul raggio (fallback A4 del blocco timing).
  WaypointPassageResult? detectGateCrossing(
    LatLng prev,
    LatLng curr,
    DateTime prevTs,
    DateTime currTs,
    List<WaypointModel> waypoints,
    Set<String> alreadyPassed,
  ) {
    for (final wp in waypoints) {
      if (alreadyPassed.contains(wp.id)) continue;
      final gate = wp.gate;
      if (gate == null) continue;
      final t = _segmentIntersectionFraction(
          prev, curr, gate.gateA, gate.gateB, gate.bearingDeg);
      if (t == null) continue;
      final dtMs = currTs.difference(prevTs).inMilliseconds;
      final crossMs =
          prevTs.millisecondsSinceEpoch + (t * dtMs).round();
      final crossLat = prev.latitude + (curr.latitude - prev.latitude) * t;
      final crossLng = prev.longitude + (curr.longitude - prev.longitude) * t;
      final distanceMeters =
          LocationUtils.haversineDistance(crossLat, crossLng, wp.lat, wp.lng);
      return WaypointPassageResult(
        waypoint: wp,
        timestamp: DateTime.fromMillisecondsSinceEpoch(crossMs),
        fractionT: t,
        distanceMeters: distanceMeters,
      );
    }
    return null;
  }

  /// Intersezione tra il segmento traiettoria (p1->p2) e il segmento
  /// porta (p3->p4), in coordinate locali equirettangolari (metri)
  /// centrate sul punto medio della porta. Ritorna la frazione `t` lungo
  /// (p1->p2) a cui avviene l'intersezione (0..1), o null se i segmenti
  /// non si intersecano o l'attraversamento è nel verso opposto a quello
  /// atteso (prodotto scalare del moto con la direzione attesa <= 0).
  static double? _segmentIntersectionFraction(
    LatLng p1,
    LatLng p2,
    LatLng p3,
    LatLng p4,
    double expectedBearingDeg,
  ) {
    final originLat = (p3.latitude + p4.latitude) / 2;
    final originLng = (p3.longitude + p4.longitude) / 2;

    final a = LocationUtils.toLocalMeters(
        originLat, originLng, p1.latitude, p1.longitude);
    final b = LocationUtils.toLocalMeters(
        originLat, originLng, p2.latitude, p2.longitude);
    final c = LocationUtils.toLocalMeters(
        originLat, originLng, p3.latitude, p3.longitude);
    final d = LocationUtils.toLocalMeters(
        originLat, originLng, p4.latitude, p4.longitude);

    final x1 = a[0], y1 = a[1];
    final x2 = b[0], y2 = b[1];
    final x3 = c[0], y3 = c[1];
    final x4 = d[0], y4 = d[1];

    final denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
    if (denom.abs() < 1e-9) return null; // paralleli

    final ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denom;
    final ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / denom;
    if (ua < 0 || ua > 1 || ub < 0 || ub > 1) return null;

    // Verso di attraversamento: il moto deve avere componente positiva
    // lungo la direzione attesa (prodotto scalare > 0), altrimenti un
    // pilota che torna indietro non deve riattivare la porta.
    final bearingRad = expectedBearingDeg * pi / 180;
    final expDirX = sin(bearingRad); // componente est
    final expDirY = cos(bearingRad); // componente nord
    final dot = (x2 - x1) * expDirX + (y2 - y1) * expDirY;
    if (dot <= 0) return null;

    return ua;
  }

  /// Per ogni waypoint, conta le rilevazioni consecutive entro il raggio e
  /// memorizza il timestamp della prima. Un waypoint è confermato solo dopo
  /// [kRequiredConsecutiveDetections] rilevazioni consecutive valide: un
  /// singolo ghost point non può più triggerare una PS con timestamp errato.
  final Map<String, int> _consecutiveNearCount = {};
  final Map<String, DateTime> _firstNearTs = {};
  static const int kRequiredConsecutiveDetections = 2;

  /// Resetta lo stato di doppia conferma (richiamare a inizio/fine registrazione).
  void reset() {
    _consecutiveNearCount.clear();
    _firstNearTs.clear();
  }

  /// Restituisce il waypoint confermato come passato — con il timestamp
  /// della PRIMA delle rilevazioni consecutive — oppure null se nessun
  /// waypoint ha raggiunto il numero di conferme richiesto in questa chiamata.
  WaypointPassageResult? detectPassage(
    LatLng position,
    DateTime ts,
    List<WaypointModel> waypoints,
    Set<String> alreadyPassed, {
    Map<String, double>? radiusOverrides,
  }) {
    for (final wp in waypoints) {
      if (alreadyPassed.contains(wp.id)) continue;
      final dist = LocationUtils.haversineDistance(
        position.latitude,
        position.longitude,
        wp.lat,
        wp.lng,
      );
      // Checkpoints (intermedio) use a wider radius because they are
      // boolean-only and have no impact on special timing accuracy.
      // radiusOverrides (es. inizio/fine zona velocità) prevale su entrambi.
      final radius = radiusOverrides?[wp.id] ??
          (wp.type == WaypointType.intermedio
              ? AppConstants.waypointCheckpointRadiusMeters
              : AppConstants.waypointRadiusMeters);
      if (dist <= radius) {
        final previousCount = _consecutiveNearCount[wp.id] ?? 0;
        if (previousCount == 0) {
          _firstNearTs[wp.id] = ts;
        }
        final count = previousCount + 1;
        if (count >= kRequiredConsecutiveDetections) {
          _consecutiveNearCount[wp.id] = 0;
          return WaypointPassageResult(
              waypoint: wp, timestamp: _firstNearTs[wp.id]!);
        }
        _consecutiveNearCount[wp.id] = count;
      } else {
        _consecutiveNearCount[wp.id] = 0;
      }
    }
    return null;
  }

  static double? nearestWaypointDistance(
      LatLng position, List<WaypointModel> waypoints) {
    if (waypoints.isEmpty) return null;
    double? nearest;
    for (final wp in waypoints) {
      final dist = LocationUtils.haversineDistance(
        position.latitude,
        position.longitude,
        wp.lat,
        wp.lng,
      );
      if (nearest == null || dist < nearest) nearest = dist;
    }
    return nearest;
  }

  /// Waypoint più vicino a [position] tra [waypoints], o null se la lista è
  /// vuota. Usato per mostrare un'etichetta specifica ("Inizio PS1", ecc.)
  /// invece del generico "WAYPOINT VICINO".
  static WaypointModel? nearestWaypoint(
      LatLng position, List<WaypointModel> waypoints) {
    if (waypoints.isEmpty) return null;
    WaypointModel? nearest;
    double? nearestDist;
    for (final wp in waypoints) {
      final dist = LocationUtils.haversineDistance(
        position.latitude,
        position.longitude,
        wp.lat,
        wp.lng,
      );
      if (nearestDist == null || dist < nearestDist) {
        nearestDist = dist;
        nearest = wp;
      }
    }
    return nearest;
  }

  /// Riesegue SOLO il rilevamento porta virtuale/raggio (senza Kalman né
  /// filtri accuracy/jump — pensato per tracce già pulite, tipicamente
  /// smussate con [TrackSmoother]) su [track], per l'inizio/fine di ogni
  /// voce di [gatedBySpecial]. Estratto da `timing_screen.dart` (Blocco B,
  /// "Tempi ufficiali") per essere condiviso anche dal banco di replay
  /// (Parte 1C, confronto "porte virtuali su traccia RTS").
  static Map<String, GateRadiusRerunResult> rerunGateRadiusDetection(
    List<SmoothedTrackPoint> track,
    Map<String, (WaypointModel, WaypointModel)> gatedBySpecial,
  ) {
    final result = <String, GateRadiusRerunResult>{};
    if (track.length < 2) return result;

    for (final entry in gatedBySpecial.entries) {
      final (inizio, fine) = entry.value;
      final waypoints = [inizio, fine];
      final detector = WaypointDetector();
      final passed = <String>{};
      WaypointPassageResult? startHit, endHit;
      var startMethod = 'radius';
      var endMethod = 'radius';

      for (var i = 1;
          i < track.length && (startHit == null || endHit == null);
          i++) {
        final prev = track[i - 1];
        final curr = track[i];
        var method = 'gate';
        var hit = detector.detectGateCrossing(prev.position, curr.position,
            prev.timestamp, curr.timestamp, waypoints, passed);
        if (hit == null) {
          method = 'radius';
          hit = detector.detectPassage(
              curr.position, curr.timestamp, waypoints, passed);
        }
        if (hit == null) continue;
        passed.add(hit.waypoint.id);
        if (hit.waypoint.id == inizio.id) {
          startHit = hit;
          startMethod = method;
        } else if (hit.waypoint.id == fine.id) {
          endHit = hit;
          endMethod = method;
        }
      }

      if (startHit != null &&
          endHit != null &&
          endHit.timestamp.isAfter(startHit.timestamp)) {
        result[entry.key] = GateRadiusRerunResult(
          startTimestamp: startHit.timestamp,
          endTimestamp: endHit.timestamp,
          startMethod: startMethod,
          endMethod: endMethod,
          startFractionT: startHit.fractionT,
          startDistanceMeters: startHit.distanceMeters,
          endFractionT: endHit.fractionT,
          endDistanceMeters: endHit.distanceMeters,
        );
      }
    }
    return result;
  }

  static int adaptiveInterval(double? nearestDistance, bool inSpecial) {
    if (nearestDistance != null &&
        nearestDistance <= AppConstants.nearWaypointThresholdMeters) {
      return AppConstants.gpsIntervalNearWaypointMs;
    }
    if (inSpecial) return AppConstants.gpsIntervalInSpecialMs;
    return AppConstants.gpsIntervalTransferMs;
  }

  /// Distance in meters from [position] to a danger point.
  static double dangerPointDistance(LatLng position, DangerPointModel dp) {
    return LocationUtils.haversineDistance(
      position.latitude,
      position.longitude,
      dp.latitude,
      dp.longitude,
    );
  }
}
