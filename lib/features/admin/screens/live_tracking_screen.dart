import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';
import '../../classifica/providers/classifica_provider.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String eventId;
  const LiveTrackingScreen({super.key, required this.eventId});

  @override
  ConsumerState<LiveTrackingScreen> createState() =>
      _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  List<LatLng> _eventTrackPoints = [];
  String? _loadedTrackUrl;
  late final Stream<List<GpsPointModel>> _pilotStream;

  static const _onlineThreshold = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _pilotStream = ref
        .read(firestoreServiceProvider)
        .getPilotTracking(widget.eventId);
  }

  Future<void> _loadTrack(String url) async {
    if (url == _loadedTrackUrl) return;
    _loadedTrackUrl = url;
    try {
      final bytes = await StorageService().downloadTrack(url);
      final content = utf8.decode(bytes);
      final pts = url.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
      if (mounted) setState(() => _eventTrackPoints = pts);
    } catch (_) {}
  }

  bool _isOnline(GpsPointModel p) =>
      DateTime.now().difference(p.timestamp) < _onlineThreshold;

  Color _pilotColor(int index) =>
      AppColors.specialColors[index % AppColors.specialColors.length];

  String _pilotLabel(GpsPointModel p, List<RegistrationModel> regs) {
    try {
      final reg = regs.firstWhere((r) => r.userId == p.userId);
      return '${reg.nome} ${reg.cognome[0]}.';
    } catch (_) {
      return p.userId.length > 6 ? p.userId.substring(0, 6) : p.userId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final regsAsync = ref.watch(registrationsProvider(widget.eventId));
    final event = ref.watch(eventStreamProvider(widget.eventId)).valueOrNull;
    final startEnabled = event?.startEnabled ?? false;
    if (event?.trackUrl != null) _loadTrack(event!.trackUrl!);

    return StreamBuilder<List<GpsPointModel>>(
      stream: _pilotStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Errore: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.error)));
        }
        final pilots = snapshot.data ?? [];
        final regs = regsAsync.valueOrNull ?? [];

        final onlinePilots = pilots.where(_isOnline).toList();
        final offlinePilots = pilots.where((p) => !_isOnline(p)).toList();

        final markers = <Marker>[];
        for (int i = 0; i < pilots.length; i++) {
          final p = pilots[i];
          final online = _isOnline(p);
          final color = online ? _pilotColor(i) : AppColors.textSecondary;
          final label = _pilotLabel(p, regs);
          markers.add(Marker(
            point: LatLng(p.lat, p.lng),
            width: 70,
            height: 64,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: online
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    online ? Icons.person : Icons.person_off,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: online ? color : AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ));
        }

        final mapCenter = onlinePilots.isNotEmpty
            ? LatLng(onlinePilots.first.lat, onlinePilots.first.lng)
            : pilots.isNotEmpty
                ? LatLng(pilots.first.lat, pilots.first.lng)
                : const LatLng(44.0, 11.0);

        return Column(
          children: [
            // Stats bar
            Container(
              color: AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.circle,
                    color: AppColors.success,
                    label: '${onlinePilots.length} online',
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.circle,
                    color: AppColors.textSecondary,
                    label: '${offlinePilots.length} offline',
                  ),
                  const Spacer(),
                  Text(
                    '${pilots.length} piloti totali',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Start enable toggle
            Container(
              width: double.infinity,
              color: startEnabled
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    startEnabled
                        ? Icons.flag
                        : Icons.hourglass_empty,
                    color: startEnabled
                        ? AppColors.success
                        : AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      startEnabled
                          ? 'Partenza abilitata — i piloti possono avviare il GPS'
                          : 'Partenza disabilitata — i piloti sono in attesa',
                      style: TextStyle(
                        color: startEnabled
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(firestoreServiceProvider)
                            .setStartEnabled(widget.eventId, !startEnabled);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Errore: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: startEnabled
                          ? AppColors.error
                          : AppColors.success,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      startEnabled ? 'Blocca' : 'Abilita',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Map
            Expanded(
              child: pilots.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gps_off,
                              color: AppColors.textSecondary, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Nessun pilota in tracciamento',
                            style:
                                TextStyle(color: AppColors.textSecondary),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'I piloti appariranno qui quando\navviano la registrazione GPS',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : FlutterMap(
                      options: MapOptions(
                        initialCenter: mapCenter,
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ccr.ccr_app',
                        ),
                        // Event GPX track in red
                        if (_eventTrackPoints.length >= 2)
                          PolylineLayer(polylines: [
                            Polyline(
                              points: _eventTrackPoints,
                              color: Colors.red,
                              strokeWidth: 3.0,
                            ),
                          ]),
                        MarkerLayer(markers: markers),
                      ],
                    ),
            ),
            // Pilot chips
            if (pilots.isNotEmpty)
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 66,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: pilots.length,
                    itemBuilder: (ctx, i) => _PilotChip(
                      pilot: pilots[i],
                      label: _pilotLabel(pilots[i], regs),
                      color: _isOnline(pilots[i])
                          ? _pilotColor(i)
                          : AppColors.textSecondary,
                      online: _isOnline(pilots[i]),
                    ),
                  ),
                ),
              ),
            // Pilot status table
            _PilotStatusSection(eventId: widget.eventId, regs: regs, pilots: pilots),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatChip(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PilotChip extends StatelessWidget {
  final GpsPointModel pilot;
  final String label;
  final Color color;
  final bool online;

  const _PilotChip({
    required this.pilot,
    required this.label,
    required this.color,
    required this.online,
  });

  String _elapsed() {
    final diff = DateTime.now().difference(pilot.timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s fa';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    return '${diff.inHours}h fa';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: online ? AppColors.success : AppColors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            _elapsed(),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── Pilot status section ───────────────────────────────────────────────────────

class _PilotStatusSection extends ConsumerWidget {
  final String eventId;
  final List<RegistrationModel> regs;
  final List<GpsPointModel> pilots;

  const _PilotStatusSection({
    required this.eventId,
    required this.regs,
    required this.pilots,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withdrawalsAv = ref.watch(withdrawalsStreamProvider(eventId));
    final withdrawals = withdrawalsAv.valueOrNull ?? {};

    final approvedRegs = regs
        .where((r) => r.stato == RegistrationStatus.approvato)
        .toList();

    if (approvedRegs.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final pilotMap = {for (final p in pilots) p.userId: p};

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Stato piloti (${approvedRegs.length} iscritti)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: approvedRegs.length,
              itemBuilder: (ctx, i) {
                final reg = approvedRegs[i];
                final gps = pilotMap[reg.userId];
                final isWithdrawn = withdrawals.contains(reg.userId);
                final isOnline = gps != null &&
                    now.difference(gps.timestamp).inSeconds < 60;
                final hasGps = gps != null;

                Color color;
                String statusLabel;
                IconData statusIcon;

                if (isWithdrawn) {
                  color = AppColors.error;
                  statusLabel = 'RIT';
                  statusIcon = Icons.flag;
                } else if (isOnline) {
                  color = AppColors.success;
                  statusLabel = 'IN GARA';
                  statusIcon = Icons.gps_fixed;
                } else if (hasGps) {
                  color = AppColors.warning;
                  statusLabel = 'OFFLINE';
                  statusIcon = Icons.gps_not_fixed;
                } else {
                  color = AppColors.textSecondary;
                  statusLabel = 'N/P';
                  statusIcon = Icons.person_outline;
                }

                return Container(
                  margin:
                      const EdgeInsets.only(right: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: color, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        '${reg.nome} ${reg.cognome[0]}.',
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                            color: color.withValues(alpha: 0.7),
                            fontSize: 9),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
