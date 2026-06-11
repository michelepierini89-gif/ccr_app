import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_error_handler.dart';
import '../../../core/utils/location_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../../timing/screens/timing_screen.dart';
import '../providers/pilot_provider.dart';
import 'race_result_screen.dart';

class GpsRecordingScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const GpsRecordingScreen({super.key, this.eventId});

  @override
  ConsumerState<GpsRecordingScreen> createState() =>
      _GpsRecordingScreenState();
}

class _GpsRecordingScreenState extends ConsumerState<GpsRecordingScreen>
    with TickerProviderStateMixin {
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _markerController;
  late AnimationController _dangerBlinkController;
  LatLng? _displayPos;
  LatLng? _fromPos;
  LatLng? _targetPos;

  late final MapController _mapController;
  late final Stream<Position> _gpsStream;
  bool _followMode = true;
  double _mapZoom = 15.0;
  bool _programmaticMove = false;

  List<LatLng> _eventTrackPoints = [];
  bool _eventTrackLoaded = false;
  bool _headingMode = false;

  StreamSubscription<String>? _recoverySub;
  String? _recoveryMessage;
  Timer? _recoveryTimer;

  StreamSubscription<String>? _fuelPointSub;
  String? _fuelPointMessage;
  Timer? _fuelPointTimer;

  DateTime? _raceDeadline;
  bool _isTimeExpired = false;
  bool _showingTimeoutDialog = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _gpsStream = ref.read(gpsServiceProvider).positionStream;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _markerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_onMarkerAnimTick);
    _dangerBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    WakelockPlus.enable().ignore();
    _startElapsedTimer();
    _recoverySub = ref.read(gpsServiceProvider).recoveryStream.listen((msg) {
      if (!mounted) return;
      setState(() => _recoveryMessage = msg);
      _recoveryTimer?.cancel();
      _recoveryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _recoveryMessage = null);
      });
    });
    _fuelPointSub = ref.read(gpsServiceProvider).fuelPointStream.listen((msg) {
      if (!mounted) return;
      setState(() => _fuelPointMessage = msg);
      _fuelPointTimer?.cancel();
      _fuelPointTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _fuelPointMessage = null);
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEventTrack());
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final gps = ref.read(gpsServiceProvider);
      if (!gps.isRecording) return;

      if (gps.recordingStart != null) {
        // Timeout check before setState so flag is visible in next build
        if (_raceDeadline != null && !_isTimeExpired && !_showingTimeoutDialog) {
          if (DateTime.now().isAfter(_raceDeadline!)) {
            final eid = widget.eventId ?? gps.activeEventId;
            final ev = eid != null
                ? ref.read(eventStreamProvider(eid)).valueOrNull
                : null;
            if (ev != null && !_allSpecialsCompleted(gps, ev)) {
              _isTimeExpired = true;
              _showingTimeoutDialog = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showTimeoutDialog();
              });
            }
          }
        }
        setState(() {
          _elapsed = DateTime.now().difference(gps.recordingStart!);
        });
      }
    });
  }

  void _computeDeadlineIfNeeded(EventModel event, RegistrationModel? reg) {
    if (_raceDeadline != null || _isTimeExpired) return;
    final teamName = reg?.teamName;
    if (teamName == null || event.startingOrder.isEmpty) return;
    final tl = teamName.toLowerCase().trim();
    final slot = event.startingOrder.cast<StartingSlot?>().firstWhere(
          (s) => s!.teamName.toLowerCase().trim() == tl,
          orElse: () => null,
        );
    if (slot == null) return;
    _raceDeadline =
        slot.startTime.add(Duration(minutes: event.maxRaceTimeMinutes));
  }

  Future<void> _showTimeoutDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          '⏱ Tempo massimo scaduto',
          style: TextStyle(color: AppColors.warning, fontSize: 17),
        ),
        content: const Text(
          'La tua squadra è stata automaticamente ritirata perché '
          'il tempo massimo di gara è scaduto.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _triggerTimeoutWithdrawal();
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('OK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerTimeoutWithdrawal() async {
    final gps = ref.read(gpsServiceProvider);
    final user = ref.read(authStateProvider).valueOrNull;
    final eid = widget.eventId ?? gps.activeEventId;
    final partialTrack = List.of(gps.localTrack);
    gps.blockFurtherWrites();
    await gps.stopRecording();
    if (mounted) setState(() => _elapsed = Duration.zero);
    if (user != null && eid != null) {
      try {
        await ref
            .read(firestoreServiceProvider)
            .recordWithdrawal(eid, user.uid,
                partialTrack: partialTrack, retiredReason: 'timeout');
        await ref.read(firestoreServiceProvider).setRaceStatus(
            eid, user.uid, 'retired',
            retiredReason: 'timeout');
        if (partialTrack.isNotEmpty) {
          await ref
              .read(firestoreServiceProvider)
              .savePilotTrack(eid, user.uid, partialTrack);
        }
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('⏱ Tempo scaduto — ritiro automatico registrato.'),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 5),
      ));
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable().ignore();
    _elapsedTimer?.cancel();
    _recoverySub?.cancel();
    _recoveryTimer?.cancel();
    _fuelPointSub?.cancel();
    _fuelPointTimer?.cancel();
    _pulseController.dispose();
    _markerController.dispose();
    _dangerBlinkController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onMarkerAnimTick() {
    if (_fromPos != null && _targetPos != null && mounted) {
      final t = _markerController.value;
      setState(() {
        _displayPos = LatLng(
          _fromPos!.latitude + (_targetPos!.latitude - _fromPos!.latitude) * t,
          _fromPos!.longitude +
              (_targetPos!.longitude - _fromPos!.longitude) * t,
        );
      });
    }
  }

  Future<void> _loadEventTrack() async {
    final gps = ref.read(gpsServiceProvider);
    final eid = widget.eventId ?? gps.activeEventId;
    if (eid == null || _eventTrackLoaded) return;
    _eventTrackLoaded = true;
    try {
      final event = await ref.read(eventProvider(eid).future);
      if (event?.trackUrl == null || !mounted) return;
      final bytes = await StorageService().downloadTrack(event!.trackUrl!);
      final content = utf8.decode(bytes);
      final pts = event.trackUrl!.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
      if (mounted) setState(() => _eventTrackPoints = pts);
    } catch (_) {}
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
      final finEventId = gps.activeEventId;
      final finUserId = ref.read(authStateProvider).valueOrNull?.uid;
      final finTrack = List.of(gps.localTrack); // capture before stop clears it
      gps.blockFurtherWrites();
      if (finEventId != null && finUserId != null) {
        try {
          await ref
              .read(firestoreServiceProvider)
              .setRaceStatus(finEventId, finUserId, 'finished',
                  finishedAt: DateTime.now());
          if (finTrack.isNotEmpty) {
            await ref
                .read(firestoreServiceProvider)
                .savePilotTrack(finEventId, finUserId, finTrack);
          }
        } catch (_) {}
      }
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
        fuelPoints: event?.fuelPoint != null ? [event!.fuelPoint!] : [],
        dangerPoints: event?.dangerPoints ?? [],
      );
      setState(() => _followMode = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FirebaseErrorHandler.getMessage(e)),
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
    gps.blockFurtherWrites();
    await gps.stopRecording();
    setState(() => _elapsed = Duration.zero);

    if (user != null && eventId != null) {
      try {
        await ref
            .read(firestoreServiceProvider)
            .recordWithdrawal(eventId, user.uid, partialTrack: partialTrack);
        await ref
            .read(firestoreServiceProvider)
            .setRaceStatus(eventId, user.uid, 'retired');
        if (partialTrack.isNotEmpty) {
          await ref
              .read(firestoreServiceProvider)
              .savePilotTrack(eventId, user.uid, partialTrack);
        }
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

    // Usa l'eventId attivo nel GPS se la schermata è aperta senza eventId
    // (es. tab GPS aperto mentre la registrazione gira per un altro evento)
    final effectiveEventId = widget.eventId ?? gps.activeEventId;
    final eventAsync = effectiveEventId != null
        ? ref.watch(eventStreamProvider(effectiveEventId))
        : null;
    final event = eventAsync?.valueOrNull;
    final startEnabled = event?.startEnabled ?? true;
    final canStart = effectiveEventId == null || startEnabled;

    // Withdrawal check
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final Set<String> withdrawnIds = effectiveEventId != null
        ? ref
                .watch(withdrawalsStreamProvider(effectiveEventId))
                .valueOrNull ??
            {}
        : {};
    final isWithdrawn =
        authUser != null && withdrawnIds.contains(authUser.uid);

    // Pilot's own race status from tracking doc
    final myStatusAsync = effectiveEventId != null
        ? ref.watch(myPilotStatusProvider(effectiveEventId))
        : null;
    final myStatusData = myStatusAsync?.valueOrNull;
    final raceStatus = myStatusData?['raceStatus'] as String?;
    final isFinished = raceStatus == 'finished';
    final isRetired = isWithdrawn || raceStatus == 'retired';

    // Race deadline for countdown — lazy, no setState needed (timer already redraws each second)
    if (isRecording && effectiveEventId != null && event != null) {
      final reg = ref
          .watch(myRegistrationStreamProvider(effectiveEventId))
          .valueOrNull;
      _computeDeadlineIfNeeded(event, reg);
    }

    // Determine which screen to show
    Widget body;
    if (isRecording) {
      body = _buildActiveTracking(gps, pos, event);
    } else if (myStatusAsync?.isLoading == true) {
      body = const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    } else if (isFinished) {
      body = _buildRaceDone(
          statusData: myStatusData,
          eventId: effectiveEventId,
          retired: false);
    } else if (isRetired) {
      body = _buildRaceDone(
          statusData: myStatusData,
          eventId: effectiveEventId,
          retired: true);
    } else if (event != null &&
        (event.stato == EventStatus.archiviata ||
            event.data.toMidnight().isBefore(DateTime.now()))) {
      body = _buildRaceOver(
          event: event,
          statusData: myStatusData,
          eventId: effectiveEventId);
    } else {
      body = _buildPreStart(gps, pos, canStart, effectiveEventId);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }

  // ── Pre-start view ──────────────────────────────────────────────────────────

  Widget _buildPreStart(
      GpsService gps, dynamic pos, bool canStart,
      [String? effectiveEventId]) {
    return Column(
      children: [
        _TopBar(
          eventId: effectiveEventId,
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

  // ── Race-done view (finished or retired) ────────────────────────────────────

  Widget _buildRaceDone({
    required Map<String, dynamic>? statusData,
    required String? eventId,
    required bool retired,
  }) {
    final finishedAtTs = statusData?['finishedAt'] as Timestamp?;
    final finishedAt = finishedAtTs?.toDate().toLocal();
    final timeFmt = DateFormat('HH:mm', 'it');

    return Column(
      children: [
        _TopBar(eventId: eventId, elapsed: null, isRecording: false),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  retired ? Icons.flag : Icons.check_circle_rounded,
                  color: retired ? AppColors.error : AppColors.success,
                  size: 72,
                ),
                const SizedBox(height: 16),
                Text(
                  retired ? 'Gara terminata — Ritiro' : 'Gara completata!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: retired ? AppColors.error : AppColors.success,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (finishedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    retired
                        ? 'Ritirato alle ${timeFmt.format(finishedAt)}'
                        : 'Completata alle ${timeFmt.format(finishedAt)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  retired
                      ? 'Il tuo ritiro è stato registrato.\nNon è possibile riprendere la gara.'
                      : 'Il GPS è stato bloccato.\nNon è possibile riattivare la registrazione.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 28),
                if (eventId != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RaceResultScreen(eventId: eventId),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('VEDI LA MIA TRACCIA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => Scaffold(
                            appBar: AppBar(
                                title: const Text('I miei tempi')),
                            backgroundColor: AppColors.background,
                            body: TimingScreen(
                                eventId: eventId, adminView: false),
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.accent
                                .withValues(alpha: 0.6)),
                        foregroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.timer, size: 18),
                      label: const Text('VEDI I MIEI TEMPI',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Race-over view (evento archiviato o passato) ────────────────────────────

  Widget _buildRaceOver({
    required EventModel event,
    required Map<String, dynamic>? statusData,
    required String? eventId,
  }) {
    final dateFmt = DateFormat('dd/MM/yyyy', 'it');
    final pilotTrack = statusData?['pilotTrack'] as List<dynamic>?;
    final hasGpsData = pilotTrack != null && pilotTrack.isNotEmpty;

    return Column(
      children: [
        _TopBar(eventId: eventId, elapsed: null, isRecording: false),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.flag_circle_outlined,
                  color: AppColors.textSecondary,
                  size: 72,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Gara conclusa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Questa gara si è svolta il ${dateFmt.format(event.data)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (hasGpsData && eventId != null)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RaceResultScreen(eventId: eventId),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('VEDI LA MIA TRACCIA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ),
                  )
                else
                  const Text(
                    'Non hai partecipato a questa gara',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Active tracking view ────────────────────────────────────────────────────

  Widget _buildActiveTracking(GpsService gps, dynamic pos, EventModel? event) {
    final modeColor = _modeColor(gps.mode);
    final lastPassage = gps.passages.isNotEmpty ? gps.passages.last : null;

    return StreamBuilder<Position>(
      stream: _gpsStream,
      builder: (context, snap) {
        // Live position from stream; fall back to last known from GpsService
        final liveData = snap.data;
        final rawPos = liveData != null
            ? LatLng(liveData.latitude, liveData.longitude)
            : pos != null
                ? LatLng(pos.latitude, pos.longitude)
                : const LatLng(44.0, 11.0);

        // Start interpolation toward the Kalman-filtered GPS position.
        // Falls back to raw coords only if no valid fix has been accepted yet.
        if (liveData != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final newPos = ref.read(gpsServiceProvider).filteredPosition
                ?? LatLng(liveData.latitude, liveData.longitude);
            if (_targetPos != newPos) {
              _fromPos = _displayPos ?? newPos;
              _targetPos = newPos;
              _markerController.forward(from: 0);
            }
          });
        }

        // Use interpolated position for marker and camera; fall back to raw GPS
        final curPos = _displayPos ?? rawPos;

        // Camera follow and optional map rotation on every stream emission
        if (liveData != null && _followMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_followMode) return;
            _programmaticMove = true;
            _mapController.move(curPos, _mapZoom);
            if (_headingMode) {
              // bearingDeg already in degrees [0,360) — no radians conversion needed
              _mapController.rotate(-gps.bearingDeg);
            }
          });
        }

        // NORD mode: arrow rotates by bearingDeg (converted to radians for Transform.rotate)
        // HEADING mode: map already rotated → arrow fixed pointing up (angle 0)
        // No double-rotation: either the map rotates OR the arrow rotates, never both.
        final arrowAngle = _headingMode ? 0.0 : gps.bearingDeg * pi / 180;
        final hasPos = liveData != null || pos != null;
        // Velocità geometrica (distanza/tempo tra punti GPS accettati),
        // coerente col filtro jump — non position.speed, inaffidabile.
        final speedKmh = gps.geometricSpeedKmh;
        final accuracy = liveData?.accuracy ?? pos?.accuracy ?? 0.0;

    return Column(
      children: [
        // Top bar
        _TopBar(
          eventId: widget.eventId,
          elapsed: _elapsed,
          isRecording: true,
        ),

        // Countdown strip (visible only when deadline is set)
        if (_raceDeadline != null)
          _CountdownStrip(
            deadline: _raceDeadline!,
            allSpecialsDone: event != null && _allSpecialsCompleted(gps, event),
          ),

        // Mode banner
        _ModeBanner(color: modeColor, label: _modeLabel(gps.mode)),

        // Banner punto ristoro: appare quando il pilota è entro 200m e non
        // l'ha ancora superato (gps.passedFuelPoints persiste anche in background)
        if (event?.fuelPoint != null &&
            !gps.passedFuelPoints.contains(event!.fuelPoint!.id))
          Builder(builder: (context) {
            final fuel = event.fuelPoint!;
            final distance = LocationUtils.haversineDistance(
                curPos.latitude, curPos.longitude, fuel.lat, fuel.lng);
            if (distance > 200) return const SizedBox.shrink();
            return _FuelPointBanner(distanceMeters: distance);
          }),

        // Banner punto ristoro raggiunto: mostrato una sola volta al passaggio
        if (_fuelPointMessage != null)
          Container(
            width: double.infinity,
            height: 26,
            color: AppColors.success.withValues(alpha: 0.18),
            alignment: Alignment.center,
            child: Text(
              _fuelPointMessage!,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),

        // Banner avviso punto pericolo (giallo, statico) — entro 150m
        if (gps.warningDangerPoint != null && !gps.isDangerBlinking)
          _DangerWarningBanner(
            comment: gps.warningDangerPoint!.comment,
            distanceMeters: gps.warningDangerDistance ?? 0,
          ),

        // Banner allerta punto pericolo (rosso, lampeggiante) — entro 50m
        if (gps.isDangerBlinking && gps.alertDangerPoint != null)
          AnimatedBuilder(
            animation: _dangerBlinkController,
            builder: (context, _) => Opacity(
              opacity: 0.3 + 0.7 * _dangerBlinkController.value,
              child: _DangerAlertBanner(
                comment: gps.alertDangerPoint!.comment,
              ),
            ),
          ),

        // Thin warning strip: visible only when the last 5+ positions were
        // discarded for poor accuracy (urban canyon, tunnel, etc.).
        if (gps.isAccuracyPoor)
          Container(
            width: double.infinity,
            height: 22,
            color: AppColors.warning.withValues(alpha: 0.15),
            alignment: Alignment.center,
            child: const Text(
              '⚠ Segnale GPS debole',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),

        // Recovery banner: light-blue strip shown for 3 s after a retroactive start
        if (_recoveryMessage != null)
          Container(
            width: double.infinity,
            height: 26,
            color: const Color(0xFF29B6F6).withValues(alpha: 0.18),
            alignment: Alignment.center,
            child: Text(
              _recoveryMessage!,
              style: const TextStyle(
                color: Color(0xFF29B6F6),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),

        // Live map — RepaintBoundary isola la mappa: rivernicia solo quando
        // cambia la posizione GPS, non quando il timer stats scatta ogni secondo
        Expanded(
          child: RepaintBoundary(
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
                  // Pilot's recorded track (blue to distinguish from red GPX event track)
                  if (gps.localTrack.length >= 2)
                    PolylineLayer(polylines: [
                      Polyline(
                        points: gps.localTrack,
                        color: const Color(0xFF2196F3),
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
                  // Danger points — sempre visibili, triangolo giallo ⚠
                  if (event != null && event.dangerPoints.isNotEmpty)
                    MarkerLayer(
                      markers: event.dangerPoints.map((dp) {
                        return Marker(
                          point: dp.latLng,
                          width: 32,
                          height: 32,
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('⚠ ${dp.comment}'),
                                  backgroundColor: Colors.amber.shade800,
                                ),
                              );
                            },
                            child: const Icon(Icons.warning_amber_rounded,
                                color: Colors.amber, size: 32),
                          ),
                        );
                      }).toList(),
                    ),
                  // Accuracy circle
                  if (hasPos)
                    CircleLayer(circles: [
                      CircleMarker(
                        point: curPos,
                        radius: accuracy.clamp(5.0, 500.0),
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
                  // Current position: bearing arrow — NON const, si aggiorna ad ogni emit
                  // rotate: _headingMode annulla la rotazione ambiente della mappa
                  // (MobileLayerTransformer ruota l'intero layer di camera.rotationRad);
                  // senza questo, in modalità HEADING la freccia ereditava -bearingDeg
                  // dalla mappa oltre alla propria rotazione → doppia rotazione variabile.
                  if (hasPos)
                    MarkerLayer(markers: [
                      Marker(
                        point: curPos,
                        width: 36,
                        height: 36,
                        rotate: _headingMode,
                        child: Transform.rotate(
                          angle: arrowAngle,
                          child: Icon(
                            Icons.navigation,
                            color: AppColors.accent,
                            size: 32,
                          ),
                        ),
                      ),
                    ]),
                ],
              ),

              // Heading mode toggle (bottom-left)
              Positioned(
                left: 12,
                bottom: 12,
                child: Material(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(8),
                  elevation: 4,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _headingMode = !_headingMode;
                        if (!_headingMode) _mapController.rotate(0);
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _headingMode ? Icons.navigation : Icons.explore,
                        color: _headingMode
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
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
              // Scale bar
              Positioned(
                right: 12,
                bottom: _followMode ? 12 : 60,
                child: _MapScaleBar(lat: curPos.latitude, zoom: _mapZoom),
              ),
              // Bordo schermo rosso lampeggiante quando un punto pericolo è in allerta (<50m)
              if (gps.isDangerBlinking)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _dangerBlinkController,
                      builder: (context, _) => Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.error.withValues(
                                alpha:
                                    0.3 + 0.7 * _dangerBlinkController.value),
                            width: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Debug overlay: bearing, rotazione mappa e velocità (solo debug)
              if (kDebugMode)
                Positioned(
                  bottom: 80,
                  left: 8,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'B:${gps.bearingDeg.toStringAsFixed(0)}° '
                      'M:${(_headingMode ? -gps.bearingDeg : 0.0).toStringAsFixed(0)}° '
                      'V:${speedKmh.toStringAsFixed(0)}km/h',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
          ), // RepaintBoundary
        ),

        // Stats strip — RepaintBoundary isola le statistiche dalla mappa
        RepaintBoundary(child: Container(
          color: AppColors.cardBackground,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(
                icon: Icons.speed,
                label: 'VEL',
                value: hasPos
                    ? '${speedKmh.clamp(0, 300).toStringAsFixed(0)} km/h'
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
                value: !hasPos
                    ? '—'
                    : gps.isAccuracyPoor
                        ? '±??'
                        : '±${accuracy.toStringAsFixed(0)}m',
                color: !hasPos
                    ? AppColors.textSecondary
                    : gps.isAccuracyPoor
                        ? AppColors.warning
                        : accuracy < 10
                            ? AppColors.success
                            : accuracy < 30
                                ? AppColors.warning
                                : AppColors.error,
              ),
            ],
          ),
        )), // Container + RepaintBoundary

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
                  _passageTimeDisplay(gps, lastPassage),
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
              // FINE GARA button — abilitato quando tutte le speciali sono completate
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 56,
                  child: Tooltip(
                    message: _isTimeExpired
                        ? 'Tempo scaduto — ritiro automatico in corso'
                        : _allSpecialsCompleted(gps, event)
                            ? ''
                            : 'Completa tutte le speciali prima di terminare',
                    child: ElevatedButton.icon(
                      onPressed: !_isTimeExpired && _allSpecialsCompleted(gps, event)
                          ? _toggleRecording
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: _allSpecialsCompleted(gps, event)
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        side: BorderSide(
                          color: _allSpecialsCompleted(gps, event)
                              ? AppColors.border
                              : AppColors.border.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.flag_circle_outlined, size: 20),
                      label: const Text(
                        'FINE GARA',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1),
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // RITIRO button — flex:2 garantisce ≥126dp su 360dp (minWidth 110 soddisfatto)
              Expanded(
                flex: 2,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (ctx, child) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: child,
                  ),
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isTimeExpired ? null : _confirmWithdrawal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.flag, size: 20),
                      label: const Text(
                        'RITIRO',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
      }, // StreamBuilder builder
    );   // StreamBuilder
  }

  String _passageTimeDisplay(GpsService gps, WaypointPassage passage) {
    if (passage.waypoint.type == WaypointType.fine) {
      for (int i = gps.specialEntries.length - 1; i >= 0; i--) {
        final e = gps.specialEntries[i];
        if (e.exitTime != null && e.elapsed != null) {
          final d = e.elapsed!;
          final m = d.inMinutes;
          final s = d.inSeconds % 60;
          final tenths = (d.inMilliseconds % 1000) ~/ 100;
          return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$tenths';
        }
      }
    }
    return LocationUtils.formatTimestamp(passage.timestamp);
  }

  bool _allSpecialsCompleted(GpsService gps, EventModel? event) {
    if (event == null || event.speciali.isEmpty) {
      return gps.remainingWaypoints.isEmpty;
    }
    return gps.specialEntries.where((e) => e.exitTime != null).length >=
        event.speciali.length;
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

class _FuelPointBanner extends StatelessWidget {
  final double distanceMeters;
  const _FuelPointBanner({required this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_gas_station,
              color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Text(
            'Punto ristoro tra ${distanceMeters.round()} m',
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerWarningBanner extends StatelessWidget {
  final String comment;
  final double distanceMeters;
  const _DangerWarningBanner(
      {required this.comment, required this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '⚠ ATTENZIONE: $comment tra ~${distanceMeters.round()}m',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerAlertBanner extends StatelessWidget {
  final String comment;
  const _DangerAlertBanner({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.25),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '⚠ PERICOLO: $comment',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

class _MapScaleBar extends StatelessWidget {
  final double lat;
  final double zoom;
  const _MapScaleBar({required this.lat, required this.zoom});

  static double _niceScale(double meters) {
    const steps = [
      1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0,
      1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0,
    ];
    for (final s in steps) {
      if (s >= meters * 0.7) return s;
    }
    return 50000.0;
  }

  @override
  Widget build(BuildContext context) {
    final metersPerPixel =
        156543.03392 * cos(lat * pi / 180) / pow(2.0, zoom);
    const targetWidth = 80.0;
    final scaleMeters = _niceScale(metersPerPixel * targetWidth);
    final barWidthPx = (scaleMeters / metersPerPixel).clamp(20.0, 160.0);
    final label = scaleMeters >= 1000
        ? '${(scaleMeters / 1000).round()} km'
        : '${scaleMeters.round()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1.1,
              )),
          const SizedBox(height: 2),
          SizedBox(
            width: barWidthPx,
            child: Row(
              children: [
                Container(width: 1.5, height: 6, color: Colors.white),
                Expanded(child: Container(height: 2, color: Colors.white)),
                Container(width: 1.5, height: 6, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
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

// ── Countdown strip ─────────────────────────────────────────────────────────

class _CountdownStrip extends StatefulWidget {
  final DateTime deadline;
  final bool allSpecialsDone;

  const _CountdownStrip({
    required this.deadline,
    required this.allSpecialsDone,
  });

  @override
  State<_CountdownStrip> createState() => _CountdownStripState();
}

class _CountdownStripState extends State<_CountdownStrip> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _blink = false;

  @override
  void initState() {
    super.initState();
    _tick(null);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer? _) {
    if (!mounted) return;
    final now = DateTime.now();
    final rem = widget.deadline.difference(now);
    setState(() {
      _remaining = rem.isNegative ? Duration.zero : rem;
      _blink = now.second % 2 == 0;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = _remaining.inSeconds;
    final expired = totalSec == 0;
    final critical = totalSec <= 5 * 60 && !expired;
    final warning = totalSec <= 10 * 60 && !critical;
    final done = widget.allSpecialsDone;

    Color stripColor;
    Color textColor;
    if (done) {
      stripColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green;
    } else if (expired) {
      stripColor = AppColors.error.withValues(alpha: 0.18);
      textColor = AppColors.error;
    } else if (critical) {
      stripColor = AppColors.error.withValues(alpha: 0.15);
      textColor = AppColors.error;
    } else if (warning) {
      stripColor = AppColors.warning.withValues(alpha: 0.13);
      textColor = AppColors.warning;
    } else {
      stripColor = AppColors.accent.withValues(alpha: 0.10);
      textColor = AppColors.accent;
    }

    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = h > 0 ? '$h:$m:$s' : '$m:$s';

    final visible = !critical || _blink || done;

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        height: 26,
        color: stripColor,
        alignment: Alignment.center,
        child: Text(
          done
              ? '✓ Speciali completate'
              : expired
                  ? '⏱ Tempo scaduto'
                  : '⏱ Tempo rimasto: $timeStr',
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
