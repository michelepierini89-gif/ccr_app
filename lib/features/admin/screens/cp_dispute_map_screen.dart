import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/cp_dispute_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../providers/admin_provider.dart';

/// Mappa di analisi per una singola voce contestata (Step 42): traccia del
/// pilota, posizione del CP con il suo raggio di validità, punto di
/// massimo avvicinamento evidenziato con la distanza, e la traccia di
/// riferimento dell'evento per contesto — lo strumento che permette
/// all'admin di decidere con cognizione invece che a intuito.
class CpDisputeMapScreen extends ConsumerStatefulWidget {
  final EventModel event;
  final String pilotId;
  final String pilotName;
  final DisputedCp cp;

  const CpDisputeMapScreen({
    super.key,
    required this.event,
    required this.pilotId,
    required this.pilotName,
    required this.cp,
  });

  @override
  ConsumerState<CpDisputeMapScreen> createState() =>
      _CpDisputeMapScreenState();
}

class _CpDisputeMapScreenState extends ConsumerState<CpDisputeMapScreen> {
  final _mapController = MapController();
  bool _loading = true;
  String? _error;
  List<LatLng> _pilotTrack = const [];
  List<LatLng> _refTrack = const [];
  LatLng? _cpPoint;
  double _cpRadiusMeters = AppConstants.waypointCheckpointRadiusMeters;
  LatLng? _closestPoint;
  double? _closestDistanceMeters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(firestoreServiceProvider);
      final pilotStatus =
          await svc.getPilotStatusOnce(widget.event.id, widget.pilotId);
      final routeId = pilotStatus?['routeVariantId'] as String? ?? 'A';
      final variant =
          widget.event.routeVariant(routeId) ?? widget.event.routeAAsVariant;

      final special = variant.speciali
          .where((s) => s.id == widget.cp.specialeId)
          .firstOrNull;
      WaypointModel? cpWaypoint;
      if (special != null) {
        cpWaypoint =
            special.controlPoints.where((c) => c.id == widget.cp.cpId).firstOrNull;
      }

      List<LatLng> refTrack = const [];
      if (variant.trackUrl != null) {
        try {
          final bytes = await StorageService().downloadTrack(variant.trackUrl!);
          final content = utf8.decode(bytes);
          final parsed = variant.trackUrl!.contains('.kml')
              ? GpxParser.parseKml(content)
              : GpxParser.parseGpx(content);
          refTrack = parsed.points;
        } catch (_) {
          // Traccia di riferimento accessoria per contesto — se non si
          // scarica, l'analisi resta comunque possibile con traccia
          // pilota + CP.
        }
      }

      final samples = await svc.getFullPilotTrack(widget.event.id, widget.pilotId);
      final pilotTrack =
          samples.map((s) => LatLng(s.lat, s.lng)).toList(growable: false);

      LatLng? closest;
      double? closestDist;
      if (cpWaypoint != null && pilotTrack.isNotEmpty) {
        for (final p in pilotTrack) {
          final d = LocationUtils.haversineDistance(
              p.latitude, p.longitude, cpWaypoint.lat, cpWaypoint.lng);
          if (closestDist == null || d < closestDist) {
            closestDist = d;
            closest = p;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _pilotTrack = pilotTrack;
        _refTrack = refTrack;
        _cpPoint = cpWaypoint?.latLng;
        _cpRadiusMeters =
            cpWaypoint?.checkpointRadiusMeters ?? AppConstants.waypointCheckpointRadiusMeters;
        _closestPoint = closest;
        _closestDistanceMeters = closestDist ?? widget.cp.distanceMeters;
        _loading = false;
      });
      _fitBounds();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _fitBounds() {
    final points = [
      ?_cpPoint,
      ..._pilotTrack,
    ];
    if (points.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        var minLat = points.first.latitude, maxLat = points.first.latitude;
        var minLng = points.first.longitude, maxLng = points.first.longitude;
        for (final p in points) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(48),
        ));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.pilotName} — P${widget.cp.position}'),
      ),
      body: SafeArea(
        bottom: true,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : _error != null
                ? Center(
                    child: Text('Errore: $_error',
                        style: const TextStyle(color: AppColors.error)))
                : Column(
                    children: [
                      Expanded(child: _buildMap()),
                      _buildInfoPanel(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(44.0, 11.0),
        initialZoom: 13,
        interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.ccr_app',
        ),
        if (_refTrack.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
                points: _refTrack,
                color: Colors.red.withValues(alpha: 0.4),
                strokeWidth: 2.5),
          ]),
        if (_pilotTrack.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(points: _pilotTrack, color: Colors.blue, strokeWidth: 3),
          ]),
        if (_closestPoint != null && _cpPoint != null)
          PolylineLayer(polylines: [
            Polyline(
                points: [_closestPoint!, _cpPoint!],
                color: AppColors.warning,
                strokeWidth: 2,
                pattern: const StrokePattern.dotted()),
          ]),
        if (_cpPoint != null)
          CircleLayer(circles: [
            CircleMarker(
              point: _cpPoint!,
              radius: _cpRadiusMeters,
              useRadiusInMeter: true,
              color: AppColors.warning.withValues(alpha: 0.15),
              borderColor: AppColors.warning,
              borderStrokeWidth: 2,
            ),
          ]),
        MarkerLayer(markers: [
          if (_cpPoint != null)
            Marker(
              point: _cpPoint!,
              width: 34,
              height: 34,
              child: const Icon(Icons.flag_circle,
                  color: AppColors.warning, size: 30),
            ),
          if (_closestPoint != null)
            Marker(
              point: _closestPoint!,
              width: 26,
              height: 26,
              child: const Icon(Icons.gps_fixed,
                  color: AppColors.accent, size: 22),
            ),
        ]),
      ],
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: AppColors.cardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.cp.specialeNome} — ${widget.cp.cpNome}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 6),
          _legendRow(Colors.blue, 'Traccia pilota (${_pilotTrack.length} punti)'),
          _legendRow(Colors.red, 'Traccia di riferimento evento'),
          _legendRow(AppColors.warning,
              'Raggio di validità CP (${_cpRadiusMeters.round()} m)'),
          _legendRow(AppColors.accent, 'Punto di massimo avvicinamento'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_closestDistanceMeters ?? 0) <= _cpRadiusMeters
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _closestDistanceMeters != null
                  ? 'Distanza minima rilevata: ${_closestDistanceMeters!.round()} m'
                      '${_closestDistanceMeters! <= _cpRadiusMeters ? ' — entro il raggio di validità' : ' — fuori dal raggio di validità'}'
                  : 'Distanza minima non disponibile (traccia completa non trovata)',
              style: TextStyle(
                  color: (_closestDistanceMeters ?? 0) <= _cpRadiusMeters
                      ? AppColors.success
                      : AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      );
}
