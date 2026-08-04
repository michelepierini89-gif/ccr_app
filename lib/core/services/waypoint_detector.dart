import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../models/waypoint_model.dart';
import '../utils/location_utils.dart';

/// Risultato di un passaggio waypoint confermato da [WaypointDetector].
class WaypointPassageResult {
  final WaypointModel waypoint;
  final DateTime timestamp;
  const WaypointPassageResult(
      {required this.waypoint, required this.timestamp});
}

class WaypointDetector {
  /// Semi-larghezza della porta virtuale (vedi [buildGate]): il segmento
  /// perpendicolare alla traccia si estende per questa distanza su
  /// entrambi i lati del waypoint.
  static const double kGateHalfWidthMeters = 25.0;

  /// Costruisce la porta virtuale per [wp] cercando il punto più vicino su
  /// [referenceTrack] (la polyline GPX di riferimento) e usando i punti
  /// immediatamente precedente/successivo per stimare il bearing locale
  /// della traccia in quel punto. Ritorna null se la traccia ha meno di 2
  /// punti o se il punto più vicino è un estremo senza vicino su un lato.
  static WaypointGate? buildGate(
    WaypointModel wp,
    List<LatLng> referenceTrack, {
    double halfWidthMeters = kGateHalfWidthMeters,
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

    final prevIdx = nearestIdx > 0 ? nearestIdx - 1 : 0;
    final nextIdx = nearestIdx < referenceTrack.length - 1
        ? nearestIdx + 1
        : referenceTrack.length - 1;
    if (prevIdx == nextIdx) return null;

    final prevPt = referenceTrack[prevIdx];
    final nextPt = referenceTrack[nextIdx];
    final bearing = LocationUtils.bearingDegrees(
      prevPt.latitude,
      prevPt.longitude,
      nextPt.latitude,
      nextPt.longitude,
    );
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
  /// riferimento. Va richiamata una sola volta al caricamento
  /// dell'evento/avvio registrazione: il risultato non viene mai
  /// persistito, solo tenuto in memoria per la sessione corrente.
  static List<WaypointModel> attachGates(
    List<WaypointModel> waypoints,
    List<LatLng> referenceTrack, {
    bool Function(WaypointModel)? shouldGate,
  }) {
    return waypoints.map((w) {
      if (shouldGate != null && !shouldGate(w)) return w;
      final gate = buildGate(w, referenceTrack);
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
      return WaypointPassageResult(
        waypoint: wp,
        timestamp: DateTime.fromMillisecondsSinceEpoch(crossMs),
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
