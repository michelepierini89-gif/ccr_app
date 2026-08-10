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
import '../../../core/utils/firebase_error_handler.dart';
import '../../map/widgets/track_layer.dart';
import '../providers/admin_provider.dart';

// ── Race status constants ────────────────────────────────────────────────────
const _kNotStarted = 'not_started';
const _kRacing = 'racing';
const _kFinished = 'finished';
const _kRetired = 'retired';

Color _statusColor(String status) => switch (status) {
      _kRacing => Colors.green,
      _kFinished => Colors.blue,
      _kRetired => Colors.grey,
      _ => Colors.amber,
    };

IconData _statusIcon(String status) => switch (status) {
      _kRacing => Icons.gps_fixed,
      _kFinished => Icons.check,
      _kRetired => Icons.close,
      _ => Icons.access_time,
    };

String _statusTooltip(String status) => switch (status) {
      _kRacing => 'In gara',
      _kFinished => 'Finito',
      _kRetired => 'Ritirato',
      _ => 'Non partito',
    };

// ── Screen ───────────────────────────────────────────────────────────────────

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
  bool _legendExpanded = false;

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

  String _pilotLabel(GpsPointModel p, List<RegistrationModel> regs) {
    try {
      final reg = regs.firstWhere((r) => r.userId == p.userId);
      return '${reg.nome} ${reg.cognome[0]}.';
    } catch (_) {
      return p.userId.length > 6 ? p.userId.substring(0, 6) : p.userId;
    }
  }

  Marker _buildPilotMarker(
      GpsPointModel p, String label) {
    final status = p.raceStatus;
    final Widget child = status == _kRacing
        ? _RacingMarker(label: label)
        : _StatusMarker(
            color: _statusColor(status),
            icon: _statusIcon(status),
            label: label,
          );
    return Marker(
      point: LatLng(p.lat, p.lng),
      width: 70,
      height: 64,
      child: Tooltip(
        message: _statusTooltip(status),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regsAsync = ref.watch(registrationsProvider(widget.eventId));
    final event = ref.watch(eventStreamProvider(widget.eventId)).valueOrNull;
    final startEnabled = event?.startEnabled ?? false;
    if (event?.activeTrackUrl != null) _loadTrack(event!.activeTrackUrl!);

    return StreamBuilder<List<GpsPointModel>>(
      stream: _pilotStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
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

        final pilotMap = {for (final p in pilots) p.userId: p};
        final approvedRegs = regs
            .where((r) => r.stato == RegistrationStatus.approvato)
            .toList();
        final countRacing =
            pilots.where((p) => p.raceStatus == _kRacing).length;
        final countFinished =
            pilots.where((p) => p.raceStatus == _kFinished).length;
        final countRetired =
            pilots.where((p) => p.raceStatus == _kRetired).length;
        final countNotStarted = approvedRegs
            .where((r) =>
                !pilotMap.containsKey(r.userId) ||
                pilotMap[r.userId]!.raceStatus == _kNotStarted)
            .length;

        final markers = <Marker>[
          for (final p in pilots)
            _buildPilotMarker(p, _pilotLabel(p, regs)),
        ];

        final racingPilots = pilots.where((p) => p.raceStatus == _kRacing);
        final mapCenter = racingPilots.isNotEmpty
            ? LatLng(racingPilots.first.lat, racingPilots.first.lng)
            : pilots.isNotEmpty
                ? LatLng(pilots.first.lat, pilots.first.lng)
                : const LatLng(44.0, 11.0);

        return Column(
          children: [
            // ── Status counter bar ──────────────────────────────────────────
            Container(
              color: AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.circle,
                    color: Colors.green,
                    label: 'In gara: $countRacing',
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.circle,
                    color: Colors.blue,
                    label: 'Finiti: $countFinished',
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.circle,
                    color: Colors.grey,
                    label: 'Rit: $countRetired',
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.circle,
                    color: Colors.amber,
                    label: 'N/P: $countNotStarted',
                  ),
                ],
              ),
            ),
            // ── Start enable toggle ─────────────────────────────────────────
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
                    startEnabled ? Icons.flag : Icons.hourglass_empty,
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
                              content:
                                  Text(FirebaseErrorHandler.getMessage(e)),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          startEnabled ? AppColors.error : AppColors.success,
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
            // ── Map ─────────────────────────────────────────────────────────
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
                  : Stack(
                      children: [
                        FlutterMap(
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
                            if (_eventTrackPoints.length >= 2) ...[
                              PolylineLayer(polylines: [
                                Polyline(
                                  points: _eventTrackPoints,
                                  color: Colors.red,
                                  strokeWidth: 3.0,
                                ),
                              ]),
                              TrackDirectionArrowsLayer(
                                  trackPoints: _eventTrackPoints),
                            ],
                            MarkerLayer(markers: markers),
                          ],
                        ),
                        // Collapsible legend
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: _MapLegend(
                            expanded: _legendExpanded,
                            onTap: () => setState(
                                () => _legendExpanded = !_legendExpanded),
                          ),
                        ),
                      ],
                    ),
            ),
            // ── Pilot chips ─────────────────────────────────────────────────
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
                      color: _statusColor(pilots[i].raceStatus),
                    ),
                  ),
                ),
              ),
            // ── Pilot status table ───────────────────────────────────────────
            _PilotStatusSection(
                eventId: widget.eventId,
                regs: regs,
                pilots: pilots),
          ],
        );
      },
    );
  }
}

