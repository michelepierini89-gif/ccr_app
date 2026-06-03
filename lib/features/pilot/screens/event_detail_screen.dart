import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../map/screens/track_map_screen.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  ParsedTrack? _parsedTrack;
  bool _isLoadingTrack = false;
  String? _loadedTrackUrl;

  Color _regStatusColor(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return AppColors.warning;
      case RegistrationStatus.approvato:
        return AppColors.success;
      case RegistrationStatus.rifiutato:
        return AppColors.error;
    }
  }

  String _regStatusLabel(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return 'Iscrizione in attesa di approvazione';
      case RegistrationStatus.approvato:
        return 'Iscrizione approvata';
      case RegistrationStatus.rifiutato:
        return 'Iscrizione rifiutata';
    }
  }

  Future<void> _autoLoadTrack(String url) async {
    if (_isLoadingTrack) return;
    setState(() {
      _isLoadingTrack = true;
      _loadedTrackUrl = url;
    });
    try {
      final bytes = await StorageService().downloadTrack(url);
      final content = utf8.decode(bytes);
      final ext = url.contains('track.kml') ? 'kml' : 'gpx';
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);
      if (mounted) setState(() => _parsedTrack = parsed);
    } catch (_) {
      if (mounted) setState(() => _loadedTrackUrl = null);
    } finally {
      if (mounted) setState(() => _isLoadingTrack = false);
    }
  }

  int? _indexFromId(String id) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(id);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final aVal =
        sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  int _nearestIdx(LatLng point, List<LatLng> pts) {
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dlat = point.latitude - pts[i].latitude;
      final dlng = point.longitude - pts[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  double? _specialLengthKm(SpecialModel s, List<LatLng> pts) {
    if (pts.isEmpty) return null;
    final startIdx = _indexFromId(s.waypointInizio.id) ??
        _nearestIdx(s.waypointInizio.latLng, pts);
    final endIdx = _indexFromId(s.waypointFine.id) ??
        _nearestIdx(s.waypointFine.latLng, pts);
    final a = min(startIdx, endIdx).clamp(0, pts.length - 1);
    final b = max(startIdx, endIdx).clamp(0, pts.length - 1);
    if (a >= b) return null;
    double total = 0.0;
    for (var i = a; i < b; i++) {
      total += _haversineKm(pts[i], pts[i + 1]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return eventAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Text('Evento non trovato',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }

        if (event.trackUrl != null &&
            _parsedTrack == null &&
            _loadedTrackUrl != event.trackUrl &&
            !_isLoadingTrack) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _autoLoadTrack(event.trackUrl!));
        }

        final trackPoints = _parsedTrack?.points ?? const [];
        final showMap = event.speciali.isNotEmpty || event.trackUrl != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event header
                Container(
                  color: AppColors.cardBackground,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.nome,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE d MMMM yyyy', 'it')
                                .format(event.data),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            event.luogo,
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      if (event.descrizione.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          event.descrizione,
                          style: const TextStyle(
                              color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),

                // Track map
                if (showMap) ...[
                  _isLoadingTrack
                      ? Container(
                          height: 220,
                          color: AppColors.cardBackground,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: AppColors.accent),
                                SizedBox(height: 8),
                                Text('Caricamento tracciato...',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 220,
                          child: TrackMapScreen(
                            trackPoints: trackPoints,
                            specials: event.speciali,
                            waypoints: event.speciali
                                .expand((s) =>
                                    [s.waypointInizio, s.waypointFine])
                                .toList(),
                            interactive: false,
                          ),
                        ),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Specials
                if (event.speciali.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: const Text(
                      'Prove Speciali',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: event.speciali.map((s) {
                        final kmLen = _specialLengthKm(s, trackPoints);
                        final cpCount = s.controlPoints.length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: s.color.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: s.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.nome,
                                      style: TextStyle(
                                        color: s.color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (kmLen != null || cpCount > 0)
                                      Text(
                                        [
                                          if (kmLen != null)
                                            '${kmLen.toStringAsFixed(1)} km',
                                          if (cpCount > 0)
                                            '$cpCount punt${cpCount == 1 ? "o" : "i"} di controllo',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Registration section
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ref.watch(currentUserModelProvider).when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent)),
                    error: (e, _) => const SizedBox(),
                    data: (user) {
                      if (user == null) return const SizedBox();
                      return FutureBuilder(
                        future: ref
                            .read(firestoreServiceProvider)
                            .getMyRegistration(widget.eventId, user.id),
                        builder: (context, regSnap) {
                          final reg = regSnap.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Iscrizione',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (reg != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _regStatusColor(reg.stato)
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            _regStatusColor(reg.stato)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        reg.stato ==
                                                RegistrationStatus
                                                    .approvato
                                            ? Icons.check_circle
                                            : reg.stato ==
                                                    RegistrationStatus
                                                        .rifiutato
                                                ? Icons.cancel
                                                : Icons.hourglass_empty,
                                        color: _regStatusColor(reg.stato),
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _regStatusLabel(reg.stato),
                                          style: TextStyle(
                                            color:
                                                _regStatusColor(reg.stato),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (regSnap.connectionState ==
                                  ConnectionState.done) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(firestoreServiceProvider)
                                            .registerForEvent(
                                              eventId: widget.eventId,
                                              userId: user.id,
                                              nome: user.nome,
                                              cognome: user.cognome,
                                            );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Iscrizione inviata!'),
                                              backgroundColor:
                                                  AppColors.success,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text('Errore: $e'),
                                              backgroundColor:
                                                  AppColors.error,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Iscriviti'),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                // Team section
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 12),
                      const Text(
                        'Squadra',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                              '/pilot/event/${widget.eventId}/team'),
                          icon: const Icon(Icons.group),
                          label: const Text('Gestisci squadra'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
