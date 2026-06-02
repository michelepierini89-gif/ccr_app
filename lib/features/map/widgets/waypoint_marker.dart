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

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: waypoints
          .map((wp) => Marker(
                point: wp.latLng,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => onTap?.call(wp),
                  child: Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _colorForWaypoint(wp),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.flag,
                            color: Colors.white, size: 14),
                      ),
                      Text(
                        wp.nome,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 8),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
