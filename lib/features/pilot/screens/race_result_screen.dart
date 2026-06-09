import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../providers/pilot_provider.dart';

class RaceResultScreen extends ConsumerStatefulWidget {
  final String eventId;
  const RaceResultScreen({super.key, required this.eventId});

  @override
  ConsumerState<RaceResultScreen> createState() => _RaceResultScreenState();
}

class _RaceResultScreenState extends ConsumerState<RaceResultScreen> {
  final _mapController = MapController();
  List<LatLng> _refTrack = [];
  bool _mapFitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefTrack());
  }

  Future<void> _loadRefTrack() async {
    try {
      final event = await ref.read(eventProvider(widget.eventId).future);
      if (event?.trackUrl == null || !mounted) return;
      final bytes = await StorageService().downloadTrack(event!.trackUrl!);
      final content = utf8.decode(bytes);
      final pts = event.trackUrl!.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
      if (mounted) setState(() => _refTrack = pts);
    } catch (_) {}
  }

  void _tryFitMap(List<LatLng> pilotPoints) {
    if (_mapFitted) return;
    final all = [...pilotPoints, ..._refTrack];
    if (all.isEmpty) return;
    _mapFitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var minLat = all.first.latitude;
      var maxLat = all.first.latitude;
      var minLng = all.first.longitude;
      var maxLng = all.first.longitude;
      for (final p in all) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          padding: const EdgeInsets.all(32),
        ));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(myPilotStatusProvider(widget.eventId));
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final classAv = ref.watch(classificaProvider(widget.eventId));
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;
    final regAsync = ref.watch(myRegistrationStreamProvider(widget.eventId));
    final squadraId = regAsync.valueOrNull?.squadraId;

    final statusData = statusAsync.valueOrNull;
    final event = eventAsync.valueOrNull;

    final pilotPoints = _parsePilotTrack(statusData);

    final entries = classAv.valueOrNull ?? [];
    ClassificaEntry? myEntry;
    for (final e in entries) {
      if (squadraId != null && e.entryId == squadraId) {
        myEntry = e;
        break;
      }
      if (userId != null && e.entryId == userId) {
        myEntry = e;
        break;
      }
    }

    if (pilotPoints.isNotEmpty || _refTrack.isNotEmpty) {
      _tryFitMap(pilotPoints);
    }

    final waypointPassati = _parseWaypointPassati(statusData);
    final mapHeight = MediaQuery.of(context).size.height * 0.45;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: Text(
          event != null ? 'Risultato — ${event.nome}' : 'Risultato gara',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            child: _buildMap(pilotPoints, event, waypointPassati),
          ),
          Expanded(
            child: _buildSummary(
              context,
              event,
              myEntry,
              statusData,
              pilotPoints,
            ),
          ),
        ],
      ),
    );
  }

  // ── Data helpers ─────────────────────────────────────────────────────────────

  List<LatLng> _parsePilotTrack(Map<String, dynamic>? data) {
    final raw = data?['pilotTrack'];
    if (raw is! List) return [];
    final result = <LatLng>[];
    for (final item in raw) {
      if (item is Map) {
        final lat = (item['lat'] as num?)?.toDouble();
        final lng = (item['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) result.add(LatLng(lat, lng));
      }
    }
    return result;
  }

  Set<String> _parseWaypointPassati(Map<String, dynamic>? data) {
    final raw = data?['waypointPassati'];
    if (raw is! List) return {};
    return {for (final v in raw) v.toString()};
  }

  SpecialTempo? _findTempo(ClassificaEntry? entry, String specialeId) {
    if (entry == null) return null;
    for (final t in entry.specialiCompletati) {
      if (t.specialeId == specialeId) return t;
    }
    return null;
  }

  double _computeDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _haversineKm(points[i - 1], points[i]);
    }
    return total;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(x));
  }

  // ── Map ──────────────────────────────────────────────────────────────────────

  Widget _buildMap(
    List<LatLng> pilotPoints,
    EventModel? event,
    Set<String> waypointPassati,
  ) {
    final markers = <Marker>[];
    if (event != null) {
      final speciali = [...event.speciali]
        ..sort((a, b) => a.ordine.compareTo(b.ordine));
      for (final s in speciali) {
        if (s.annullata) continue;
        markers.add(_psMarker(s.waypointInizio.latLng, 'PS${s.ordine}▶',
            const Color(0xFF00C853), true));
        markers.add(_psMarker(s.waypointFine.latLng, '⏹ PS${s.ordine}',
            AppColors.error, false));
        for (final cp in s.controlPoints) {
          markers.add(_cpMarker(cp.latLng, waypointPassati.contains(cp.id)));
        }
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(44.0, 11.0),
        initialZoom: 10,
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
              color: Colors.red.withValues(alpha: 0.5),
              strokeWidth: 2.5,
            ),
          ]),
        if (pilotPoints.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: pilotPoints,
              color: Colors.blue,
              strokeWidth: 3.5,
            ),
          ]),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  Marker _psMarker(LatLng point, String label, Color color, bool isStart) =>
      Marker(
        point: point,
        width: 66,
        height: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(
              isStart ? Icons.flag : Icons.stop_circle_outlined,
              color: color,
              size: 16,
            ),
          ],
        ),
      );

  Marker _cpMarker(LatLng point, bool passed) => Marker(
        point: point,
        width: 20,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: passed ? const Color(0xFF00C853) : AppColors.error,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Icon(
            passed ? Icons.check : Icons.close,
            color: Colors.white,
            size: 11,
          ),
        ),
      );

  // ── Summary ──────────────────────────────────────────────────────────────────

  Widget _buildSummary(
    BuildContext context,
    EventModel? event,
    ClassificaEntry? myEntry,
    Map<String, dynamic>? statusData,
    List<LatLng> pilotPoints,
  ) {
    final speciali = event != null
        ? ([...event.speciali]..sort((a, b) => a.ordine.compareTo(b.ordine)))
            .where((s) => !s.annullata)
            .toList()
        : <SpecialModel>[];

    final distanceKm = _computeDistanceKm(pilotPoints);
    final retiredReason = statusData?['retiredReason'] as String?;
    final finishedAt = (statusData?['finishedAt'] as Timestamp?)?.toDate();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myEntry != null) ...[
            _StatusHeader(entry: myEntry),
            const SizedBox(height: 16),
          ],
          if (speciali.isNotEmpty) ...[
            const Text(
              'Prove speciali',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...speciali.map(
              (s) => _SpecialRow(
                special: s,
                tempo: _findTempo(myEntry, s.id),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _StatsRow(
            distanceKm: distanceKm,
            tempoTotale: myEntry?.tempoTotale,
            finishedAt: finishedAt,
            retiredReason: retiredReason,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Status header ──────────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final ClassificaEntry entry;
  const _StatusHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isRetired = entry.ritirato;
    final isTimeout = entry.retiredReason == 'timeout';
    final posColor = isRetired
        ? AppColors.error
        : entry.posizione == 1
            ? const Color(0xFFFFD700)
            : AppColors.accent;

    final posLabel = isRetired
        ? (isTimeout ? '⏱ T/O' : 'RIT')
        : entry.posizione == 0
            ? 'NC'
            : '${entry.posizione}°';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: posColor),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                posLabel,
                style: TextStyle(
                  color: posColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'posizione',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 20),
          const VerticalDivider(color: AppColors.border, width: 1),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.teamNome,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.tempoTotaleFormatted,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Special row ────────────────────────────────────────────────────────────────

class _SpecialRow extends StatelessWidget {
  final SpecialModel special;
  final SpecialTempo? tempo;

  const _SpecialRow({required this.special, required this.tempo});

  @override
  Widget build(BuildContext context) {
    final done = tempo != null;
    final hasMissedCp = done && !tempo!.controlPointsOk;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done
              ? (hasMissedCp
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : AppColors.border)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Ordine badge
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: special.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '${special.ordine}',
              style: TextStyle(
                color: special.color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + CP warning
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  special.nome,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hasMissedCp)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '⚠ CP mancati: ${tempo!.missedCpPositions.length}',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Time
          Text(
            done ? tempo!.tempoFormatted : '— Non completata',
            style: TextStyle(
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: done ? 14 : 12,
              fontWeight: done ? FontWeight.bold : FontWeight.normal,
              fontFamily: done ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final double distanceKm;
  final Duration? tempoTotale;
  final DateTime? finishedAt;
  final String? retiredReason;

  const _StatsRow({
    required this.distanceKm,
    required this.tempoTotale,
    required this.finishedAt,
    required this.retiredReason,
  });

  @override
  Widget build(BuildContext context) {
    final isRetired = retiredReason != null;
    final isTimeout = retiredReason == 'timeout';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(
                icon: Icons.straighten,
                label: 'Distanza percorsa',
                value: distanceKm > 0
                    ? '${distanceKm.toStringAsFixed(1)} km'
                    : '—',
              ),
              const SizedBox(width: 12),
              _StatChip(
                icon: Icons.timer,
                label: 'Tempo totale PS',
                value: (tempoTotale != null && tempoTotale != Duration.zero)
                    ? _formatDuration(tempoTotale!)
                    : '—',
              ),
            ],
          ),
          if (finishedAt != null || isRetired) ...[
            const Divider(color: AppColors.border, height: 20),
            Row(
              children: [
                Icon(
                  isRetired ? Icons.flag_outlined : Icons.check_circle_outline,
                  size: 16,
                  color: isRetired ? AppColors.error : AppColors.success,
                ),
                const SizedBox(width: 8),
                Text(
                  isRetired
                      ? (isTimeout
                          ? 'Ritirato per superamento tempo massimo'
                          : 'Gara terminata con ritiro')
                      : finishedAt != null
                          ? 'Arrivo alle ${DateFormat('HH:mm').format(finishedAt!.toLocal())}'
                          : 'Gara completata',
                  style: TextStyle(
                    color: isRetired ? AppColors.error : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final cs = (d.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
