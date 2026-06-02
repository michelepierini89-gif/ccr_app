import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/special_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../widgets/track_layer.dart';
import '../widgets/waypoint_marker.dart';
import '../../../core/theme/app_colors.dart';

class TrackMapScreen extends StatefulWidget {
  final List<LatLng> trackPoints;
  final List<SpecialModel> specials;
  final List<WaypointModel> waypoints;
  final bool interactive;

  const TrackMapScreen({
    super.key,
    required this.trackPoints,
    required this.specials,
    required this.waypoints,
    this.interactive = true,
  });

  @override
  State<TrackMapScreen> createState() => _TrackMapScreenState();
}

class _TrackMapScreenState extends State<TrackMapScreen> {
  WaypointModel? _selectedWaypoint;

  LatLng get _center {
    if (widget.trackPoints.isEmpty && widget.waypoints.isEmpty) {
      return const LatLng(44.0, 11.0); // Italy center
    }
    final pts = widget.trackPoints.isNotEmpty
        ? widget.trackPoints
        : widget.waypoints.map((w) => w.latLng).toList();
    final avgLat =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final avgLng =
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(avgLat, avgLng);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              interactionOptions: InteractionOptions(
                flags: widget.interactive
                    ? InteractiveFlag.all
                    : InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ccr.ccr_app',
              ),
              TrackLayer(
                  trackPoints: widget.trackPoints,
                  specials: widget.specials),
              WaypointMarkersLayer(
                waypoints: widget.waypoints,
                specials: widget.specials,
                onTap: (wp) =>
                    setState(() => _selectedWaypoint = wp),
              ),
            ],
          ),
        ),
        if (_selectedWaypoint != null)
          Container(
            color: AppColors.cardBackground,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedWaypoint!.nome,
                    style:
                        const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                Text(
                  _selectedWaypoint!.type.name,
                  style: const TextStyle(
                      color: AppColors.textSecondary),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary),
                  onPressed: () =>
                      setState(() => _selectedWaypoint = null),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
