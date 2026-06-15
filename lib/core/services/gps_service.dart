import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/waypoint_model.dart';
import '../models/gps_point_model.dart';
import '../models/special_model.dart';
import '../constants/app_constants.dart';
import '../services/waypoint_detector.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue_service.dart';
import '../utils/kalman_filter.dart';

enum GpsMode { idle, transfer, inSpecial, nearWaypoint }

class WaypointPassage {
  final WaypointModel waypoint;
  final DateTime timestamp;
  WaypointPassage({required this.waypoint, required this.timestamp});
}

class SpecialEntry {
  final String specialeId;
  final String specialeNome;
  final DateTime entryTime;
  final DateTime? exitTime;
  final bool recoveredStart;

  const SpecialEntry({
    required this.specialeId,
    required this.specialeNome,
    required this.entryTime,
    this.exitTime,
    this.recoveredStart = false,
  });

  Duration? get elapsed => exitTime?.difference(entryTime);

  SpecialEntry withExit(DateTime t) => SpecialEntry(
        specialeId: specialeId,
        specialeNome: specialeNome,
        entryTime: entryTime,
        exitTime: t,
        recoveredStart: recoveredStart,
      );
}

class GpsService extends ChangeNotifier {
  // STEP 1 — Filtro accuracy adattivo.
  // Soglia normale 15m; soglia di fallback 40m se nessun punto è stato
  // accettato da più di [kAccuracyFallbackSeconds] secondi, per evitare
  // un freeze totale quando il segnale resta scadente a lungo.
  static const double kAccuracyThresholdNormal = 15.0;
  static const double kAccuracyThresholdFallback = 40.0;
  static const int kAccuracyFallbackSeconds = 4;

  // STEP 2 — Filtro jump geometrico: secondo livello dopo il Kalman 4D.
  // Scarta punti che implicherebbero una velocità superiore a 200 km/h,
  // a meno che [kMaxConsecutiveJumps] punti consecutivi siano già stati
  // scartati — in tal caso il GPS ha probabilmente "teletrasportato"
  // (tunnel, perdita di segnale) e il punto viene accettato resettando
  // il filtro Kalman.
  static const double kMaxSpeedFilterKmh = 200.0;
  static const int kMaxConsecutiveJumps = 4;

  // STEP 4 — Spostamento minimo per aggiornare polyline/distanza, per
  // evitare il pattern "a ventaglio" generato dal rumore GPS da fermo.
  static const double kMinDisplacementMeters = 3.0;

  // Bearing: sotto questa velocità geometrica il bearing resta congelato
  // (evita jitter della freccia da fermo); sopra, smoothing esponenziale.
  static const double kMinBearingSpeedKmh = 3.0;
  static const double kBearingSmoothingAlpha = 0.4;

  // Distanza minima (m) tra due fix consecutivi richiesta da Geolocator,
  // fissa per tutte le modalità — 0 causava l'accettazione di ogni
  // scatter GPS come punto valido (pattern a ventaglio).
  static const int kDistanceFilterMeters = 2;

  final FirestoreService _firestoreService;
  final OfflineQueueService _offlineQueue;

  GpsService(this._firestoreService, this._offlineQueue);

  final StreamController<Position> _posStreamCtrl =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _posStreamCtrl.stream;

  bool _isRecording = false;
  bool _writesBlocked = false;
  GpsMode _mode = GpsMode.idle;
  Position? _lastPosition;
  String? _activeEventId;
  String? _activeUserId;
  List<WaypointModel> _waypoints = [];
  List<SpecialModel> _specials = [];
  final Map<String, String> _inizioToSpecial = {};
  final Map<String, String> _fineToSpecial = {};
  final Set<String> _passedWaypoints = {};
  List<WaypointModel> _fuelPoints = [];
  final Set<String> _passedFuelPoints = {};
  List<DangerPointModel> _dangerPoints = [];
  // Punti pericolo "attivi" (entro 150m): rimossi quando la distanza torna > 100m.
  final Set<String> _alertedDangerPoints = {};
  DangerPointModel? _warningDangerPoint;
  double? _warningDangerDistance;
  DangerPointModel? _alertDangerPoint;
  double? _alertDangerDistance;
  bool _dangerBlinking = false;
  final List<WaypointPassage> _passages = [];
  String? _currentSpecialId;
  String? _currentSpecialNome;
  final List<SpecialEntry> _specialEntries = [];
  DateTime? _recordingStart;
  StreamSubscription<Position>? _positionSub;
  double _totalDistanceKm = 0.0;