// ── Marker widgets ────────────────────────────────────────────────────────────

class _RacingMarker extends StatefulWidget {
  final String label;
  const _RacingMarker({required this.label});

  @override
  State<_RacingMarker> createState() => _RacingMarkerState();
}

class _RacingMarkerState extends State<_RacingMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (ctx, child) =>
              Transform.scale(scale: _pulse.value, child: child),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.green,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 2)],
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StatusMarker extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _StatusMarker({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Map legend ────────────────────────────────────────────────────────────────

class _MapLegend extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _MapLegend({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: expanded ? _buildExpanded() : _buildCollapsed(),
      ),
    );
  }

  Widget _buildCollapsed() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(Colors.amber),
        const SizedBox(width: 3),
        _dot(Colors.green),
        const SizedBox(width: 3),
        _dot(Colors.blue),
        const SizedBox(width: 3),
        _dot(Colors.grey),
        const SizedBox(width: 5),
        const Icon(Icons.chevron_right, color: Colors.white, size: 14),
      ],
    );
  }

  Widget _buildExpanded() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Legenda',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            const Icon(Icons.chevron_left, color: Colors.white, size: 14),
          ],
        ),
        const SizedBox(height: 6),
        _legendRow(Colors.amber, Icons.access_time, 'Non partito'),
        const SizedBox(height: 4),
        _legendRow(Colors.green, Icons.gps_fixed, 'In gara'),
        const SizedBox(height: 4),
        _legendRow(Colors.blue, Icons.check, 'Finito'),
        const SizedBox(height: 4),
        _legendRow(Colors.grey, Icons.close, 'Ritirato'),
      ],
    );
  }

  Widget _legendRow(Color color, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 10),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatChip(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PilotChip extends StatelessWidget {
  final GpsPointModel pilot;
  final String label;
  final Color color;

  const _PilotChip({
    required this.pilot,
    required this.label,
    required this.color,
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
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
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

// ── Pilot status section ──────────────────────────────────────────────────────

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
    final approvedRegs = regs
        .where((r) => r.stato == RegistrationStatus.approvato)
        .toList();

    if (approvedRegs.isEmpty) return const SizedBox.shrink();

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
                final status = gps?.raceStatus ?? _kNotStarted;
                final color = _statusColor(status);
                final icon = _statusIcon(status);
                final statusLabel = switch (status) {
                  _kRacing => 'IN GARA',
                  _kFinished => 'FINITO',
                  _kRetired => 'RIT',
                  _ => 'N/P',
                };

                return Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 11),
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
