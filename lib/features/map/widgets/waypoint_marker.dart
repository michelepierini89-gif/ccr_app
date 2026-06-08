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

  /// Colore della speciale a cui appartiene il waypoint (per il bordo del marker
  /// inizio/fine), oppure null se non è un punto inizio/fine di una speciale.
  Color? _specialColorForWaypoint(WaypointModel wp) {
    for (final s in specials) {
      if (s.waypointInizio.id == wp.id) return s.color;
      if (s.waypointFine.id == wp.id) return s.color;
    }
    return null;
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
        final specialColor = _specialColorForWaypoint(wp);
        final label = labelInfo?.$1 ?? wp.nome;
        final isStart = labelInfo?.$2 ?? true;
        // Inizio = cerchio verde con triangolo play; Fine = cerchio rosso con
        // quadrato stop. Il bordo usa il colore della speciale corrispondente.
        final fillColor = labelInfo == null
            ? AppColors.textSecondary
            : (isStart ? AppColors.success : AppColors.error);
        final borderColor = specialColor ?? Colors.white;
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
                    color: fillColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                          color: fillColor.withValues(alpha: 0.5),
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
