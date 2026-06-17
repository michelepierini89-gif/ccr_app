import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/special_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';

class TrackLayer extends StatelessWidget {
  final List<LatLng> trackPoints;
  final List<SpecialModel> specials;

  const TrackLayer(
      {super.key, required this.trackPoints, required this.specials});

  int? _indexFromId(String id) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(id);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  int _nearestIdx(LatLng point) {
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < trackPoints.length; i++) {
      final dlat = point.latitude - trackPoints[i].latitude;
      final dlng = point.longitude - trackPoints[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  int _resolveWpIdx(String id, LatLng latLng) {
    final parsed = _indexFromId(id);
    if (parsed != null) return parsed.clamp(0, trackPoints.length - 1);
    return _nearestIdx(latLng);
  }

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    // Specials first (underneath), wider stroke
    for (final s in specials) {
      final color = s.annullata ? AppColors.textSecondary : s.color;
      final pattern = s.annullata
          ? StrokePattern.dashed(segments: const [10, 8])
          : const StrokePattern.solid();
      if (trackPoints.isEmpty) {
        polylines.add(Polyline(
          points: [s.waypointInizio.latLng, s.waypointFine.latLng],
          color: color,
          strokeWidth: 5,
          pattern: pattern,
        ));
      } else {
        final startIdx =
            _resolveWpIdx(s.waypointInizio.id, s.waypointInizio.latLng);
        final endIdx =
            _resolveWpIdx(s.waypointFine.id, s.waypointFine.latLng);
        final a = startIdx < endIdx ? startIdx : endIdx;
        final b = startIdx < endIdx ? endIdx : startIdx;
        if (a < b && b < trackPoints.length) {
          polylines.add(Polyline(
            points: trackPoints.sublist(a, b + 1),
            color: color,
            strokeWidth: 5,
            pattern: pattern,
          ));
        }
      }
    }
    // Base track last (on top), thinner — always visible over specials
    if (trackPoints.isNotEmpty) {
      polylines.add(Polyline(
        points: trackPoints,
        color: AppColors.accent,
        strokeWidth: 2,
      ));
    }
    return Stack(children: [
      PolylineLayer(polylines: polylines),
      TrackDirectionArrowsLayer(trackPoints: trackPoints),
    ]);
  }
}

/// Frecce direzionali campionate lungo [trackPoints] ogni
/// [kArrowSpacingMeters] metri, per indicare il verso di percorrenza della
/// traccia di riferimento (rossa/accent). Non interattive: nessun gesto o
/// tooltip — solo indicazione visiva.
class TrackDirectionArrowsLayer extends StatelessWidget {
  final List<LatLng> trackPoints;
  static const double kArrowSpacingMeters = 150.0;

  const TrackDirectionArrowsLayer({super.key, required this.trackPoints});

  static double _bearingDeg(LatLng a, LatLng b) {
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final brng = atan2(y, x) * 180 / pi;
    return (brng + 360) % 360;
  }

  List<Marker> _buildMarkers() {
    if (trackPoints.length < 2) return const [];
    final markers = <Marker>[];
    var accumulated = 0.0;
    for (var i = 1; i < trackPoints.length; i++) {
      accumulated += LocationUtils.haversineDistance(
        trackPoints[i - 1].latitude,
        trackPoints[i - 1].longitude,
        trackPoints[i].latitude,
        trackPoints[i].longitude,
      );
      if (accumulated >= kArrowSpacingMeters) {
        final bearing = _bearingDeg(trackPoints[i - 1], trackPoints[i]);
        markers.add(Marker(
          point: trackPoints[i],
          width: 16,
          height: 16,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: bearing * pi / 180,
              child: const Icon(
                Icons.navigation,
                size: 14,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
              ),
            ),
          ),
        ));
        accumulated = 0.0;
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(markers: _buildMarkers());
  }
}
