import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../models/waypoint_model.dart';
import '../utils/location_utils.dart';

class WaypointDetector {
  WaypointDetector._();

  static WaypointModel? detectPassage(
    LatLng position,
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
      if (dist <= radius) return wp;
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
