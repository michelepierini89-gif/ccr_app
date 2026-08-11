import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/providers/track_appearance_provider.dart';
import '../../../core/services/battery_setup_service.dart';
import '../../../core/services/diagnostic_logger.dart';
import '../../../core/services/gnss_status_service.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/imu_fusion_service.dart';
import '../../../core/services/voice_alert_service.dart';
import '../../../core/services/track_appearance_service.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_error_handler.dart';
import '../../../core/utils/heading_display_utils.dart';
import '../../../core/utils/location_utils.dart';
import '../../../core/utils/time_format_utils.dart';
import '../../map/danger_marker_icon.dart';
import '../../map/widgets/speed_zone_layer.dart';
import '../../map/widgets/track_layer.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  int _notificationUpdateTicks = 0;
  static const _foregroundNotificationChannel = MethodChannel('ccr/notification');
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _markerController;
  late AnimationController _dangerBlinkController;
  LatLng? _displayPos;
  LatLng? _fromPos;
  LatLng? _targetPos;

  // Posizione/heading da ImuFusionService, aggiornati a ~50Hz.
  // Usati SOLO per la freccia/posizione di display e la rotazione mappa
  // in modalità HEADING — mai per waypoint detection o timing PS.
  LatLng? _imuPosition;
  double _imuHeading = 0.0;

  late final MapController _mapController;
  late final Stream<Position> _gpsStream;
  bool _followMode = true;
  double _mapZoom = 15.0;
  bool _programmaticMove = false;

  List<LatLng> _eventTrackPoints = [];
  bool _eventTrackLoaded = false;
  bool _headingMode = false;

  bool _batteryOptOk = true;
  bool _locationAlwaysOk = true;

  StreamSubscription<String>? _recoverySub;
  String? _recoveryMessage;
  Timer? _recoveryTimer;

  StreamSubscription<String>? _fuelPointSub;
  String? _fuelPointMessage;
  Timer? _fuelPointTimer;

  StreamSubscription<String>? _dangerPassedSub;

  DateTime? _raceDeadline;
  bool _isTimeExpired = false;
  bool _showingTimeoutDialog = false;

  // Catturato in initState — MAI leggere provider via `ref` dentro
  // dispose(): in questa versione di Riverpod il ConsumerStatefulElement
  // marca `ref` invalido prima che State.dispose() giri, e un ref.read()
  // lì dentro lancia "Cannot use ref after the widget was disposed"
  // interrompendo il resto di dispose() (AnimationController mai fermati).
  late final ImuFusionService _imuService;
  late final DiagnosticLogger _diagLogger;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imuService = ref.read(imuFusionServiceProvider);
    _diagLogger = ref.read(diagnosticLoggerProvider);
    _mapController = MapController();
    _gpsStream = ref.read(gpsServiceProvider).positionStream;
    // Blocco C: l'avvio/stop del monitoraggio GNSS è gestito da GpsService
    // in startRecording()/stopRecording() — GnssStatus non riceve comunque
    // aggiornamenti satellite senza una richiesta di posizione attiva, che
    // in questa app parte solo con la registrazione GPS.
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
    _imuService.addListener(_onImuUpdate);
    _dangerPassedSub =
        ref.read(gpsServiceProvider).dangerPassedStream.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _loadEventTrack();
      await _refreshPrepChecklist();
    });
  }

  /// Ricontrolla lo stato batteria/posizione (Parte 2A) — richiamato
  /// all'avvio e ogni volta che l'app torna in foreground, così la
  /// checklist "Preparazione gara" si aggiorna da sola dopo che il pilota
  /// ha sistemato le impostazioni e torna indietro.
  Future<void> _refreshPrepChecklist() async {
    final batteryOk = await BatterySetupService.isIgnoringBatteryOptimizations();
    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    setState(() {
      _batteryOptOk = batteryOk;
      _locationAlwaysOk = permission == LocationPermission.always;
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _notificationUpdateTicks = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final gps = ref.read(gpsServiceProvider);
      if (!gps.isRecording) return;

      // Parte 5: aggiorna il testo della notifica persistente ogni 30s —
      // il pilota può verificare dalla lock screen che la registrazione è
      // viva senza aprire l'app.
      _notificationUpdateTicks++;
      if (_notificationUpdateTicks >= 30) {
        _notificationUpdateTicks = 0;
        unawaited(_updateForegroundNotification(gps));
      }

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

  /// Parte 5: "CCR — registrazione attiva · N punti · HH:MM:SS", N = fix
  /// GPS accettati in questa sessione, orario = ultimo fix accettato.
  /// No-op silenzioso su web/iOS o se il canale nativo non risponde — mai
  /// deve interrompere la registrazione.
  Future<void> _updateForegroundNotification(GpsService gps) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final count = gps.fullTrackSamples.length;
    final lastFix = gps.lastAcceptedFixTime;
    final timeStr =
        lastFix != null ? DateFormat('HH:mm:ss').format(lastFix) : '--:--:--';
    try {
      await _foregroundNotificationChannel.invokeMethod(
        'updateForegroundNotification',
        {'text': 'CCR — registrazione attiva · $count punti · $timeStr'},
      );
    } catch (_) {}
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

  Future<void> _confirmSkipSpecial(GpsService gps) async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          '⏭ Salta speciale',
          style: TextStyle(color: Colors.orange, fontSize: 17),
        ),
        content: const Text(
          'Stai per saltare la prossima speciale non completata.\n\n'
          'Verrà applicata una penalità pari al tempo peggiore '
          'registrato dagli altri piloti su quella PS + 30 minuti.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANNULLA',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700),
            child: const Text('CONTINUA',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Conferma definitiva',
          style: TextStyle(color: AppColors.error, fontSize: 17),
        ),
        content: const Text(
          'Sei sicuro? La penalità non può essere rimossa '
          'dopo la conferma.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANNULLA',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('SALTA E PENALIZZA',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    await gps.skipCurrentSpecial();
  }

  Future<void> _triggerTimeoutWithdrawal() async {
    final gps = ref.read(gpsServiceProvider);
    final user = ref.read(authStateProvider).valueOrNull;
    final eid = widget.eventId ?? gps.activeEventId;
    final partialTrack = List.of(gps.localTrack);
    final fullSamples = gps.fullTrackSamples;
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
        if (fullSamples.isNotEmpty) {
          await ref
              .read(firestoreServiceProvider)
              .saveFullPilotTrack(eid, user.uid, fullSamples);
        }
      } catch (e) {
        _diagLogger.logTrackSaveError('timeout', e);
        try {
          await ref
              .read(firestoreServiceProvider)
              .flagTrackSaveError(eid, user.uid, e.toString());
        } catch (_) {}
      }
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

  void _onImuUpdate() {
    if (_imuService.fusedPosition == null || !mounted) return;
    _diagLogger.logImuHeading(
        _imuService.displayHeadingDeg, ref.read(gpsServiceProvider).bearingDeg);
    setState(() {
      _imuPosition = _imuService.fusedPosition;
      // displayHeadingDeg: bussola grezza + low-pass leggero, per la
      // rotazione mappa/freccia — fusedHeadingDeg (filtro complementare)
      // resta usato solo internamente da ImuFusionService per il dead
      // reckoning della posizione.
      _imuHeading = _imuService.displayHeadingDeg;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().ignore();
    _imuService.removeListener(_onImuUpdate);
    _elapsedTimer?.cancel();
    _recoverySub?.cancel();
    _recoveryTimer?.cancel();
    _fuelPointSub?.cancel();
    _fuelPointTimer?.cancel();
    _dangerPassedSub?.cancel();
    _pulseController.dispose();
    _markerController.dispose();
    _dangerBlinkController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Log diagnostico di sessione (Parte 4): il ciclo di vita dell'app è
    // il segnale più utile per diagnosticare un GPS che si ferma in
    // background. `paused` è anche l'approssimazione più vicina a "schermo
    // spento" disponibile senza hook nativi dedicati.
    _diagLogger.logLifecycle(state.name);
    if (state == AppLifecycleState.resumed) {
      _refreshPrepChecklist();
    }
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
      if (event?.activeTrackUrl == null || !mounted) return;
      final bytes = await StorageService().downloadTrack(event!.activeTrackUrl!);
      final content = utf8.decode(bytes);
      final pts = event.activeTrackUrl!.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
      if (mounted) setState(() => _eventTrackPoints = pts);
    } catch (_) {}
  }

  Marker _psMarker(LatLng point, String label, Color color, bool isStart,
          {double offsetY = 0}) =>
      Marker(
        point: point,
        width: 60,
        height: 30,
        rotate: true,
        child: Transform.translate(
          offset: Offset(0, offsetY),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isStart ? Icons.play_arrow : Icons.stop,
                    color: Colors.white, size: 18),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );

  /// Marker inizio/fine di tutte le speciali, con offset verticale alternato
  /// quando due punti sono geograficamente vicini abbastanza da
  /// sovrapporsi a schermo (entro ~50px all'attuale livello di zoom) — le
  /// dimensioni maggiori (Fix 8) altrimenti farebbero sovrapporre due
  /// marker di speciali consecutive ravvicinate.
  List<Marker> _buildPsMarkers(EventModel event) {
    final metersPerPixel =
        156543.03392 * cos(curLatForScale * pi / 180) / pow(2, _mapZoom);
    final thresholdMeters = metersPerPixel * 50;
    final points = <LatLng>[];
    final markers = <Marker>[];
    for (final s in event.activeSpeciali) {
      if (s.annullata) continue;
      for (final entry in [
        (s.waypointInizio.latLng, true),
        (s.waypointFine.latLng, false),
      ]) {
        final (point, isStart) = entry;
        var offsetY = 0.0;
        for (final prev in points) {
          if (_haversineMeters(point, prev) < thresholdMeters) {
            offsetY = points.length.isEven ? -16.0 : 16.0;
            break;
          }
        }
        points.add(point);
        markers.add(_psMarker(
            point, 'PS${s.ordine + 1}', s.color, isStart,
            offsetY: offsetY));
      }
    }
    return markers;
  }

  double get curLatForScale =>
      ref.read(gpsServiceProvider).lastPosition?.latitude ?? 44.0;

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return 2 * r * asin(sqrt(x));
  }

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
      // FIX 6: chiude eventuali PS ancora aperte (fine non rilevata) prima
      // di bloccare le scritture — nessun effetto se tutte erano già chiuse
      // regolarmente.
      await gps.closeAllOpenSpecialsForFineGara();
      if (!mounted) return;
      final finTrack = List.of(gps.localTrack); // capture before stop clears it
      final finFullSamples = gps.fullTrackSamples;
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
          if (finFullSamples.isNotEmpty) {
            await ref
                .read(firestoreServiceProvider)
                .saveFullPilotTrack(finEventId, finUserId, finFullSamples);
          }
        } catch (e) {
          _diagLogger.logTrackSaveError('fine_gara', e);
          try {
            await ref
                .read(firestoreServiceProvider)
                .flagTrackSaveError(finEventId, finUserId, e.toString());
          } catch (_) {}
        }
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
        for (final s in event.activeSpeciali) {
          waypoints.add(s.waypointInizio);
          waypoints.addAll(s.controlPoints);
          waypoints.add(s.waypointFine);
        }
      }
      await gps.startRecording(
        eventId: widget.eventId!,
        userId: user.uid,
        waypoints: waypoints,
        specials: event?.activeSpeciali ?? [],
        fuelPoints:
            event?.activeFuelPoint != null ? [event!.activeFuelPoint!] : [],
        dangerPoints: event?.activeDangerPoints ?? [],
        speedZones: event?.activeSpeedZones ?? [],
        referenceTrack: _eventTrackPoints,
        // Percorso alternativo, Parte 5 — la variante ATTIVA in questo
        // preciso momento (START), persistita sul tracking del pilota:
        // eventuali cambi successivi dell'admin non la toccheranno più.
        routeVariantId: event?.activeRouteId ?? 'A',
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
    final fullSamples = gps.fullTrackSamples;
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
        if (fullSamples.isNotEmpty) {
          await ref
              .read(firestoreServiceProvider)
              .saveFullPilotTrack(eventId, user.uid, fullSamples);
        }
      } catch (e) {
        _diagLogger.logTrackSaveError('ritiro', e);
        try {
          await ref
              .read(firestoreServiceProvider)
              .flagTrackSaveError(eventId, user.uid, e.toString());
        } catch (_) {}
      }
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

  String _modeLabel(GpsMode mode, GpsService gps) {
    if (mode == GpsMode.nearWaypoint) {
      final label = gps.nearestWaypointLabel;
      if (label != null) {
        final suffix = label.startsWith('Fine') ? 'vicina' : 'vicino';
        return '$label $suffix';
      }
      return 'WAYPOINT VICINO';
    }
    return switch (mode) {
      GpsMode.idle => 'INATTIVO',
      GpsMode.transfer => 'TRASFERIMENTO',
      GpsMode.inSpecial => 'IN SPECIALE',
      GpsMode.nearWaypoint => 'WAYPOINT VICINO',
    };
  }

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
      body = _buildPreStart(gps, pos, canStart, effectiveEventId, event);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }

  // ── Pre-start view ──────────────────────────────────────────────────────────

  Widget _buildPreStart(
      GpsService gps, dynamic pos, bool canStart,
      [String? effectiveEventId, EventModel? event]) {
    // Calcola se la squadra del pilota è sotto il minimo richiesto dall'evento.
    // Il calcolo avviene SOLO qui (pre-avvio): quando parte la registrazione
    // _buildActiveTracking viene chiamato e questo metodo — con i ref.watch —
    // smette di essere invocato, azzerando automaticamente le subscription.
    final myReg = effectiveEventId != null
        ? ref.watch(myRegistrationStreamProvider(effectiveEventId)).valueOrNull
        : null;
    final mySquadraId = myReg?.squadraId;
    int approvedTeamCount = 0;
    bool isUnderSized = false;
    if (event != null &&
        mySquadraId != null &&
        myReg?.stato == RegistrationStatus.approvato) {
      final allRegsAsync =
          ref.watch(registrationsProvider(effectiveEventId!));
      if (allRegsAsync.hasValue) {
        approvedTeamCount = allRegsAsync.requireValue
            .where((r) =>
                r.squadraId == mySquadraId &&
                r.stato == RegistrationStatus.approvato)
            .length;
        isUnderSized = approvedTeamCount < event.minSquadra;
      }
    }

    return Column(
      children: [
        _TopBar(
          eventId: effectiveEventId,
          elapsed: null,
          isRecording: false,
          onSettingsTap: _showTrackAppearanceSheet,
        ),
        if (!canStart)
          _WaitingBanner(),
        // Percorso alternativo, Parte 4 — se il percorso è cambiato nelle
        // ultime 24h, avviso a ricontrollare la mappa prima di partire
        // (indipendentemente da quale variante sia ora attiva: il punto è
        // che è CAMBIATA di recente, non quale sia il verso del cambio).
        if (event != null &&
            event.lastRouteChangeAt != null &&
            DateTime.now().difference(event.lastRouteChangeAt!) <
                const Duration(hours: 24))
          _RouteChangedRecentlyBanner(
              label: event.activeLabel, changedAt: event.lastRouteChangeAt!),
        if (isUnderSized)
          _UnderSizedTeamBanner(
            present: approvedTeamCount,
            minRequired: event!.minSquadra,
          ),
        // Banner informativo non bloccante: il pulsante START sopra resta
        // sempre attivo a prescindere dal segnale GPS, questo è solo un
        // avviso che il chip sta ancora acquisendo.
        if (pos == null) const _GpsAcquiringBanner(),
        // Blocco C3: qualità GNSS reale (satelliti usati/visibili), così il
        // pilota sa se conviene attendere prima di partire.
        const _GnssQualityBanner(),
        _PrepChecklistCard(
          locationAlwaysOk: _locationAlwaysOk,
          batteryOptOk: _batteryOptOk,
          gpsSignalOk: pos != null,
          onFixLocation: _fixLocationPermission,
          onFixBattery: _fixBatteryOptimization,
          onGpsSignalTap: _showGpsSignalTip,
          onVoiceTest: _playVoiceTest,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ModeBadge(
                        color: _modeColor(gps.mode),
                        label: _modeLabel(gps.mode, gps)),
                    const SizedBox(height: 48),
                    GestureDetector(
                      onTap: canStart ? () => _onStartTapped(gps) : null,
                      child: _BigButton(isRecording: false, enabled: canStart),
                    ),
                    const SizedBox(height: 48),
                    if (pos != null) _GpsInfoRow(pos: pos),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Preparazione gara (Parte 2) ──────────────────────────────────────────

  Future<void> _fixLocationPermission() async {
    await Geolocator.openAppSettings();
    // Il pilota torna dalle impostazioni con l'app in resumed:
    // didChangeAppLifecycleState richiama già _refreshPrepChecklist().
  }

  Future<void> _fixBatteryOptimization() async {
    await BatterySetupService.requestIgnoreBatteryOptimizations();
    await _refreshPrepChecklist();
    if (!mounted) return;
    final manufacturer = await BatterySetupService.manufacturer();
    final instructions = BatterySetupService.instructionsFor(manufacturer);
    // Sui produttori con risparmio energetico proprietario l'esenzione
    // standard non basta: mostra sempre le istruzioni specifiche, anche se
    // il dialog di sistema è stato accettato.
    if (instructions == null || !mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$manufacturer: passaggi extra necessari',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Su questo produttore l\'esenzione standard da sola spesso '
              'non basta: il sistema ha comunque un risparmio energetico '
              'proprietario che può fermare il GPS.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(instructions,
                style: const TextStyle(
                    color: AppColors.textPrimary, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  await BatterySetupService.openManufacturerBatterySettings();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Apri impostazioni produttore',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _showGpsSignalTip() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Vai all\'aperto, lontano da edifici, per un segnale '
          'GPS migliore'),
      duration: Duration(seconds: 3),
    ));
  }

  Future<void> _playVoiceTest() async {
    final voiceService = ref.read(voiceAlertServiceProvider);
    await voiceService.playTestAnnouncement();
  }

  /// Non blocca mai la partenza: se un requisito non è soddisfatto mostra
  /// un avviso esplicito con conferma, ma il pilota resta sempre libero di
  /// partire comunque.
  Future<void> _onStartTapped(GpsService gps) async {
    final warnings = <String>[];
    if (!_batteryOptOk) {
      warnings.add('L\'ottimizzazione batteria è attiva: la registrazione '
          'potrebbe interrompersi con lo schermo spento.');
    }
    if (!_locationAlwaysOk) {
      warnings.add('Il permesso posizione non è impostato su "Consenti '
          'sempre": il GPS potrebbe fermarsi con l\'app in background.');
    }
    if (warnings.isEmpty) {
      _toggleRecording();
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('⚠ Attenzione',
            style: TextStyle(color: AppColors.warning, fontSize: 17)),
        content: Text(
          '${warnings.join('\n\n')}\n\nVuoi partire lo stesso?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANNULLA',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('PARTI LO STESSO',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (proceed == true) _toggleRecording();
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
                  if (hasGpsData)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RaceResultScreen(eventId: eventId),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('VEDI RISULTATO TRACCIA',
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
                            body: SafeArea(
                              bottom: true,
                              child: TimingScreen(
                                  eventId: eventId, adminView: false),
                            ),
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
                    height: 56,
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
                      label: const Text('VEDI RISULTATO TRACCIA',
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
    final trackAppearance = ref.watch(trackAppearanceProvider);

    // Ultima speciale chiusa: mostrata come banner "PS completata: <tempo>"
    // al posto della riga generica di passaggio, finché non si entra nella
    // speciale successiva (gps.currentSpecialNome torna non-null) o per
    // max 30s — qualunque condizione si verifichi prima.
    SpecialEntry? lastCompletedSpecial;
    for (int i = gps.specialEntries.length - 1; i >= 0; i--) {
      if (gps.specialEntries[i].exitTime != null) {
        lastCompletedSpecial = gps.specialEntries[i];
        break;
      }
    }
    final showSpecialCompletedBanner = gps.currentSpecialNome == null &&
        lastCompletedSpecial != null &&
        DateTime.now().difference(lastCompletedSpecial.exitTime!) <=
            const Duration(seconds: 30);

    return StreamBuilder<Position>(
      stream: _gpsStream,
      builder: (context, snap) {
        // Live position from stream; fall back to last known from GpsService.
        // If no fix yet, center on first GPX track point so the pilot can see
        // the route immediately (grey-screen fix for offline use).
        final liveData = snap.data;
        final rawPos = liveData != null
            ? LatLng(liveData.latitude, liveData.longitude)
            : pos != null
                ? LatLng(pos.latitude, pos.longitude)
                : _eventTrackPoints.isNotEmpty
                    ? _eventTrackPoints.first
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

        // Use interpolated position for marker and camera; fall back to raw GPS.
        // _imuPosition (da ImuFusionService, ~50Hz) ha priorità per fluidità
        // del display — usato SOLO qui, mai per waypoint/timing.
        final curPos = _imuPosition ?? _displayPos ?? rawPos;

        // Heading di display: IMU a 50Hz se disponibile, altrimenti bearing GPS.
        final displayHeadingDeg =
            _imuPosition != null ? _imuHeading : gps.bearingDeg;

        // Camera follow and optional map rotation on every stream emission
        if (liveData != null && _followMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_followMode) return;
            _programmaticMove = true;
            _mapController.move(curPos, _mapZoom);
            if (_headingMode) {
              _mapController.rotate(HeadingDisplayUtils.mapRotationDeg(
                  _headingMode, displayHeadingDeg));
            }
          });
        }

        // Fix 6 — calcolo estratto in HeadingDisplayUtils (funzioni pure,
        // testate in isolamento): NORD, la freccia ruota di
        // displayHeadingDeg; HEADING, la mappa è già ruotata e la freccia
        // resta fissa (angolo 0). Mai entrambe contemporaneamente.
        final arrowAngle =
            HeadingDisplayUtils.arrowAngleRad(_headingMode, displayHeadingDeg);
        final hasPos = liveData != null || pos != null;
        // Velocità geometrica (distanza/tempo tra punti GPS accettati),
        // coerente col filtro jump — non position.speed, inaffidabile.
        // L'IMU sovrascrive il display se ha un valore significativo (>0.5km/h),
        // altrimenti si usa la velocità geometrica GPS.
        final imu = ref.watch(imuFusionServiceProvider);
        final speedKmh =
            imu.fusedSpeedKmh > 0.5 ? imu.fusedSpeedKmh : gps.geometricSpeedKmh;
        final accuracy = liveData?.accuracy ?? pos?.accuracy ?? 0.0;

        // FIX 6: seconda via di sblocco FINE GARA, vedi _canFinishNearStart.
        final allSpecialsDone = _allSpecialsCompleted(gps, event);
        final canFinish =
            allSpecialsDone || _canFinishNearStart(gps, curPos, event);
        // Blocco D4: "Fine gara disponibile" — idempotente (dedupe interno
        // a VoiceAlertService), sicuro da chiamare ad ogni rebuild.
        if (allSpecialsDone) {
          ref.read(voiceAlertServiceProvider).announceRaceEndAvailable();
        }

    return Column(
      children: [
        // Top bar
        _TopBar(
          eventId: widget.eventId,
          elapsed: _elapsed,
          isRecording: true,
          onSettingsTap: _showTrackAppearanceSheet,
        ),

        // Countdown strip (visible only when deadline is set)
        if (_raceDeadline != null)
          _CountdownStrip(
            deadline: _raceDeadline!,
            allSpecialsDone: event != null && _allSpecialsCompleted(gps, event),
          ),

        // Mode banner
        _ModeBanner(color: modeColor, label: _modeLabel(gps.mode, gps)),

        // Banner zona a velocità controllata: visibile per tutta la
        // permanenza nella zona, colore verde/rosso in base al limite.
        if (gps.activeSpeedZone != null)
          _SpeedZoneBanner(
              zone: gps.activeSpeedZone!, currentSpeedKmh: speedKmh),

        // Banner non bloccante: nessun fix GPS ancora ricevuto (normale nei
        // primi secondi dopo START). Mappa e controlli restano comunque
        // visibili e utilizzabili sotto questo banner.
        if (!hasPos) const _GpsAcquiringBanner(),

        // Banner GPS in ripristino (riavvio manuale in corso, richiesto dal pilota)
        if (gps.isRestartingGps)
          Container(
            color: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 8),
                Text('⟳ GPS in ripristino...',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        // Nessuna posizione da oltre 30s: il pilota decide se riavviare lo
        // stream GPS, nessuna azione automatica viene presa dall'app.
        else if (gps.isGpsStale)
          _GpsRestoreBanner(onRestart: () => gps.restartGps()),

        // Banner punto ristoro: appare quando il pilota è entro 200m e non
        // l'ha ancora superato (gps.passedFuelPoints persiste anche in background)
        if (event?.activeFuelPoint != null &&
            !gps.passedFuelPoints.contains(event!.activeFuelPoint!.id))
          Builder(builder: (context) {
            final fuel = event.activeFuelPoint!;
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
                  // Event GPX track — colore/larghezza personalizzabili
                  if (_eventTrackPoints.length >= 2)
                    PolylineLayer(polylines: [
                      Polyline(
                        points: _eventTrackPoints,
                        color: trackAppearance.refTrackColor,
                        strokeWidth: trackAppearance.refTrackWidth,
                        borderStrokeWidth: trackAppearance.refTrackWidth * 0.25,
                        borderColor: Color.lerp(
                            trackAppearance.refTrackColor, Colors.black, 0.4)!,
                      ),
                    ]),
                  // Frecce direzionali sulla traccia rossa (verso di percorrenza)
                  if (_eventTrackPoints.length >= 2)
                    TrackDirectionArrowsLayer(trackPoints: _eventTrackPoints),
                  // Zone a velocità controllata: stesso stile della mappa admin —
                  // nessun avviso di violazione qui, il pilota vede solo dove
                  // rallentare, non se l'ha superato (lo scopre in classifica).
                  if (event != null && event.activeSpeedZones.isNotEmpty)
                    SpeedZoneLayer(
                        zones: event.activeSpeedZones,
                        trackPoints: _eventTrackPoints),
                  // Pilot's recorded track — colore/larghezza personalizzabili
                  if (gps.localTrack.length >= 2)
                    PolylineLayer(polylines: [
                      Polyline(
                        points: gps.localTrack,
                        color: trackAppearance.trackColor,
                        strokeWidth: trackAppearance.trackWidth,
                      ),
                    ]),
                  // PS start/end markers from event specials
                  if (event != null && event.activeSpeciali.isNotEmpty)
                    MarkerLayer(markers: _buildPsMarkers(event)),
                  // Fuel point marker
                  if (event?.activeFuelPoint != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(event!.activeFuelPoint!.lat,
                            event.activeFuelPoint!.lng),
                        width: 40,
                        height: 48,
                        rotate: true,
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
                  // Danger points — sempre visibili, DangerMarkerIcon
                  if (event != null && event.activeDangerPoints.isNotEmpty)
                    MarkerLayer(
                      markers: event.activeDangerPoints.map((dp) {
                        return Marker(
                          point: dp.latLng,
                          width: 36,
                          height: 36,
                          rotate: true,
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('⚠ ${dp.comment}'),
                                  backgroundColor: Colors.amber.shade800,
                                ),
                              );
                            },
                            child: const DangerMarkerIcon(),
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
                        rotate: true,
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
                        width: trackAppearance.arrowSize,
                        height: trackAppearance.arrowSize,
                        rotate: _headingMode,
                        child: Transform.rotate(
                          angle: arrowAngle,
                          child: Icon(
                            Icons.navigation,
                            color: trackAppearance.arrowColor,
                            size: trackAppearance.arrowSize * 8 / 9,
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
              // Fix 6 (09/08/2026) — debug overlay SEMPRE visibile (anche in
              // release: gli unici test reali su strada usano l'APK
              // release, non un build debug) con tutti i valori in gioco
              // per la modalità mappa rotante: heading display (quello
              // effettivamente usato per freccia/mappa), bearing GPS
              // grezzo, rotazione applicata alla mappa, angolo applicato
              // alla freccia e la modalità corrente — per diagnosticare sul
              // campo un eventuale disallineamento senza dover riprodurre
              // il problema nel codice.
              Positioned(
                  bottom: 80,
                  left: 8,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'MODE:${_headingMode ? "HEADING" : "NORD"} '
                          'GY:${imu.fusedHeadingDeg.toStringAsFixed(0)}° '
                          'GPS:${gps.bearingDeg.toStringAsFixed(0)}° '
                          'DISP:${displayHeadingDeg.toStringAsFixed(0)}°',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                        Text(
                          'MAP:${HeadingDisplayUtils.mapRotationDeg(_headingMode, displayHeadingDeg).toStringAsFixed(0)}° '
                          'ARROW:${(arrowAngle * 180 / pi).toStringAsFixed(0)}° '
                          'V:${imu.fusedSpeedKmh.toStringAsFixed(0)}km/h',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                        StreamBuilder<GnssStatusSnapshot>(
                          stream: ref.read(gnssStatusServiceProvider).stream,
                          initialData:
                              ref.read(gnssStatusServiceProvider).lastSnapshot,
                          builder: (context, snap) {
                            final s = snap.data;
                            if (s == null) return const SizedBox.shrink();
                            return Text(
                              'SAT:${s.satCountLabel} ${s.quality.label}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            );
                          },
                        ),
                      ],
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
        else if (showSpecialCompletedBanner)
          Container(
            color: AppColors.success.withValues(alpha: 0.08),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.timer,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PS completata: ${_formatElapsed(lastCompletedSpecial!.elapsed!)}',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // FINE GARA button — abilitato quando tutte le speciali sono
                  // completate, OPPURE tutte avviate e il pilota è tornato
                  // vicino al punto di partenza (FIX 6, vedi _canFinishNearStart)
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 56,
                      child: Tooltip(
                        message: _isTimeExpired
                            ? 'Tempo scaduto — ritiro automatico in corso'
                            : canFinish
                                ? (allSpecialsDone
                                    ? ''
                                    : 'PS non chiuse correttamente: '
                                        'verranno segnalate all\'admin')
                                : 'Completa tutte le speciali prima di terminare',
                        child: ElevatedButton.icon(
                          onPressed: !_isTimeExpired && canFinish
                              ? _toggleRecording
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cardBackground,
                            foregroundColor: canFinish
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            side: BorderSide(
                              color: canFinish
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
              // SALTA PS — visibile solo se ci sono speciali non ancora saltate/completate
              if (event != null &&
                  event.activeSpeciali.any((s) => !s.annullata) &&
                  !allSpecialsDone) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSkipSpecial(gps),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade300,
                      side: BorderSide(color: Colors.orange.shade700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text(
                      'SALTA SPECIALE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8),
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
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
          return _formatElapsed(e.elapsed!);
        }
      }
    }
    return LocationUtils.formatTimestamp(passage.timestamp);
  }

  static String _formatElapsed(Duration d) => TimeFormatUtils.formatRaceTime(d);

  static const _trackColorOptions = [
    Colors.blue,
    Colors.cyan,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Color(0xFFFF00FF), // magenta
    Colors.white,
    Colors.red,
    Colors.black,
  ];

  static const _arrowColorOptions = [
    AppColors.accent, // rosso (default)
    Colors.white,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.black,
  ];

  static const _refTrackColorOptions = [
    Colors.red, // default
    Colors.orange,
    Color(0xFFFF00FF), // magenta
    Colors.white,
    Colors.black,
  ];

  Widget _colorSwatchRow(
      List<Color> options, Color selected, ValueChanged<Color> onSelect) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.map((c) {
        final isSelected = c.toARGB32() == selected.toARGB32();
        // Il nero si confonde col background scuro dell'app: bordo bianco
        // sottile sempre visibile per renderlo distinguibile e selezionabile.
        final isBlack = c.toARGB32() == Colors.black.toARGB32();
        return GestureDetector(
          onTap: () => onSelect(c),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? AppColors.accent
                    : isBlack
                        ? Colors.white
                        : AppColors.border,
                width: isSelected ? 3 : (isBlack ? 1.5 : 1),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _showTrackAppearanceSheet() async {
    final current = ref.read(trackAppearanceProvider);
    double width = current.trackWidth;
    Color color = current.trackColor;
    Color arrowColor = current.arrowColor;
    double arrowSize = current.arrowSize;
    Color refTrackColor = current.refTrackColor;
    double refTrackWidth = current.refTrackWidth;

    final voiceService = ref.read(voiceAlertServiceProvider);
    var voiceSettings = voiceService.settings;

    final gps = ref.read(gpsServiceProvider);
    var useRawGps = gps.useRawLocationManager;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheetState) {
          return SafeArea(
            top: false,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aspetto traccia',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text('Larghezza: ${width.toStringAsFixed(1)}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                Container(
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    height: width,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(width / 2),
                    ),
                  ),
                ),
                Slider(
                  value: width,
                  min: TrackAppearanceService.minWidth,
                  max: TrackAppearanceService.maxWidth,
                  divisions: ((TrackAppearanceService.maxWidth -
                              TrackAppearanceService.minWidth) /
                          0.5)
                      .round(),
                  activeColor: AppColors.accent,
                  label: width.toStringAsFixed(1),
                  onChanged: (v) => setSheetState(() => width = v),
                ),
                const SizedBox(height: 8),
                const Text('Colore',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                _colorSwatchRow(_trackColorOptions, color,
                    (c) => setSheetState(() => color = c)),

                const SizedBox(height: 24),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                const Text('Freccia pilota',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('Dimensione: ${arrowSize.toStringAsFixed(0)}px',
                    style: const TextStyle(color: AppColors.textSecondary)),
                Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(Icons.navigation,
                      color: arrowColor, size: arrowSize),
                ),
                Slider(
                  value: arrowSize,
                  min: TrackAppearanceService.minArrowSize,
                  max: TrackAppearanceService.maxArrowSize,
                  divisions: (TrackAppearanceService.maxArrowSize -
                          TrackAppearanceService.minArrowSize)
                      .round(),
                  activeColor: AppColors.accent,
                  label: arrowSize.toStringAsFixed(0),
                  onChanged: (v) => setSheetState(() => arrowSize = v),
                ),
                const SizedBox(height: 8),
                const Text('Colore freccia',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                _colorSwatchRow(_arrowColorOptions, arrowColor,
                    (c) => setSheetState(() => arrowColor = c)),

                const SizedBox(height: 24),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                const Text('Traccia da seguire',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('Larghezza: ${refTrackWidth.toStringAsFixed(1)}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                Container(
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    height: refTrackWidth,
                    decoration: BoxDecoration(
                      color: refTrackColor,
                      borderRadius: BorderRadius.circular(refTrackWidth / 2),
                    ),
                  ),
                ),
                Slider(
                  value: refTrackWidth,
                  min: TrackAppearanceService.minRefTrackWidth,
                  max: TrackAppearanceService.maxRefTrackWidth,
                  divisions: ((TrackAppearanceService.maxRefTrackWidth -
                              TrackAppearanceService.minRefTrackWidth) /
                          0.5)
                      .round(),
                  activeColor: AppColors.accent,
                  label: refTrackWidth.toStringAsFixed(1),
                  onChanged: (v) => setSheetState(() => refTrackWidth = v),
                ),
                const SizedBox(height: 8),
                const Text('Colore traccia di riferimento',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                _colorSwatchRow(_refTrackColorOptions, refTrackColor,
                    (c) => setSheetState(() => refTrackColor = c)),

                const SizedBox(height: 24),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                const Text('Avvisi vocali',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.accent,
                  title: const Text('Attivi',
                      style: TextStyle(color: AppColors.textPrimary)),
                  value: voiceSettings.enabled,
                  onChanged: (v) => setSheetState(
                      () => voiceSettings = voiceSettings.copyWith(enabled: v)),
                ),
                if (voiceSettings.enabled) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: AppColors.accent,
                    title: const Text('Pericoli',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    value: voiceSettings.dangerEnabled,
                    onChanged: (v) => setSheetState(() =>
                        voiceSettings = voiceSettings.copyWith(dangerEnabled: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: AppColors.accent,
                    title: const Text('Prove speciali',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    value: voiceSettings.specialsEnabled,
                    onChanged: (v) => setSheetState(() => voiceSettings =
                        voiceSettings.copyWith(specialsEnabled: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: AppColors.accent,
                    title: const Text('Zone velocità',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    value: voiceSettings.speedZonesEnabled,
                    onChanged: (v) => setSheetState(() => voiceSettings =
                        voiceSettings.copyWith(speedZonesEnabled: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: AppColors.accent,
                    title: const Text('Checkpoint',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    value: voiceSettings.checkpointsEnabled,
                    onChanged: (v) => setSheetState(() => voiceSettings =
                        voiceSettings.copyWith(checkpointsEnabled: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: AppColors.accent,
                    title: const Text('Punto ristoro',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    value: voiceSettings.fuelPointEnabled,
                    onChanged: (v) => setSheetState(() => voiceSettings =
                        voiceSettings.copyWith(fuelPointEnabled: v)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Velocità di lettura: ${voiceSettings.speechRate.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  Slider(
                    value: voiceSettings.speechRate,
                    min: VoiceAlertService.minSpeechRate,
                    max: VoiceAlertService.maxSpeechRate,
                    divisions: 12,
                    activeColor: AppColors.accent,
                    label: voiceSettings.speechRate.toStringAsFixed(2),
                    onChanged: (v) => setSheetState(
                        () => voiceSettings = voiceSettings.copyWith(speechRate: v)),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Applica subito la velocità corrente per un test
                        // rappresentativo, senza attendere "Applica".
                        await voiceService.updateSettings(voiceSettings);
                        await voiceService.playTestAnnouncement();
                      },
                      icon: const Icon(Icons.volume_up, size: 16),
                      label: const Text('Prova audio'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                const Text('Avanzate',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.accent,
                  title: const Text('Provider GPS grezzo (sperimentale)',
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: const Text(
                      'Bypassa la fusione di Google. Può ridurre il '
                      'ritardo della posizione.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  value: useRawGps,
                  onChanged: (v) {
                    setSheetState(() => useRawGps = v);
                    // Parte 3: applica subito riavviando lo stream se la
                    // registrazione è attiva, altrimenti si applica al
                    // prossimo avvio (già persistito da setUseRawLocationManager).
                    unawaited(gps.setUseRawLocationManager(v));
                  },
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final notifier = ref.read(trackAppearanceProvider.notifier);
                      await notifier.setWidth(width);
                      await notifier.setColor(color);
                      await notifier.setArrowColor(arrowColor);
                      await notifier.setArrowSize(arrowSize);
                      await notifier.setRefTrackColor(refTrackColor);
                      await notifier.setRefTrackWidth(refTrackWidth);
                      await voiceService.updateSettings(voiceSettings);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Applica',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
              ),
            ),
            ),
          );
        });
      },
    );
  }

  bool _allSpecialsCompleted(GpsService gps, EventModel? event) {
    if (event == null || event.activeSpeciali.isEmpty) {
      return gps.remainingWaypoints.isEmpty;
    }
    return gps.specialEntries.where((e) => e.exitTime != null).length >=
        event.activeSpeciali.length;
  }

  static const double _kFineGaraNearStartMeters = 100.0;

  /// Tutte le speciali sono state almeno AVVIATE (non necessariamente
  /// chiuse correttamente) — condizione meno stringente di
  /// [_allSpecialsCompleted], usata per la seconda via di sblocco di FINE
  /// GARA quando il pilota è tornato al punto di partenza.
  bool _allSpecialsStarted(GpsService gps, EventModel? event) {
    final activeSpecials =
        event?.activeSpeciali.where((s) => !s.annullata) ?? const Iterable.empty();
    if (activeSpecials.isEmpty) return false;
    final startedIds = gps.specialEntries.map((e) => e.specialeId).toSet();
    return activeSpecials.every((s) => startedIds.contains(s.id));
  }

  bool _isNearStartPoint(LatLng curPos, EventModel? event) {
    if (_eventTrackPoints.isNotEmpty) {
      final d = LocationUtils.haversineDistance(
          curPos.latitude,
          curPos.longitude,
          _eventTrackPoints.first.latitude,
          _eventTrackPoints.first.longitude);
      if (d <= _kFineGaraNearStartMeters) return true;
    }
    if (event != null && event.activeSpeciali.isNotEmpty) {
      final ps1Start = event.activeSpeciali.first.waypointInizio;
      final d = LocationUtils.haversineDistance(
          curPos.latitude, curPos.longitude, ps1Start.lat, ps1Start.lng);
      if (d <= _kFineGaraNearStartMeters) return true;
    }
    return false;
  }

  /// Seconda via di sblocco FINE GARA (FIX 6): tutte le PS avviate (anche
  /// se non tutte chiuse per problemi GPS) E il pilota è tornato entro
  /// [_kFineGaraNearStartMeters] dal punto di partenza dell'evento o
  /// dall'inizio della PS1. Le PS ancora aperte vengono chiuse al momento
  /// della pressione (vedi [_toggleRecording]) con lo stesso algoritmo di
  /// recovery del FIX 5, segnalate all'admin per la verifica.
  bool _canFinishNearStart(GpsService gps, LatLng curPos, EventModel? event) =>
      _allSpecialsStarted(gps, event) && _isNearStartPoint(curPos, event);

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
  final VoidCallback? onSettingsTap;

  const _TopBar(
      {required this.eventId,
      required this.elapsed,
      required this.isRecording,
      this.onSettingsTap});

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
          if (onSettingsTap != null)
            IconButton(
              onPressed: onSettingsTap,
              icon: const Icon(Icons.settings, color: AppColors.textSecondary),
              tooltip: 'Aspetto traccia',
            ),
        ],
      ),
    );
  }
}

/// Banner informativo non bloccante: il chip GPS sta ancora acquisendo il
/// primo fix (normale nei primi 30-60s dall'avvio, specialmente al chiuso).
/// Non sostituisce mai la schermata — START/navigazione restano sempre
/// utilizzabili a prescindere da questo stato.
class _GpsAcquiringBanner extends StatelessWidget {
  const _GpsAcquiringBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.textSecondary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.satellite_alt_outlined,
              color: AppColors.textSecondary, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Acquisizione GPS in corso...',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Qualità GNSS reale (Blocco C3): satelliti usati/visibili + metrica
/// sintetica, calcolati da GnssStatus nativo (non dal solo `accuracy`
/// dichiarato dal chip, ottimistico su device economici). Nessun banner
/// se il canale non ha ancora emesso nulla (es. iOS/web, o Android in
/// attesa del primo aggiornamento satelliti).
class _GnssQualityBanner extends ConsumerWidget {
  const _GnssQualityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(gnssStatusServiceProvider);
    return StreamBuilder<GnssStatusSnapshot>(
      stream: service.stream,
      initialData: service.lastSnapshot,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox.shrink();
        final color = switch (s.quality) {
          GnssQuality.eccellente || GnssQuality.buona => AppColors.success,
          GnssQuality.scarsa => Colors.orange,
          GnssQuality.critica => AppColors.error,
        };
        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.satellite_alt, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GNSS ${s.quality.label} — ${s.satCountLabel} satelliti',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Checklist "Preparazione gara" (Parte 2D): mostrata sopra il pulsante
/// START, ogni riga in stato ⚠ è toccabile e porta direttamente all'azione
/// che la risolve. Non blocca mai la partenza — solo informa.
class _PrepChecklistCard extends StatelessWidget {
  final bool locationAlwaysOk;
  final bool batteryOptOk;
  final bool gpsSignalOk;
  final VoidCallback onFixLocation;
  final VoidCallback onFixBattery;
  final VoidCallback onGpsSignalTap;
  final VoidCallback onVoiceTest;

  const _PrepChecklistCard({
    required this.locationAlwaysOk,
    required this.batteryOptOk,
    required this.gpsSignalOk,
    required this.onFixLocation,
    required this.onFixBattery,
    required this.onGpsSignalTap,
    required this.onVoiceTest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preparazione gara',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _PrepRow(
            label: 'Permesso posizione sempre attiva',
            ok: locationAlwaysOk,
            onTap: locationAlwaysOk ? null : onFixLocation,
          ),
          _PrepRow(
            label: 'Ottimizzazione batteria disattivata',
            ok: batteryOptOk,
            onTap: batteryOptOk ? null : onFixBattery,
          ),
          _PrepRow(
            label: 'Segnale GPS',
            ok: gpsSignalOk,
            onTap: gpsSignalOk ? null : onGpsSignalTap,
          ),
          _PrepRow(
            label: 'Avvisi vocali (prova audio)',
            ok: null,
            onTap: onVoiceTest,
          ),
        ],
      ),
    );
  }
}

class _PrepRow extends StatelessWidget {
  /// null = riga solo azione (nessuno stato ok/⚠), es. "prova audio".
  final bool? ok;
  final String label;
  final VoidCallback? onTap;

  const _PrepRow({required this.label, required this.ok, this.onTap});

  @override
  Widget build(BuildContext context) {
    final Widget icon = ok == null
        ? const Icon(Icons.play_circle_outline,
            color: AppColors.accent, size: 18)
        : Icon(ok! ? Icons.check_circle : Icons.warning_amber_rounded,
            color: ok! ? AppColors.success : AppColors.warning, size: 18);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner con pulsante manuale "Ripristina GPS": visibile solo quando non
/// arriva nessuna posizione (valida o no) da oltre 30s. Nessun riavvio
/// automatico — il pilota decide se e quando toccare il pulsante.
class _GpsRestoreBanner extends StatelessWidget {
  const _GpsRestoreBanner({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.gps_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Nessuna posizione GPS da oltre 30s',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRestart,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Ripristina GPS',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
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

class _RouteChangedRecentlyBanner extends StatelessWidget {
  final String label;
  final DateTime changedAt;
  const _RouteChangedRecentlyBanner(
      {required this.label, required this.changedAt});

  @override
  Widget build(BuildContext context) {
    final t = '${changedAt.hour.toString().padLeft(2, '0')}:'
        '${changedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Il percorso è stato cambiato alle $t — è ora in vigore '
              '"$label". Ricontrolla la mappa prima di partire.',
              style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnderSizedTeamBanner extends StatelessWidget {
  final int present;
  final int minRequired;
  const _UnderSizedTeamBanner(
      {required this.present, required this.minRequired});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.group_off, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Squadra sotto-numerata: $present/$minRequired piloti — '
              'verrà applicata una penalità in classifica',
              style: const TextStyle(
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

/// Banner zona a velocità controllata: mostra il limite e la velocità
/// attuale del pilota, verde se la rispetta o rosso se la supera. Visibile
/// per tutta la durata della permanenza nella zona (driven da
/// [GpsService.activeSpeedZone], non scompare finché non si esce).
class _SpeedZoneBanner extends StatelessWidget {
  final SpeedZoneModel zone;
  final double currentSpeedKmh;
  const _SpeedZoneBanner({required this.zone, required this.currentSpeedKmh});

  @override
  Widget build(BuildContext context) {
    final overLimit = currentSpeedKmh > zone.maxSpeedKmh;
    final speedColor = overLimit ? AppColors.error : AppColors.success;
    return Container(
      width: double.infinity,
      color: speedColor.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.speed, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Zona ${zone.nome} — limite ${zone.maxSpeedKmh.toStringAsFixed(0)} km/h',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${currentSpeedKmh.clamp(0, 300).toStringAsFixed(0)} km/h',
            style: TextStyle(
              color: speedColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
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
              'ATTENZIONE: $comment tra ~${distanceMeters.round()}m',
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
              'PERICOLO: $comment',
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
