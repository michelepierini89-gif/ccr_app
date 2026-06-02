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
      polylines.add(Polyline(
        points: [s.waypointInizio.latLng, s.waypointFine.latLng],
        color: s.color,
        strokeWidth: 4,
      ));
    }
    return PolylineLayer(polylines: polylines);
  }
}
