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
    Set<String> alreadyPassed,
  ) {
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
      final radius = wp.type == WaypointType.intermedio
          ? AppConstants.waypointCheckpointRadiusMeters
          : AppConstants.waypointRadiusMeters;
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