  // Display/distance track: only points that moved >= kMinDisplacementMeters
  // from the previous one (STEP 4). Used for the pilot polyline and for
  // the cumulative distance — avoids accumulating GPS jitter as distance.
  final List<LatLng> _trackPoints = [];

  // Recovery track: every accepted (post-Kalman) point with its timestamp,
  // used only for the special-start retroactive lookback.
  final List<LatLng> _recoveryTrack = [];
  final List<DateTime> _recoveryTimestamps = [];

  // Kalman 4D filter (kinematic: position + velocity) + accuracy filtering
  final GpsKalmanFilter _kalmanFilter =
      GpsKalmanFilter(sigmaAccel: GpsKalmanFilter.kSigmaAccelMotorcycle);
  int _consecutiveDiscarded = 0;
  LatLng? _filteredPosition;

  // Geometric jump filter state (raw points, before Kalman)
  LatLng? _lastAcceptedRawPos;
  DateTime? _lastAcceptedTs;
  int _jumpCount = 0;

  // Geometric speed (between consecutive filtered points) + bearing state
  LatLng? _lastAcceptedFilteredPos;
  DateTime? _lastFilteredTs;
  double _geometricSpeedKmh = 0.0;
  final List<LatLng> _recentFilteredPoints = []; // circular buffer, last 5
  double _bearingDeg = 0.0;

  // Special-start recovery
  static const double kSpecialStartRecoveryRadiusMeters = 80.0;
  static const int kSpecialStartRecoveryLookbackSeconds = 30;
  final Set<String> _recoveryAttempted = {};
  final StreamController<String> _recoveryStreamCtrl =
      StreamController<String>.broadcast();

  // Fuel point ("punto ristoro") passage notifications
  final StreamController<String> _fuelPointStreamCtrl =
      StreamController<String>.broadcast();

  bool get isRecording => _isRecording;
  String? get activeEventId => _activeEventId;

  void blockFurtherWrites() => _writesBlocked = true;
  GpsMode get mode => _mode;
  Position? get lastPosition => _lastPosition;
  List<WaypointPassage> get passages => List.unmodifiable(_passages);
  List<LatLng> get localTrack => List.unmodifiable(_trackPoints);
  double get totalDistanceKm => _totalDistanceKm;
  String? get currentSpecialId => _currentSpecialId;
  String? get currentSpecialNome => _currentSpecialNome;
  List<SpecialEntry> get specialEntries => List.unmodifiable(_specialEntries);
  DateTime? get recordingStart => _recordingStart;
  Duration get elapsed => _recordingStart != null
      ? DateTime.now().difference(_recordingStart!)
      : Duration.zero;
  List<WaypointModel> get remainingWaypoints =>
      _waypoints.where((w) => !_passedWaypoints.contains(w.id)).toList();

  /// True when the last 5 consecutive GPS positions were discarded for poor accuracy.
  bool get isAccuracyPoor => _consecutiveDiscarded >= 5;

  /// Last Kalman-filtered position; null until the first accepted GPS fix.
  LatLng? get filteredPosition => _filteredPosition;

  /// Geometric bearing in degrees [0, 360), computed from consecutive
  /// Kalman-filtered points with exponential smoothing. Freezes below
  /// [kMinBearingSpeedKmh] to avoid jitter at low speed. Never uses
  /// `position.heading` or `position.speed` (unreliable on most chipsets).
  double get bearingDeg => _bearingDeg;

  /// Geometric speed in km/h, computed from the distance and time elapsed
  /// between the last two accepted Kalman-filtered positions. Used for the
  /// UI "VEL" readout, the bearing freeze threshold and the adaptive GPS
  /// interval — `position.speed` is never used for logic decisions.
  double get geometricSpeedKmh => _geometricSpeedKmh;

  /// Emits a localised message string each time a missed special start is
  /// retroactively recovered. Subscribers should display a timed banner.
  Stream<String> get recoveryStream => _recoveryStreamCtrl.stream;

