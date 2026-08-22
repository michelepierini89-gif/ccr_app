import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/map/ccr_tile_provider.dart';
import '../../../core/map/map_style.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/models/route_variant_model.dart';
import '../../../core/providers/track_appearance_provider.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/pilot_provider.dart';
import '../providers/training_attempts_history_provider.dart';
import '../widgets/attempt_log_export.dart';

/// Traccia percorsa di UN tentativo di allenamento (punto 3 del test sul
/// campo 22/08/2026: "come già avviene per le gare") — versione ridotta di
/// `RaceResultScreen` (niente classifica/dispute CP, tutto già mostrato
/// nello storico tentativi): solo mappa + esportazione log tecnico.
class TrainingAttemptTrackScreen extends ConsumerStatefulWidget {
  final String eventId;
  final AttemptModel attempt;
  final List<AttemptSpecialRow> speciali;

  const TrainingAttemptTrackScreen({
    super.key,
    required this.eventId,
    required this.attempt,
    required this.speciali,
  });

  @override
  ConsumerState<TrainingAttemptTrackScreen> createState() =>
      _TrainingAttemptTrackScreenState();
}

class _TrainingAttemptTrackScreenState
    extends ConsumerState<TrainingAttemptTrackScreen> {
  final _mapController = MapController();
  List<LatLng> _refTrack = [];
  RouteVariantModel? _variant;
  bool _mapFitted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final event = await ref.read(eventProvider(widget.eventId).future);
      if (event == null || !mounted) return;
      final variant = event.routeVariant(
              widget.attempt.routeVariantId ?? event.activeRouteId) ??
          event.routeAAsVariant;
      _variant = variant;
      if (variant.trackUrl != null) {
        final bytes = await StorageService().downloadTrack(variant.trackUrl!);
        final content = utf8.decode(bytes);
        _refTrack = variant.trackUrl!.contains('.kml')
            ? GpxParser.parseKml(content).points
            : GpxParser.parseGpx(content).points;
      }
    } catch (_) {
      // Best-effort: nessuna traccia di riferimento, resta comunque
      // visibile la traccia pilota.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tryFitMap(List<LatLng> pilotPoints) {
    if (_mapFitted) return;
    final all = [...pilotPoints, ..._refTrack];
    if (all.isEmpty) return;
    _mapFitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var minLat = all.first.latitude, maxLat = all.first.latitude;
      var minLng = all.first.longitude, maxLng = all.first.longitude;
      for (final p in all) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
              LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(32),
        ));
      } catch (_) {}
    });
  }

  Future<void> _exportLog() => exportAttemptDiagnosticLog(
        context,
        startedAt: widget.attempt.startedAt,
        finishedAt: widget.attempt.finishedAt,
      );

  @override
  Widget build(BuildContext context) {
    final trackAppearance = ref.watch(trackAppearanceProvider);
    final pilotPoints = widget.attempt.pilotTrack;
    if (pilotPoints.isNotEmpty || _refTrack.isNotEmpty) {
      _tryFitMap(pilotPoints);
    }

    final markers = <Marker>[];
    final variant = _variant;
    if (variant != null) {
      final byId = {for (final s in widget.speciali) s.specialeId: s};
      final speciali = [...variant.speciali]
        ..sort((a, b) => a.ordine.compareTo(b.ordine));
      for (final s in speciali) {
        if (s.annullata) continue;
        markers.add(_psMarker(s.waypointInizio.latLng, 'PS${s.ordine + 1}▶',
            const Color(0xFF00C853), true));
        markers.add(_psMarker(s.waypointFine.latLng, '⏹ PS${s.ordine + 1}',
            AppColors.error, false));
        final row = byId[s.id];
        for (var i = 0; i < s.controlPoints.length; i++) {
          final cp = s.controlPoints[i];
          final passed =
              row?.tempo == null ? false : !row!.tempo!.missedCpPositions.contains(i + 1);
          markers.add(_cpMarker(cp.latLng, passed));
        }
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: Text('Tentativo ${widget.attempt.attemptNumber}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            tooltip: 'Esporta log tecnico',
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            onPressed: _exportLog,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(44.0, 11.0),
              initialZoom: 10,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              Opacity(
                opacity: trackAppearance.tileOpacity,
                child: TileLayer(
                  urlTemplate: trackAppearance.mapStyle.urlTemplate,
                  subdomains: trackAppearance.mapStyle.subdomains,
                  maxNativeZoom: trackAppearance.mapStyle.maxNativeZoom,
                  maxZoom: MapStyle.maxUiZoom.toDouble(),
                  userAgentPackageName: 'com.ccr.ccr_app',
                  tileProvider:
                      CcrTileProvider(styleId: trackAppearance.mapStyle.id),
                ),
              ),
              if (_refTrack.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _refTrack,
                    color: trackAppearance.refTrackColor,
                    strokeWidth: trackAppearance.refTrackWidth,
                  ),
                ]),
              if (pilotPoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: pilotPoints,
                    color: trackAppearance.trackColor,
                    strokeWidth: trackAppearance.trackWidth,
                  ),
                ]),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),
          if (_loading)
            const Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _LoadingBanner(),
            ),
        ],
      ),
    );
  }

  Marker _psMarker(LatLng point, String label, Color color, bool isStart) =>
      Marker(
        point: point,
        width: 66,
        height: 52,
        rotate: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            Icon(isStart ? Icons.flag : Icons.stop_circle_outlined,
                color: color, size: 16),
          ],
        ),
      );

  Marker _cpMarker(LatLng point, bool passed) => Marker(
        point: point,
        width: 20,
        height: 20,
        rotate: true,
        child: Container(
          decoration: BoxDecoration(
            color: passed ? const Color(0xFF00C853) : AppColors.error,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Icon(passed ? Icons.check : Icons.close,
              color: Colors.white, size: 11),
        ),
      );
}

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          ),
          SizedBox(width: 8),
          Text('Caricamento traccia di riferimento…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
