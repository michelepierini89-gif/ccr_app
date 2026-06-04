import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../providers/pilot_provider.dart';

class GpsRecordingScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const GpsRecordingScreen({super.key, this.eventId});

  @override
  ConsumerState<GpsRecordingScreen> createState() =>
      _GpsRecordingScreenState();
}

class _GpsRecordingScreenState extends ConsumerState<GpsRecordingScreen>
    with SingleTickerProviderStateMixin {
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late final MapController _mapController;
  bool _followMode = true;
  double _mapZoom = 15.0;
  bool _programmaticMove = false;

  List<LatLng> _eventTrackPoints = [];
  bool _eventTrackLoaded = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startElapsedTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEventTrack());
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final gps = ref.read(gpsServiceProvider);
      if (gps.isRecording && gps.recordingStart != null && mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(gps.recordingStart!);
        });
      }
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadEventTrack() async {
    if (widget.eventId == null || _eventTrackLoaded) return;
    _eventTrackLoaded = true;
    try {
      final event = await ref.read(eventProvider(widget.eventId!).future);
      if (event?.trackUrl == null || !mounted) return;
      final bytes = await StorageService().downloadTrack(event!.trackUrl!);
      final content = utf8.decode(bytes);
      final pts = event.trackUrl!.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
      if (mounted) setState(() => _eventTrackPoints = pts);
    } catch (_) {}
  }

  double _calcBearing(List<LatLng> track) {
    if (track.length < 2) return 0;
    final a = track[track.length - 2];
    final b = track[track.length - 1];
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return atan2(y, x);
  }

  Marker _psMarker(LatLng point, String label, Color color, bool isStart) =>
      Marker(
        point: point,
        width: 58,
        height: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$label ${isStart ? '▶' : '■'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Icon(isStart ? Icons.play_arrow : Icons.stop,
                color: color, size: 18),
          ],
        ),
      );

  void _recenter() {
    final pos = ref.read(gpsServiceProvider).lastPosition;
    if (pos != null) {
      _programmaticMove = true;
      _mapController.move(
          LatLng(pos.latitude, pos.longitude), _mapZoom);
    }
    setState(() => _followMode = true);
  }

  Future<void> _toggleRecording() async {
    final gps = ref.read(gpsServiceProvider);
    if (gps.isRecording) {
      await gps.stopRecording();
      setState(() => _elapsed = Duration.zero);
      return;
    }

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Utente non autenticato'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    if (widget.eventId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nessun evento selezionato. Vai alla lista gare.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    try {
      final event = await ref.read(eventProvider(widget.eventId!).future);
      final waypoints = <WaypointModel>[];
      if (event != null) {
        for (final s in event.speciali) {
          waypoints.add(s.waypointInizio);
          waypoints.addAll(s.controlPoints);
          waypoints.add(s.waypointFine);
        }
      }
      await gps.startRecording(
        eventId: widget.eventId!,
        userId: user.uid,
        waypoints: waypoints,
        specials: event?.speciali ?? [],
      );
      setState(() => _followMode = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _confirmWithdrawal() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma ritiro',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Sei sicuro di volerti ritirare dalla gara?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Ultima conferma',
            style: TextStyle(color: AppColors.error)),
        content: const Text(
          'Questa azione non può essere annullata.\n'
          'La traccia parziale verrà salvata e l\'admin verrà notificato.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('CONFERMO IL RITIRO'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final gps = ref.read(gpsServiceProvider);
    final user = ref.read(authStateProvider).valueOrNull;
    final eventId = widget.eventId;
    final partialTrack = List.of(gps.localTrack);
    await gps.stopRecording();
    setState(() => _elapsed = Duration.zero);

    if (user != null && eventId != null) {
      try {
        await ref
            .read(firestoreServiceProvider)
            .recordWithdrawal(eventId, user.uid, partialTrack: partialTrack);
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ritiro registrato. L\'admin è stato notificato.'),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 4),
      ));
    }
  }

  Color _modeColor(GpsMode mode) => switch (mode) {
        GpsMode.idle => AppColors.textSecondary,
        GpsMode.transfer => AppColors.textSecondary,
        GpsMode.inSpecial => AppColors.accent,
        GpsMode.nearWaypoint => AppColors.warning,
      };

  String _modeLabel(GpsMode mode) => switch (mode) {
        GpsMode.idle => 'INATTIVO',
        GpsMode.transfer => 'TRASFERIMENTO',
        GpsMode.inSpecial => 'IN SPECIALE',
        GpsMode.nearWaypoint => 'WAYPOINT VICINO',
      };

  @override
  Widget build(BuildContext context) {
    final gps = ref.watch(gpsServiceProvider);
    final pos = gps.lastPosition;
    final isRecording = gps.isRecording;

    final eventAsync = widget.eventId != null
        ? ref.watch(eventStreamProvider(widget.eventId!))
        : null;
    final event = eventAsync?.valueOrNull;
    final startEnabled = event?.startEnabled ?? true;
    final canStart = widget.eventId == null || startEnabled;

    // Withdrawal check
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final Set<String> withdrawnIds = widget.eventId != null
        ? ref
                .watch(withdrawalsStreamProvider(widget.eventId!))
                .valueOrNull ??
            {}
        : {};
    final isWithdrawn =
        authUser != null && withdrawnIds.contains(authUser.uid);

    // Auto-follow: move map whenever position updates during recording
    ref.listen(gpsServiceProvider, (prev, next) {
      if (!mounted || !_followMode || !next.isRecording) return;
      final p = next.lastPosition;
      if (p == null) return;
      final latLng = LatLng(p.latitude, p.longitude);
      _programmaticMove = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _followMode) {
          _mapController.move(latLng, _mapZoom);
        }
      });
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: isRecording
            ? _buildActiveTracking(gps, pos, event)
            : _buildPreStart(gps, pos, canStart, isWithdrawn),
      ),
    );
  }

  // ── Pre-start view ──────────────────────────────────────────────────────────

  Widget _buildPreStart(
      GpsService gps, dynamic pos, bool canStart, bool isWithdrawn) {
    if (isWithdrawn) {
      return Column(
        children: [
          _TopBar(eventId: widget.eventId, elapsed: null, isRecording: false),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flag, color: AppColors.error, size: 64),
                    const SizedBox(height: 24),
                    const Text(
                      'Sei ritirato da questa gara',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Il tuo ritiro è stato registrato.\nNon è possibile riprendere la gara.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _TopBar(
          eventId: widget.eventId,
          elapsed: null,
          isRecording: false,
        ),
        if (!canStart)
          _WaitingBanner(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ModeBadge(
                    color: _modeColor(gps.mode),
                    label: _modeLabel(gps.mode)),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: canStart ? _toggleRecording : null,
                  child: _BigButton(isRecording: false, enabled: canStart),
                ),
                const SizedBox(height: 48),
                if (pos != null)
                  _GpsInfoRow(pos: pos)
                else
                  const Text('In attesa del segnale GPS...',
                      style:
                          TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Active tracking view ────────────────────────────────────────────────────

  Widget _buildActiveTracking(GpsService gps, dynamic pos, EventModel? event) {
    final curPos = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(44.0, 11.0);
    final modeColor = _modeColor(gps.mode);
    final lastPassage =
        gps.passages.isNotEmpty ? gps.passages.last : null;

    return Column(
      children: [
        // Top bar
        _TopBar(
          eventId: widget.eventId,
          elapsed: _elapsed,
          isRecording: true,
        ),

        // Mode banner
        _ModeBanner(color: modeColor, label: _modeLabel(gps.mode)),

        // Live map
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: curPos,
                  initialZoom: _mapZoom,
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && !_programmaticMove) {
                      if (_followMode) {
                        setState(() => _followMode = false);
                      }
                    }
                    _programmaticMove = false;
                    _mapZoom = camera.zoom;
                  },
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
                  // Pilot's recorded track
                  if (gps.localTrack.length >= 2)
                    PolylineLayer(polylines: [
                      Polyline(
                        points: gps.localTrack,
                        color: AppColors.accent,
                        strokeWidth: 4.0,
                      ),
                    ]),
                  // PS start/end markers from event specials
                  if (event != null && event.speciali.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (int i = 0; i < event.speciali.length; i++) ...[
                          _psMarker(
                            LatLng(event.speciali[i].waypointInizio.lat,
                                event.speciali[i].waypointInizio.lng),
                            'PS${i + 1}',
                            event.speciali[i].color,
                            true,
                          ),
                          _psMarker(
                            LatLng(event.speciali[i].waypointFine.lat,
                                event.speciali[i].waypointFine.lng),
                            'PS${i + 1}',
                            event.speciali[i].color,
                            false,
                          ),
                        ],
                      ],
                    ),
                  // Fuel point marker
                  if (event?.fuelPoint != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(event!.fuelPoint!.lat,
                            event.fuelPoint!.lng),
                        width: 40,
                        height: 48,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.yellow.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.orange, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.yellow
                                        .withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.local_gas_station,
                                  size: 16, color: Colors.white),
                            ),
                            Container(
                                width: 2,
                                height: 8,
                                color: Colors.orange
                                    .withValues(alpha: 0.7)),
                          ],
                        ),
                      ),
                    ]),
                  // Accuracy circle
                  if (pos != null)
                    CircleLayer(circles: [
                      CircleMarker(
                        point: curPos,
                        radius: pos.accuracy.clamp(5.0, 500.0),
                        useRadiusInMeter: true,
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderColor:
                            AppColors.accent.withValues(alpha: 0.4),
                        borderStrokeWidth: 1,
                      ),
                    ]),
                  // Remaining waypoints (control points hidden)
                  MarkerLayer(
                    markers: gps.remainingWaypoints
                        .where(
                            (wp) => wp.type != WaypointType.intermedio)
                        .map((wp) {
                      final isNear = gps.mode == GpsMode.nearWaypoint;
                      return Marker(
                        point: LatLng(wp.lat, wp.lng),
                        width: 32,
                        height: 38,
                        child: _WaypointPin(
                          color: isNear
                              ? AppColors.warning
                              : AppColors.textSecondary,
                          icon: _waypointIcon(wp.type),
                        ),
                      );
                    }).toList(),
                  ),
                  // Current position: bearing arrow
                  if (pos != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: curPos,
                        width: 36,
                        height: 36,
                        child: Transform.rotate(
                          angle: _calcBearing(gps.localTrack),
                          child: Icon(
                            Icons.navigation,
                            color: AppColors.accent,
                            size: 32,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
                ],
              ),

              // Re-center FAB
              if (!_followMode)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    onPressed: _recenter,
                    backgroundColor: AppColors.cardBackground,
                    foregroundColor: AppColors.accent,
                    elevation: 4,
                    child: const Icon(Icons.my_location, size: 20),
                  ),
                ),
            ],
          ),
        ),

        // Stats strip
        Container(
          color: AppColors.cardBackground,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(
                icon: Icons.speed,
                label: 'VEL',
                value: pos != null
                    ? '${(pos.speed * 3.6).clamp(0, 300).toStringAsFixed(0)} km/h'
                    : '—',
                color: AppColors.accent,
              ),
              _vDivider(),
              _StatCell(
                icon: Icons.route,
                label: 'DIST',
                value: gps.totalDistanceKm >= 1
                    ? '${gps.totalDistanceKm.toStringAsFixed(1)} km'
                    : '${(gps.totalDistanceKm * 1000).toStringAsFixed(0)} m',
                color: AppColors.textPrimary,
              ),
              _vDivider(),
              _StatCell(
                icon: Icons.timer,
                label: 'TEMPO',
                value: LocationUtils.formatDuration(_elapsed),
                color: AppColors.accent,
              ),
              _vDivider(),
              _StatCell(
                icon: Icons.gps_fixed,
                label: 'PREC',
                value: pos != null
                    ? '±${pos.accuracy.toStringAsFixed(0)}m'
                    : '—',
                color: pos != null && pos.accuracy < 10
                    ? AppColors.success
                    : pos != null && pos.accuracy < 30
                        ? AppColors.warning
                        : AppColors.error,
              ),
            ],
          ),
        ),

        // Current special entry info
        if (gps.currentSpecialNome != null)
          Container(
            color: AppColors.accent.withValues(alpha: 0.08),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.timer, color: AppColors.accent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'IN SPECIALE: ${gps.currentSpecialNome}',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (lastPassage != null)
          Container(
            color: AppColors.background,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lastPassage.waypoint.nome,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  LocationUtils.formatTimestamp(lastPassage.timestamp),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${gps.passages.length} WP',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        // Action buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          color: AppColors.cardBackground,
          child: Row(
            children: [
              // FINE GARA button — abilitato solo quando tutti i waypoint sono passati
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: Tooltip(
                    message: gps.remainingWaypoints.isEmpty
                        ? ''
                        : 'Completa tutte le speciali prima di terminare',
                    child: ElevatedButton.icon(
                      onPressed: gps.remainingWaypoints.isEmpty
                          ? _toggleRecording
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: gps.remainingWaypoints.isEmpty
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        side: BorderSide(
                          color: gps.remainingWaypoints.isEmpty
                              ? AppColors.border
                              : AppColors.border.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.flag_circle_outlined, size: 20),
                      label: const Text('FINE GARA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // RITIRO button
              Expanded(
                flex: 3,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (ctx, child) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: child,
                  ),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _confirmWithdrawal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.flag, size: 20),
                      label: const Text('RITIRO',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
      width: 1, height: 32, color: AppColors.border.withValues(alpha: 0.5));

  IconData _waypointIcon(WaypointType type) => switch (type) {
        WaypointType.inizio => Icons.play_circle_outline,
        WaypointType.fine => Icons.stop_circle_outlined,
        WaypointType.intermedio => Icons.radio_button_unchecked,
      };
}

// ── Shared sub-widgets ─────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final String? eventId;
  final Duration? elapsed;
  final bool isRecording;

  const _TopBar(
      {required this.eventId,
      required this.elapsed,
      required this.isRecording});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eventId != null)
                  ref.watch(eventProvider(eventId!)).when(
                        data: (ev) => Text(
                          ev?.nome ?? 'Evento',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        loading: () => const Text('...',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        error: (e, s) => const Text('Evento',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      )
                else
                  const Text('Nessun evento',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                if (elapsed != null && isRecording)
                  Text(
                    LocationUtils.formatDuration(elapsed!),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          if (isRecording)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  const Text('REC',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty, color: AppColors.warning, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'In attesa del via dell\'organizzatore',
              style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final Color color;
  final String label;
  const _ModeBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ModeBanner extends StatelessWidget {
  final Color color;
  final String label;
  const _ModeBanner({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsInfoRow extends StatelessWidget {
  final dynamic pos;
  const _GpsInfoRow({required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _GpsInfoItem(label: 'LAT', value: pos.latitude.toStringAsFixed(5)),
          _GpsInfoItem(label: 'LNG', value: pos.longitude.toStringAsFixed(5)),
          _GpsInfoItem(
              label: 'PREC',
              value: '±${pos.accuracy.toStringAsFixed(0)}m'),
          _GpsInfoItem(
              label: 'VEL',
              value: '${(pos.speed * 3.6).toStringAsFixed(0)} km/h'),
        ],
      ),
    );
  }
}

class _GpsInfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _GpsInfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCell(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _WaypointPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _WaypointPin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(icon, color: color, size: 12),
        ),
        Container(
          width: 2,
          height: 6,
          color: color.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final bool isRecording;
  final bool enabled;
  const _BigButton({required this.isRecording, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final activeColor = enabled ? AppColors.accent : AppColors.textSecondary;
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isRecording ? activeColor : AppColors.cardBackground,
        border: Border.all(
          color: isRecording ? AppColors.accentDark : activeColor,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: activeColor.withValues(alpha: isRecording ? 0.5 : 0.3),
            blurRadius: isRecording ? 32 : 16,
            spreadRadius: isRecording ? 8 : 4,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isRecording ? Icons.stop : Icons.play_arrow,
            color: isRecording ? Colors.white : activeColor,
            size: 72,
          ),
          Text(
            isRecording ? 'STOP' : 'START',
            style: TextStyle(
              color: isRecording ? Colors.white : activeColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