  /// IDs of fuel points ("punti ristoro") already passed in this race.
  /// Persists for the lifetime of the GpsService (survives background/foreground)
  /// so the "approaching" banner never reappears once a point has been passed.
  Set<String> get passedFuelPoints => Set.unmodifiable(_passedFuelPoints);

  /// Emits a localised message each time a fuel point is passed for the first time.
  Stream<String> get fuelPointStream => _fuelPointStreamCtrl.stream;

  /// Punto pericolo più vicino entro la soglia di avviso (150m), o null.
  DangerPointModel? get warningDangerPoint => _warningDangerPoint;
  double? get warningDangerDistance => _warningDangerDistance;

  /// Punto pericolo in stato di allerta (entro 50m, lampeggio attivo), o null.
  DangerPointModel? get alertDangerPoint => _alertDangerPoint;
  double? get alertDangerDistance => _alertDangerDistance;
  bool get isDangerBlinking => _dangerBlinking;

  /// Computes the forward azimuth from [from] to [to] in degrees [0, 360).
  static double _computeBearingDeg(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
  }

  /// Velocità geometrica (km/h) tra due punti filtrati, basata sulla distanza
  /// haversine e sul delta temporale. Non usa mai `position.speed`.
  double _computeGeometricSpeedKmh(LatLng prev, LatLng curr, Duration dt) {
    final distM = _haversineKm(prev, curr) * 1000.0;
    final dtSec = dt.inMilliseconds / 1000.0;
    if (dtSec < 0.01) return _geometricSpeedKmh;
    return (distM / dtSec) * 3.6;
  }

  /// Interpolazione angolare con smoothing esponenziale (gestisce il wrap a 360°).
  static double _angularInterp(double from, double to, double alpha) {
    final diff = ((to - from + 540) % 360) - 180;
    return (from + alpha * diff + 360) % 360;
  }

