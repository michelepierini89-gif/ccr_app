import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/special_model.dart';
import '../../../core/theme/app_colors.dart';

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
    if (trackPoints.isNotEmpty) {
      polylines.add(Polyline(
        points: trackPoints,
        color: AppColors.accent,
        strokeWidth: 3,
      ));
    }
    for (final s in specials) {
      if (trackPoints.isEmpty) {
        polylines.add(Polyline(
          points: [s.waypointInizio.latLng, s.waypointFine.latLng],
          color: s.color,
          strokeWidth: 4,
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
            color: s.color,
            strokeWidth: 4,
          ));
        }
      }
    }
    return PolylineLayer(polylines: polylines);
  }
}
