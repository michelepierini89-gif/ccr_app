import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/utils/gpx_utils.dart';
import 'speed_zone_marker.dart';

/// Disegna le zone a velocità controllata sulla traccia di riferimento:
/// il segmento tra inizio e fine zona in giallo/lime sopra la traccia rossa,
/// con il cartello limite di velocità ([SpeedZoneMarkerIcon]) a inizio zona.
/// Usato sia nell'editor admin (specials_editor_screen.dart) sia nella mappa
/// di navigazione del pilota (gps_recording_screen.dart) e nel riepilogo
/// gara (race_result_screen.dart), in modo che lo stile sia identico.
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
        // flutter_map non supporta nativamente un pattern dash sulle
        // polyline: fallback a giallo/lime semi-trasparente, strokeWidth
        // maggiore della traccia rossa sottostante, ben visibile sopra di
        // essa senza coprirla del tutto.
        polylines.add(Polyline(
          points: trackPoints.sublist(lo, hi + 1),
          color: const Color(0xFFCCFF00).withValues(alpha: 0.7),
          strokeWidth: 8,
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
              width: 40,
              height: 40,
              rotate: true,
              child: IgnorePointer(
                child: SpeedZoneMarkerIcon(
                    speedLimit: z.maxSpeedKmh.round()),
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