  /// Retroactively detects a missed special-start waypoint.
  ///
  /// Called on every accepted GPS point. For each special whose START has not
  /// been registered yet:
  ///   1. Checks if the current position is within 3× the recovery radius of
  ///      the START waypoint (pilot is "inside" the special zone).
  ///   2. If so, scans the last [kSpecialStartRecoveryLookbackSeconds] seconds
  ///      of the recorded track for the point closest to the START.
  ///   3. If that closest point is within [kSpecialStartRecoveryRadiusMeters],
  ///      the start is retroactively registered using that point's timestamp.
  ///
  /// Each special is attempted at most once ([_recoveryAttempted]) to prevent loops.
  Future<void> _trySpecialStartRecovery(
      LatLng currentPos, DateTime now) async {
    for (final special in _specials) {
      final inizioId = special.waypointInizio.id;

      // Skip if already started, already attempted, or cancelled
      if (_passedWaypoints.contains(inizioId)) continue;
      if (_recoveryAttempted.contains(special.id)) continue;
      if (special.annullata) continue;

      // Trigger: current position within 3× recovery radius of the START
      final distToStartM = _haversineKm(
            currentPos,
            LatLng(special.waypointInizio.lat, special.waypointInizio.lng),
          ) *
          1000.0;
      if (distToStartM >= kSpecialStartRecoveryRadiusMeters * 3) continue;

      // Mark attempted before the lookback to prevent re-entry on subsequent points
      _recoveryAttempted.add(special.id);

      // Lookback: find track point closest to START within the time window
      final cutoff = now
          .subtract(Duration(seconds: kSpecialStartRecoveryLookbackSeconds));
      final startPt =
          LatLng(special.waypointInizio.lat, special.waypointInizio.lng);

      double bestDistM = double.infinity;
      int bestIdx = -1;
      for (int i = _recoveryTrack.length - 1; i >= 0; i--) {
        if (_recoveryTimestamps[i].isBefore(cutoff)) break;
        final d = _haversineKm(_recoveryTrack[i], startPt) * 1000.0;
        if (d < bestDistM) {
          bestDistM = d;
          bestIdx = i;
        }
      }

      if (bestIdx < 0 || bestDistM >= kSpecialStartRecoveryRadiusMeters) {
        continue;
      }

      // Recovery confirmed
      final recoveredTime = _recoveryTimestamps[bestIdx];
      debugPrint(
          'RECOVERY speciale ${special.id}: '
          'start retroattivo a $recoveredTime '
          '(dist min: ${bestDistM.toStringAsFixed(1)}m)');

      // Register inizio waypoint as passed to block double-detection
      _passedWaypoints.add(inizioId);
      _passages.add(
          WaypointPassage(waypoint: special.waypointInizio, timestamp: recoveredTime));

      // Open the special with the recovered entry time
      _currentSpecialId = special.id;
      _currentSpecialNome = special.nome;
      _specialEntries.add(SpecialEntry(
        specialeId: special.id,
        specialeNome: special.nome,
        entryTime: recoveredTime,
        recoveredStart: true,
      ));

      // Notify the UI
      _recoveryStreamCtrl.add('⚡ Inizio ${special.nome} recuperato');

      // Persist in Firestore with recoveredStart flag so admins can review it
      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: inizioId,
            waypointNome: special.waypointInizio.nome,
            timestamp: recoveredTime,
            recoveredStart: true,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: inizioId,
            waypointNome: special.waypointInizio.nome,
            timestamp: recoveredTime,
          );
        }
      }
    }
  }

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<void> startRecording({
    required String eventId,
    required String userId,
    required List<WaypointModel> waypoints,
    List<SpecialModel> specials = const [],
    List<WaypointModel> fuelPoints = const [],
    List<DangerPointModel> dangerPoints = const [],
  }) async {
    if (_isRecording) return;
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permesso GPS negato');
    // Try to flush any data queued during previous offline sessions
    if (_offlineQueue.hasPending) {
      _offlineQueue.syncPending(_firestoreService).ignore();
    }

    _writesBlocked = false;
    _activeEventId = eventId;
    _activeUserId = userId;
    _waypoints = waypoints;
    _specials = specials;
    _inizioToSpecial.clear();
    _fineToSpecial.clear();
    for (final s in specials) {
      _inizioToSpecial[s.waypointInizio.id] = s.id;
      _fineToSpecial[s.waypointFine.id] = s.id;
    }
    _passedWaypoints.clear();
    _fuelPoints = fuelPoints;
    _passedFuelPoints.clear();
    _dangerPoints = dangerPoints;
    _alertedDangerPoints.clear();
    _warningDangerPoint = null;
    _warningDangerDistance = null;
    _alertDangerPoint = null;
    _alertDangerDistance = null;
    _dangerBlinking = false;
    _passages.clear();
    _specialEntries.clear();
    _trackPoints.clear();
    _recoveryTrack.clear();
    _recoveryTimestamps.clear();
    _totalDistanceKm = 0.0;
    _currentSpecialId = null;
    _currentSpecialNome = null;
    _consecutiveDiscarded = 0;
    _filteredPosition = null;
    _kalmanFilter.reset();
    _lastAcceptedRawPos = null;
    _lastAcceptedTs = null;
    _jumpCount = 0;
    _lastAcceptedFilteredPos = null;
    _lastFilteredTs = null;
    _geometricSpeedKmh = 0.0;
    _recentFilteredPoints.clear();
    _bearingDeg = 0.0;
    _recoveryAttempted.clear();
    _isRecording = true;
    _mode = GpsMode.transfer;
    _recordingStart = DateTime.now();
    WakelockPlus.enable().ignore();
    notifyListeners();

    _firestoreService.setRaceStatus(eventId, userId, 'racing').catchError((_) {});
    _startPositionStream(AppConstants.gpsIntervalTransferMs);
  }

  void _startPositionStream(int intervalMs) {
    _positionSub?.cancel();
    // distanceFilter fisso a kDistanceFilterMeters per tutte le modalità:
    // 0 causava l'accettazione di ogni scatter GPS come punto valido
    // (pattern "a ventaglio" da fermo). L'adattività resta sull'intervallo
    // temporale (intervalMs), non sulla distanza minima tra fix.
    final LocationSettings settings;
    if (kIsWeb) {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanceFilterMeters,
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanceFilterMeters,
        intervalDuration: Duration(milliseconds: intervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'CCR Rally — GPS attivo in background',
          notificationTitle: 'Registrazione GPS',
          enableWakeLock: true,
          setOngoing: true,
          notificationChannelName: 'CCR GPS Tracking',
        ),
      );
    } else {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: kDistanceFilterMeters,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      _onPosition,
      onError: (e) {
        debugPrint('GPS stream error: $e');
        if (_isRecording) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_isRecording) _startPositionStream(intervalMs);
          });
        }
      },
    );
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

  void _onPosition(Position pos) async {
    // Always store raw position and emit stream — UI uses it for accuracy display.
    _lastPosition = pos;
    _posStreamCtrl.add(pos);

    final now = DateTime.now();
    final rawLatLng = LatLng(pos.latitude, pos.longitude);

    // ── STEP 1: filtro accuracy adattivo ──────────────────────────────────
    // Soglia normale 15m; soglia di fallback 40m se nessun punto è stato
    // accettato da più di kAccuracyFallbackSeconds secondi (evita un
    // freeze totale quando il segnale resta scadente a lungo).
    final accuracyThreshold = (_lastAcceptedTs != null &&
            now.difference(_lastAcceptedTs!).inSeconds >
                kAccuracyFallbackSeconds)
        ? kAccuracyThresholdFallback
        : kAccuracyThresholdNormal;
    if (pos.accuracy > accuracyThreshold) {
      _consecutiveDiscarded++;
      notifyListeners();
      return;
    }
    _consecutiveDiscarded = 0;

    // ── STEP 2: filtro jump geometrico ────────────────────────────────────
    // Scarta punti che implicano una velocità fisicamente impossibile, a
    // meno che kMaxConsecutiveJumps punti consecutivi siano già stati
    // scartati — in tal caso il GPS ha "teletrasportato" (tunnel, perdita
    // di segnale) e il punto viene accettato resettando il Kalman.
    if (_lastAcceptedRawPos != null && _lastAcceptedTs != null) {
      final dtMs = now.difference(_lastAcceptedTs!).inMilliseconds;
      final impliedSpeedKmh = _computeGeometricSpeedKmh(
          _lastAcceptedRawPos!, rawLatLng, Duration(milliseconds: dtMs));
      if (impliedSpeedKmh > kMaxSpeedFilterKmh) {
        _jumpCount++;
        if (_jumpCount < kMaxConsecutiveJumps) {
          debugPrint(
              'GPS JUMP scartato: ${impliedSpeedKmh.toStringAsFixed(0)} km/h');
          notifyListeners();
          return;
        }
        _kalmanFilter.reset();
        _jumpCount = 0;
      } else {
        _jumpCount = 0;
      }
    }
    _lastAcceptedRawPos = rawLatLng;
    _lastAcceptedTs = now;

    // ── STEP 3: Kalman filter 4D cinematico ─────────────────────────────────
    final filteredPos =
        _kalmanFilter.filter(pos.latitude, pos.longitude, pos.accuracy, now);
    _filteredPosition = filteredPos;

    // ── STEP 4: filtro spostamento minimo ───────────────────────────────────
    // Fix diretto al pattern "a ventaglio": sotto soglia non si aggiorna la
    // polyline/distanza, ma si prosegue comunque con bearing, waypoint
    // detection, recovery e tracking live.
    var updatePolyline = true;
    if (_lastAcceptedFilteredPos != null) {
      final dispM =
          _haversineKm(_lastAcceptedFilteredPos!, filteredPos) * 1000.0;
      if (dispM < kMinDisplacementMeters) {
        updatePolyline = false;
      }
    }

    // ── STEP 5: velocità geometrica e bearing ───────────────────────────────
    if (_lastAcceptedFilteredPos != null && _lastFilteredTs != null) {
      final dtMs = now.difference(_lastFilteredTs!).inMilliseconds;
      _geometricSpeedKmh = _computeGeometricSpeedKmh(
          _lastAcceptedFilteredPos!, filteredPos, Duration(milliseconds: dtMs));
    }
    _lastAcceptedFilteredPos = filteredPos;
    _lastFilteredTs = now;

    // Circular buffer of last 5 Kalman-filtered points for bearing
    _recentFilteredPoints.add(filteredPos);
    if (_recentFilteredPoints.length > 5) _recentFilteredPoints.removeAt(0);

    // Bearing: smoothing esponenziale sopra kMinBearingSpeedKmh; sotto
    // soglia resta congelato all'ultimo valore (freccia stabile da fermo).
    if (_geometricSpeedKmh > kMinBearingSpeedKmh &&
        _recentFilteredPoints.length >= 2) {
      final rawBearing = _computeBearingDeg(
        _recentFilteredPoints[_recentFilteredPoints.length - 2],
        _recentFilteredPoints[_recentFilteredPoints.length - 1],
      );
      _bearingDeg =
          _angularInterp(_bearingDeg, rawBearing, kBearingSmoothingAlpha);
    }

    debugPrint(
        'Bearing: ${_bearingDeg.toStringAsFixed(1)}°, '
        'Speed: ${_geometricSpeedKmh.toStringAsFixed(1)} km/h, '
        'Mode: $mode');

    // Recovery track: ogni punto accettato, per il lookback inizio speciale
    _recoveryTrack.add(filteredPos);
    _recoveryTimestamps.add(now);

    // Detect waypoint passage — sempre sulla posizione filtrata Kalman
    final wp = WaypointDetector.detectPassage(
        filteredPos, _waypoints, _passedWaypoints);
    if (wp != null) {
      _passedWaypoints.add(wp.id);
      final passage = WaypointPassage(waypoint: wp, timestamp: now);
      _passages.add(passage);

      // Special entry/exit detection
      if (_inizioToSpecial.containsKey(wp.id) && _currentSpecialId == null) {
        final specialId = _inizioToSpecial[wp.id]!;
        final special = _specials.where((s) => s.id == specialId).firstOrNull;
        _currentSpecialId = specialId;
        _currentSpecialNome = special?.nome;
        _specialEntries.add(SpecialEntry(
          specialeId: specialId,
          specialeNome: special?.nome ?? specialId,
          entryTime: now,
        ));
      } else if (_fineToSpecial.containsKey(wp.id) &&
          _currentSpecialId == _fineToSpecial[wp.id]) {
        final idx =
            _specialEntries.lastIndexWhere((e) => e.exitTime == null);
        if (idx >= 0) {
          _specialEntries[idx] = _specialEntries[idx].withExit(now);
        }
        _currentSpecialId = null;
        _currentSpecialNome = null;
      }

      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: wp.id,
            waypointNome: wp.nome,
            timestamp: passage.timestamp,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: wp.id,
            waypointNome: wp.nome,
            timestamp: passage.timestamp,
          );
        }
      }
    }

    // Recovery: retroactively detect missed special starts
    await _trySpecialStartRecovery(filteredPos, now);

    // Fuel point passage: mark as passed once within radius, notify exactly once.
    // After this, the "approaching" banner stops even if a GPS jump brings the
    // pilot virtually back near the fuel point.
    for (final fp in _fuelPoints) {
      if (_passedFuelPoints.contains(fp.id)) continue;
      final distM = _haversineKm(filteredPos, LatLng(fp.lat, fp.lng)) * 1000.0;
      if (distM <= AppConstants.fuelPointRadiusMeters) {
        _passedFuelPoints.add(fp.id);
        _fuelPointStreamCtrl.add('✅ Punto ristoro raggiunto');
      }
    }

    // Punti pericolo: aggiorna soglie di prossimità avviso (150m) e allerta (50m)
    final wasDangerNear = _alertedDangerPoints.isNotEmpty;
    DangerPointModel? warnPoint;
    double? warnDist;
    for (final dp in _dangerPoints) {
      final distM = WaypointDetector.dangerPointDistance(filteredPos, dp);
      if (distM <= AppConstants.dangerWarningRadiusMeters) {
        _alertedDangerPoints.add(dp.id);
      } else if (distM > AppConstants.dangerRemoveRadiusMeters) {
        _alertedDangerPoints.remove(dp.id);
      }
      if (_alertedDangerPoints.contains(dp.id)) {
        if (warnDist == null || distM < warnDist) {
          warnDist = distM;
          warnPoint = dp;
        }
      }
    }
    _warningDangerPoint = warnPoint;
    _warningDangerDistance = warnDist;
    if (warnPoint != null && warnDist! <= AppConstants.dangerAlertRadiusMeters) {
      _alertDangerPoint = warnPoint;
      _alertDangerDistance = warnDist;
      _dangerBlinking = true;
    } else if (_dangerBlinking) {
      if (warnPoint != null && warnPoint.id == _alertDangerPoint?.id) {
        _alertDangerDistance = warnDist;
        if (warnDist! > AppConstants.dangerAlertClearRadiusMeters) {
          _dangerBlinking = false;
          _alertDangerPoint = null;
          _alertDangerDistance = null;
        }
      } else {
        _dangerBlinking = false;
        _alertDangerPoint = null;
        _alertDangerDistance = null;
      }
    }
    final dangerNear = _alertedDangerPoints.isNotEmpty;

    // Determine mode
    final remainingForMode =
        _waypoints.where((w) => !_passedWaypoints.contains(w.id)).toList();
    final nearest =
        WaypointDetector.nearestWaypointDistance(filteredPos, remainingForMode);
    final newMode = nearest != null &&
            nearest <= AppConstants.nearWaypointThresholdMeters
        ? GpsMode.nearWaypoint
        : (_currentSpecialId != null ? GpsMode.inSpecial : GpsMode.transfer);

    // Adapt interval if mode or danger-zone proximity changed
    if (newMode != _mode || dangerNear != wasDangerNear) {
      _mode = newMode;
      var newInterval = WaypointDetector.adaptiveInterval(
          nearest, _currentSpecialId != null);
      if (dangerNear) {
        newInterval = min(newInterval, AppConstants.gpsIntervalNearDangerMs);
      }
      _startPositionStream(newInterval);
    }

    // ── STEP 6: aggiorna polyline display + distanza totale ─────────────────
    // Solo se lo spostamento (STEP 4) è >= kMinDisplacementMeters, per non
    // accumulare rumore GPS come distanza e non disegnare il pattern "a
    // ventaglio" da fermo.
    if (updatePolyline) {
      if (_trackPoints.isNotEmpty) {
        _totalDistanceKm += _haversineKm(_trackPoints.last, filteredPos);
      }
      _trackPoints.add(filteredPos);
    }

    // Push live tracking to Firestore — queue offline if unavailable.
    // Usa coordinate Kalman-filtrate e velocità geometrica (mai position.speed).
    if (_activeEventId != null && _activeUserId != null) {
      final point = GpsPointModel(
        userId: _activeUserId!,
        eventId: _activeEventId!,
        lat: filteredPos.latitude,
        lng: filteredPos.longitude,
        accuracy: pos.accuracy,
        speed: _geometricSpeedKmh / 3.6,
        timestamp: now,
        specialeId: _currentSpecialId,
        waypointPassati: _passedWaypoints.toList(),
      );
      if (!_writesBlocked) {
        _firestoreService.updatePilotTracking(point).catchError((_) {
          _offlineQueue.queueTracking(point).ignore();
        });
      }
    }

    notifyListeners();
  }

  Future<void> stopRecording() async {
    _positionSub?.cancel();
    _positionSub = null;
    _isRecording = false;
    _writesBlocked = false;
    _mode = GpsMode.idle;
    _activeEventId = null;
    _activeUserId = null;
    _currentSpecialId = null;
    _currentSpecialNome = null;
    _recordingStart = null;
    _consecutiveDiscarded = 0;
    _filteredPosition = null;
    _kalmanFilter.reset();
    _lastAcceptedRawPos = null;
    _lastAcceptedTs = null;
    _jumpCount = 0;
    _lastAcceptedFilteredPos = null;
    _lastFilteredTs = null;
    _geometricSpeedKmh = 0.0;
    _recentFilteredPoints.clear();
    _bearingDeg = 0.0;
    _recoveryAttempted.clear();
    _trackPoints.clear();
    _recoveryTrack.clear();
    _recoveryTimestamps.clear();
    _alertedDangerPoints.clear();
    _warningDangerPoint = null;
    _warningDangerDistance = null;
    _alertDangerPoint = null;
    _alertDangerDistance = null;
    _dangerBlinking = false;
    WakelockPlus.disable().ignore();
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _posStreamCtrl.close();
    _recoveryStreamCtrl.close();
    _fuelPointStreamCtrl.close();
    super.dispose();
  }
}
