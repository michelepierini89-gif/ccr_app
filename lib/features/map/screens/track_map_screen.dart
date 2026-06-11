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
  final WaypointModel? fuelPoint;
  final List<DangerPointModel> dangerPoints;

  const TrackMapScreen({
    super.key,
    required this.trackPoints,
    required this.specials,
    required this.waypoints,
    this.interactive = true,
    this.fuelPoint,
    this.dangerPoints = const [],
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

  MapOptions get _mapOptions {
    if (widget.trackPoints.isNotEmpty) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.trackPoints),
          padding: const EdgeInsets.all(32),
        ),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all
              : InteractiveFlag.none,
        ),
      );
    }
    return MapOptions(
      initialCenter: _center,
      initialZoom: 13,
      interactionOptions: InteractionOptions(
        flags: widget.interactive
            ? InteractiveFlag.all
            : InteractiveFlag.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: _mapOptions,
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
                dangerPoints: widget.dangerPoints,
              ),
              if (widget.fuelPoint != null)
                MarkerLayer(markers: [
                  Marker(
                    point: widget.fuelPoint!.latLng,
                    width: 44,
                    height: 52,
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _selectedWaypoint = widget.fuelPoint),
                      child: Column(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.amber.withValues(alpha: 0.5),
                                    blurRadius: 6)
                              ],
                            ),
                            child: const Icon(Icons.local_gas_station,
                                color: Colors.white, size: 20),
                          ),
                          const Text('Ristoro',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black54, blurRadius: 2)
                                  ])),
                        ],
                      ),
                    ),
                  ),
                ]),
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
