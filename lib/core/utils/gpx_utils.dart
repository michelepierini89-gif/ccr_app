import 'package:latlong2/latlong.dart';
import '../models/special_model.dart';
import '../models/waypoint_model.dart';
import 'location_utils.dart';

class GpxUtils {
  GpxUtils._();

  /// Trova il punto della polyline [trackPoints] più vicino a [tapped],
  /// proiettando perpendicolarmente su ciascun segmento (o il punto più
  /// vicino se la proiezione cade fuori dal segmento).
  static LatLng snapToTrack(LatLng tapped, List<LatLng> trackPoints) {
    if (trackPoints.isEmpty) return tapped;
    if (trackPoints.length == 1) return trackPoints.first;

    var best = trackPoints.first;
    var bestDist = double.infinity;

    for (var i = 0; i < trackPoints.length - 1; i++) {
      final proj =
          _closestPointOnSegment(tapped, trackPoints[i], trackPoints[i + 1]);
      final dist = LocationUtils.haversineDistance(tapped.latitude,
          tapped.longitude, proj.latitude, proj.longitude);
      if (dist < bestDist) {
        bestDist = dist;
        best = proj;
      }
    }
    return best;
  }

  /// Distanza in metri tra [point] e il punto più vicino sulla traccia.
  static double distanceToTrack(LatLng point, LatLng snapped) =>
      LocationUtils.haversineDistance(
          point.latitude, point.longitude, snapped.latitude, snapped.longitude);

  static LatLng _closestPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a;

    var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);

    return LatLng(ay + t * dy, ax + t * dx);
  }

  /// Indice del punto della traccia più vicino a [point].
  static int nearestTrackIndex(LatLng point, List<LatLng> trackPoints) {
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < trackPoints.length; i++) {
      final d = LocationUtils.haversineDistance(point.latitude,
          point.longitude, trackPoints[i].latitude, trackPoints[i].longitude);
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  /// Conta quanti [dangerPoints] cadono lungo la traccia tra l'inizio e la
  /// fine della [special], confrontando gli indici del punto più vicino
  /// sulla traccia di riferimento (proxy della distanza cumulativa).
  static int countDangerPointsInSpecial(
    SpecialModel special,
    List<DangerPointModel> dangerPoints,
    List<LatLng> trackPoints,
  ) {
    if (trackPoints.isEmpty || dangerPoints.isEmpty) return 0;

    final startIdx = nearestTrackIndex(special.waypointInizio.latLng, trackPoints);
    final endIdx = nearestTrackIndex(special.waypointFine.latLng, trackPoints);
    final a = startIdx < endIdx ? startIdx : endIdx;
    final b = startIdx < endIdx ? endIdx : startIdx;

    var count = 0;
    for (final dp in dangerPoints) {
      final idx = nearestTrackIndex(dp.latLng, trackPoints);
      if (idx >= a && idx <= b) count++;
    }
    return count;
  }
}
