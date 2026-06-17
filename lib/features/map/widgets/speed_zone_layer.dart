import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/utils/gpx_utils.dart';

/// Disegna le zone a velocità controllata sulla traccia di riferimento:
/// il segmento tra inizio e fine zona in arancione, con un'icona a inizio
/// zona. Usato sia nell'editor admin (specials_editor_screen.dart) sia
/// nella mappa di navigazione del pilota (gps_recording_screen.dart), in
/// modo che lo stile sia identico nei due contesti.
class SpeedZoneLayer extends StatelessWidget {
  final List<SpeedZoneModel> zones;
  final List<LatLng> trackPoints;

  const SpeedZoneLayer({
    super.key,
    required this.zones,
    required this.trackPoints,
  });

  List<Polyline> _buildSegments() {
    if (trackPoints.isEmpty) return const [];
    final polylines = <Polyline>[];
    for (final z in zones) {
      final a = GpxUtils.nearestTrackIndex(z.startLatLng, trackPoints);
      final b = GpxUtils.nearestTrackIndex(z.endLatLng, trackPoints);
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      if (lo < hi && hi < trackPoints.length) {
        polylines.add(Polyline(
          points: trackPoints.sublist(lo, hi + 1),
          color: Colors.orange,
          strokeWidth: 6,
        ));
      }
    }
    return polylines;
  }

  List<Marker> _buildMarkers() {
    return zones
        .map((z) => Marker(
              point: trackPoints.isNotEmpty
                  ? trackPoints[GpxUtils.nearestTrackIndex(
                      z.startLatLng, trackPoints)]
                  : z.startLatLng,
              width: 26,
              height: 26,
              child: const IgnorePointer(
                child: Icon(
                  Icons.speed,
                  color: Colors.orange,
                  size: 22,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      PolylineLayer(polylines: _buildSegments()),
      MarkerLayer(markers: _buildMarkers()),
    ]);
  }
}
