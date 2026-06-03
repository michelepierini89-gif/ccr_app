import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pilot_provider.dart';

class GpsRecordingScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const GpsRecordingScreen({super.key, this.eventId});

  @override
  ConsumerState<GpsRecordingScreen> createState() =>
      _GpsRecordingScreenState();
}

class _GpsRecordingScreenState
    extends ConsumerState<GpsRecordingScreen>
    with SingleTickerProviderStateMixin {
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startElapsedTimer();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final gps = ref.read(gpsServiceProvider);
      if (gps.isRecording && gps.recordingStart != null) {
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
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Utente non autenticato'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (widget.eventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun evento selezionato. Vai alla lista gare.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      // Load event to extract waypoints (inizio, fine e control points)
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
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Color get _modeColor {
    final gps = ref.read(gpsServiceProvider);
    switch (gps.mode) {
      case GpsMode.idle:
        return AppColors.textSecondary;
      case GpsMode.transfer:
        return AppColors.textSecondary;
      case GpsMode.inSpecial:
        return AppColors.accent;
      case GpsMode.nearWaypoint:
        return AppColors.warning;
    }
  }

  String get _modeLabel {
    final gps = ref.read(gpsServiceProvider);
    switch (gps.mode) {
      case GpsMode.idle:
        return 'INATTIVO';
      case GpsMode.transfer:
        return 'TRASFERIMENTO';
      case GpsMode.inSpecial:
        return 'IN SPECIALE';
      case GpsMode.nearWaypoint:
        return 'WAYPOINT VICINO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final gps = ref.watch(gpsServiceProvider);
    final pos = gps.lastPosition;
    final isRecording = gps.isRecording;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: event name + elapsed
            Container(
              color: AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.eventId != null)
                          ref.watch(eventProvider(widget.eventId!)).when(
                                data: (ev) => Text(
                                  ev?.nome ?? 'Evento',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                loading: () => const Text('...',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                                error: (e, _) => const Text('Evento',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              )
                        else
                          const Text(
                            'Nessun evento',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        if (isRecording) ...[
                          Text(
                            LocationUtils.formatDuration(_elapsed),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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
                                color: AppColors.accent,
                                shape: BoxShape.circle),
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
            ),

            // Center: big START/STOP button
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _modeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _modeColor),
                      ),
                      child: Text(
                        _modeLabel,
                        style: TextStyle(
                          color: _modeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Big circular button
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: isRecording
                          ? AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) => Transform.scale(
                                scale: _pulseAnimation.value,
                                child: child,
                              ),
                              child: _BigButton(
                                  isRecording: true),
                            )
                          : _BigButton(isRecording: false),
                    ),

                    const SizedBox(height: 48),

                    // GPS info row
                    if (pos != null) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceAround,
                          children: [
                            _GpsInfoItem(
                              label: 'LAT',
                              value: pos.latitude.toStringAsFixed(5),
                            ),
                            _GpsInfoItem(
                              label: 'LNG',
                              value: pos.longitude.toStringAsFixed(5),
                            ),
                            _GpsInfoItem(
                              label: 'PREC',
                              value: '±${pos.accuracy.toStringAsFixed(0)}m',
                            ),
                            _GpsInfoItem(
                              label: 'VEL',
                              value:
                                  '${((pos.speed * 3.6)).toStringAsFixed(0)} km/h',
                            ),
                          ],
                        ),
                      ),
                    ] else if (isRecording) ...[
                      const Text(
                        'In attesa del segnale GPS...',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Waypoints list
            if (gps.passages.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.border),
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: const Row(
                  children: [
                    Icon(Icons.flag, color: AppColors.accent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Waypoints passati',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: AppColors.cardBackground,
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: gps.passages.length,
                  itemBuilder: (ctx, i) {
                    final p =
                        gps.passages[gps.passages.length - 1 - i];
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          vertical: 3, horizontal: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.success, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.waypoint.nome,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13),
                            ),
                          ),
                          Text(
                            LocationUtils.formatTimestamp(p.timestamp),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final bool isRecording;
  const _BigButton({required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isRecording
            ? AppColors.accent
            : AppColors.cardBackground,
        border: Border.all(
          color: isRecording ? AppColors.accentDark : AppColors.accent,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: isRecording ? 0.5 : 0.3),
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
            color: isRecording ? Colors.white : AppColors.accent,
            size: 72,
          ),
          Text(
            isRecording ? 'STOP' : 'START',
            style: TextStyle(
              color: isRecording ? Colors.white : AppColors.accent,
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

class _GpsInfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _GpsInfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
