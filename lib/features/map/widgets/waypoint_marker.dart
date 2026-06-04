import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/theme/app_colors.dart';

class WaypointMarkersLayer extends StatelessWidget {
  final List<WaypointModel> waypoints;
  final List<SpecialModel> specials;
  final void Function(WaypointModel)? onTap;

  const WaypointMarkersLayer({
    super.key,
    required this.waypoints,
    required this.specials,
    this.onTap,
  });

  Color _colorForWaypoint(WaypointModel wp) {
    for (final s in specials) {
      if (s.waypointInizio.id == wp.id) return s.color;
      if (s.waypointFine.id == wp.id) return s.color;
    }
    return AppColors.textSecondary;
  }

  /// Returns (label, isStart) for a waypoint that belongs to a special.
  /// Returns null if the waypoint is not an inizio/fine of any special.
  (String, bool)? _labelFor(WaypointModel wp) {
    for (var i = 0; i < specials.length; i++) {
      final s = specials[i];
      final psLabel = 'PS${i + 1}';
      if (s.waypointInizio.id == wp.id) return (psLabel, true);
      if (s.waypointFine.id == wp.id) return (psLabel, false);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: waypoints.map((wp) {
        final labelInfo = _labelFor(wp);
        final color = _colorForWaypoint(wp);
        final label = labelInfo?.$1 ?? wp.nome;
        final isStart = labelInfo?.$2 ?? true;
        return Marker(
          point: wp.latLng,
          width: 48,
          height: 48,
          child: GestureDetector(
            onTap: () => onTap?.call(wp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 4)
                    ],
                  ),
                  child: Icon(
                    isStart ? Icons.play_arrow : Icons.stop,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
