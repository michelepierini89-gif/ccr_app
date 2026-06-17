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
import '../services/imu_fusion_service.dart';
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
  // STEP 1 — Doppia soglia accuracy: DISPLAY (Kalman/polyline) vs DETECTION
  // (waypoint timing). Con ±8m dichiarati l'errore reale può essere 20-30m:
  // un punto così impreciso corrompe il Kalman, ma scartarlo del tutto
  // rischia di perdere il passaggio di un waypoint. Soglia display più
  // restrittiva (meglio gaps che scatter), soglia detection più permissiva.
  // 8.0 (era 10.0): il chip MediaTek del DOOGEE dichiara accuracy
  // ottimistica, abbassare la soglia migliora la qualità del Kalman.
  static const double kMaxAccuracyDisplayMeters = 8.0;
  static const double kMaxAccuracyDetectionMeters = 25.0;

  // Soglia display PROGRESSIVA durante l'acquisizione iniziale: il chip GPS
  // impiega normalmente 30-60s a convergere dopo l'avvio del tracking, con
  // accuracy ben oltre 8m nei primi secondi. Una soglia fissa scarterebbe
  // sistematicamente TUTTI i punti in questa fase (Kalman/display mai
  // inizializzati). La soglia si restringe a step man mano che passa il
  // tempo dall'avvio, fino al valore finale kMaxAccuracyDisplayMeters.
  static const double kAccuracyStartupThreshold1 = 30.0; // 0-20s
  static const double kAccuracyStartupThreshold2 = 15.0; // 20-45s
  static const int kAccuracyStartupPhase1Seconds = 20;
  static const int kAccuracyStartupPhase2Seconds = 45;

  // STEP 2 — Filtro jump geometrico: secondo livello dopo il Kalman 4D.
  // Scarta SEMPRE i punti che implicherebbero una velocità superiore a
  // kMaxSpeedFilterKmh — 120 km/h è già il massimo realistico per un
  // enduro su sentiero. Tra 120 e 200 km/h ci sono solo ghost points
  // multipath, non velocità reali: nessuna eccezione di "jump accettato"
  // (causava il pattern a ventaglio e i tempi PS impossibili).
  static const double kMaxSpeedFilterKmh = 120.0;

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
  final ImuFusionService _imu;

  GpsService(this._firestoreService, this._offlineQueue, this._imu);

  /// Servizio di fusione IMU (giroscopio + accelerometro + bussola) usato
  /// SOLO per il display a 50Hz (freccia, polyline live, velocità UI).
  /// MAI per waypoint detection, timing PS o recovery.
  ImuFusionService get imu => _imu;

  final StreamController<Position> _posStreamCtrl =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _posStreamCtrl.stream;

  bool _isRecording = false;
  bool _writesBlocked = false;
  bool _disposed = false;
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
  // Punti pericolo già superati (entro 15m) in questa sessione: niente più
  // banner di avviso/allerta per questi, anche se il pilota torna indietro.
  // Resettato solo in startRecording (nuova sessione), non in stopRecording.
  final Set<String> _passedDangerPoints = {};
  final StreamController<String> _dangerPassedStreamCtrl =
      StreamController<String>.broadcast();
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

  // Display/distance track: only points that moved past the display anchor
  // (see _displayAnchor below). Used for the pilot polyline and for the
  // cumulative distance — avoids accumulating GPS jitter as distance.
  final List<LatLng> _trackPoints = [];

  // Anchor per il display della polyline: si sposta solo quando il pilota si
  // è mosso davvero (soglia adattiva alla velocità in _anchorThresholdMeters).
  // Un displacement check punto-precedente lascia passare scatter da 2-3m che
  // formano catene e disegnano il pattern "a ventaglio"; un anchor fisso no.
  // Controlla SOLO la polyline blu: bearing, waypoint detection, recovery
  // track e tracking live su Firestore usano sempre filteredPos direttamente.
  LatLng? _displayAnchor;

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

  // Doppia conferma waypoint: protegge la rilevazione PS dai ghost points.
  final WaypointDetector _waypointDetector = WaypointDetector();

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

  // Special-end recovery (recovery retroattivo della fine PS, speculare
  // al recovery dell'inizio sopra)
  static const double kSpecialEndRecoveryRadiusMeters = 80.0;
  static const int kSpecialEndRecoveryLookbackSeconds = 30;
  final Set<String> _endRecoveryAttempted = {};

  // Fuel point ("punto ristoro") passage notifications
  final StreamController<String> _fuelPointStreamCtrl =
      StreamController<String>.broadcast();

  // GPS freeze watchdog: _lastRawPositionTs è aggiornato ad OGNI posizione
  // ricevuta (valida o scartata dai filtri), per distinguere "GPS che non
  // manda più nulla" da "GPS che manda solo punti scartati".
  DateTime? _lastRawPositionTs;
  bool _isGpsFrozen = false;
  bool _isRestartingGps = false;
  Timer? _freezeDetectionTimer;
  int _currentIntervalMs = AppConstants.gpsIntervalTransferMs;
  static const int kFreezeDetectionSeconds = 8;
  static const int kFreezeRestartSeconds = 15;

  // Grace period di acquisizione: prima del PRIMO fix raw in assoluto
  // (_lastRawPositionTs == null), il chip GPS può normalmente impiegare
  // 30-60s (cold start, indoor, ecc.). Il watchdog freeze/restart resta
  // inattivo durante questa finestra — altrimenti un restart automatico a
  // metà acquisizione fa ripartire il chip da zero, impedendo per sempre
  // la convergenza (loop di restart infinito che non lascia mai arrivare
  // il primo fix). Oltre la finestra di grazia senza nessun fix, il
  // freeze è considerato reale.
  static const int kStartupGracePeriodSeconds = 60;

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

  /// True when the last 2 consecutive GPS positions were discarded for poor
  /// accuracy (abbassato da 3: con soglia display 8m gli scarti sono più
  /// frequenti).
  bool get isAccuracyPoor => _consecutiveDiscarded >= 2;

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

  /// IDs dei punti pericolo già superati (entro 15m) in questa sessione.
  Set<String> get passedDangerPoints => Set.unmodifiable(_passedDangerPoints);

  /// Emette un messaggio quando un punto pericolo viene superato per la
  /// prima volta in questa sessione (mostrare una SnackBar verde, 2s).
  Stream<String> get dangerPassedStream => _dangerPassedStreamCtrl.stream;

  /// True se non arriva nessuna posizione GPS (valida o no) da almeno
  /// [kFreezeDetectionSeconds] secondi.
  bool get isGpsFrozen => _isGpsFrozen;

  /// True durante il riavvio automatico/manuale dello stream GPS.
  bool get isRestartingGps => _isRestartingGps;

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

  /// Soglia di spostamento dall'anchor display, adattiva alla velocità
  /// geometrica corrente: più si va piano, più serve spostamento reale per
  /// muovere la polyline (evita il pattern "a ventaglio" da fermo).
  double _anchorThresholdMeters() {
    if (_geometricSpeedKmh > 60) return 2.0;
    if (_geometricSpeedKmh > 20) return 3.5;
    if (_geometricSpeedKmh > 5) return 6.0;
    return 10.0;
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
      if (_disposed) return;
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

      // STEP 4 — validazione timestamp: rifiuta recovery con timestamp
      // corrotti (es. da inizializzazione GPS o sessione precedente), che
      // produrrebbero PS con durata enorme (es. 795 minuti).
      final ageSeconds = now.difference(recoveredTime).inSeconds;
      if (ageSeconds > 60 || recoveredTime.isAfter(now)) {
        debugPrint('RECOVERY RIFIUTATO: timestamp non valido '
            '(age: ${ageSeconds}s)');
        continue;
      }
      if (_recordingStart != null &&
          recoveredTime.isBefore(_recordingStart!)) {
        debugPrint('RECOVERY RIFIUTATO: timestamp precedente '
            'all\'avvio sessione');
        continue;
      }

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

  /// Registra un passaggio waypoint confermato da [WaypointDetector]:
  /// aggiorna i passaggi, l'apertura/chiusura delle speciali e persiste su
  /// Firestore (con fallback su coda offline). Usata sia per i punti che
  /// superano il filtro accuracy display, sia per i punti scartati dal
  /// display ma ancora validi per la detection (STEP 1).
  Future<void> _handleWaypointDetection(WaypointPassageResult detection) async {
    final wp = detection.waypoint;
    final passageTs = detection.timestamp;
    _passedWaypoints.add(wp.id);
    final passage = WaypointPassage(waypoint: wp, timestamp: passageTs);
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
        entryTime: passageTs,
      ));
    } else if (_fineToSpecial.containsKey(wp.id) &&
        _currentSpecialId == _fineToSpecial[wp.id]) {
      final idx = _specialEntries.lastIndexWhere((e) => e.exitTime == null);
      if (idx >= 0) {
        _specialEntries[idx] = _specialEntries[idx].withExit(passageTs);
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

  /// Recovery retroattivo della fine PS non rilevata (speculare a
  /// [_trySpecialStartRecovery]).
  ///
  /// Per ogni speciale avviata e non ancora conclusa: se la posizione
  /// corrente è "oltre" il waypoint di fine (tra 1× e 4× il raggio di
  /// recovery, cioè l'abbiamo superato senza rilevarlo), scandisce gli
  /// ultimi [kSpecialEndRecoveryLookbackSeconds] secondi di [_recoveryTrack]
  /// cercando il punto più vicino al waypoint di fine. Se trovato entro
  /// [kSpecialEndRecoveryRadiusMeters], registra la fine PS retroattiva con
  /// quel timestamp.
  Future<void> _trySpecialEndRecovery(LatLng currentPos, DateTime now) async {
    for (final special in _specials) {
      if (_disposed) return;
      if (special.annullata) continue;
      if (_endRecoveryAttempted.contains(special.id)) continue;

      final entryIdx = _specialEntries
          .lastIndexWhere((e) => e.specialeId == special.id && e.exitTime == null);
      if (entryIdx < 0) continue; // non avviata, o già conclusa

      final endWp = special.waypointFine;
      final endPt = LatLng(endWp.lat, endWp.lng);
      final distToEndM = _haversineKm(currentPos, endPt) * 1000.0;

      // Trigger: siamo "oltre" l'END (l'abbiamo superato senza rilevarlo)
      if (distToEndM <= kSpecialEndRecoveryRadiusMeters ||
          distToEndM >= kSpecialEndRecoveryRadiusMeters * 4) {
        continue;
      }

      _endRecoveryAttempted.add(special.id);

      // Lookback: trova il punto del tracciato più vicino all'END nella finestra temporale
      final cutoff =
          now.subtract(Duration(seconds: kSpecialEndRecoveryLookbackSeconds));
      double bestDistM = double.infinity;
      int bestIdx = -1;
      for (int i = _recoveryTrack.length - 1; i >= 0; i--) {
        if (_recoveryTimestamps[i].isBefore(cutoff)) break;
        final d = _haversineKm(_recoveryTrack[i], endPt) * 1000.0;
        if (d < bestDistM) {
          bestDistM = d;
          bestIdx = i;
        }
      }

      if (bestIdx < 0 || bestDistM >= kSpecialEndRecoveryRadiusMeters) continue;

      final recoveredTime = _recoveryTimestamps[bestIdx];

      // Validazione timestamp: stesse regole del recovery START
      final ageSeconds = now.difference(recoveredTime).inSeconds;
      if (ageSeconds > 60 || recoveredTime.isAfter(now)) {
        debugPrint('RECOVERY END RIFIUTATO: timestamp non valido '
            '(age: ${ageSeconds}s)');
        continue;
      }
      if (_recordingStart != null && recoveredTime.isBefore(_recordingStart!)) {
        debugPrint('RECOVERY END RIFIUTATO: timestamp precedente '
            'all\'avvio sessione');
        continue;
      }

      // Sanity check: durata PS plausibile
      final entryTime = _specialEntries[entryIdx].entryTime;
      final durationMin = recoveredTime.difference(entryTime).inMinutes;
      if (durationMin > 90 || durationMin < 0) {
        debugPrint('RECOVERY END RIFIUTATO: durata PS implausibile '
            '(${durationMin}min)');
        continue;
      }

      // Registra fine PS retroattiva
      _specialEntries[entryIdx] =
          _specialEntries[entryIdx].withExit(recoveredTime);
      if (_currentSpecialId == special.id) {
        _currentSpecialId = null;
        _currentSpecialNome = null;
      }
      _passedWaypoints.add(endWp.id);
      _passages.add(WaypointPassage(waypoint: endWp, timestamp: recoveredTime));

      debugPrint('RECOVERY END speciale ${special.id}: '
          'fine retroattiva a $recoveredTime '
          '(dist: ${bestDistM.toStringAsFixed(1)}m)');

      _recoveryStreamCtrl.add('⚡ Fine ${special.nome} recuperata');

      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
            timestamp: recoveredTime,
            recoveredEnd: true,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
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
    _passedDangerPoints.clear();
    _warningDangerPoint = null;
    _warningDangerDistance = null;
    _alertDangerPoint = null;
    _alertDangerDistance = null;
    _dangerBlinking = false;
    _passages.clear();
    _specialEntries.clear();
    _trackPoints.clear();
    _displayAnchor = null;
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
    _lastAcceptedFilteredPos = null;
    _lastFilteredTs = null;
    _geometricSpeedKmh = 0.0;
    _recentFilteredPoints.clear();
    _bearingDeg = 0.0;
    _recoveryAttempted.clear();
    _endRecoveryAttempted.clear();
    _waypointDetector.reset();
    _isRecording = true;
    _mode = GpsMode.transfer;
    _recordingStart = DateTime.now();
    _lastRawPositionTs = null;
    _isGpsFrozen = false;
    _isRestartingGps = false;
    // Notifica IMMEDIATA: la schermata di navigazione deve apparire subito,
    // indipendentemente da quanto impiega il GPS a fornire un fix. Tutto
    // quello che segue (IMU, stream posizione) avviene in background mentre
    // l'utente vede già la mappa e i controlli attivi.
    _safeNotify();

    WakelockPlus.enable().ignore();
    await _imu.start();

    _firestoreService.setRaceStatus(eventId, userId, 'racing').catchError((_) {});
    _startPositionStream(AppConstants.gpsIntervalTransferMs);

    _freezeDetectionTimer?.cancel();
    _freezeDetectionTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkFreeze());
  }

  void _startPositionStream(int intervalMs) {
    _currentIntervalMs = intervalMs;
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

  /// Soglia accuracy display progressiva: più permissiva nei primi secondi
  /// dall'avvio della registrazione (fase di acquisizione/convergenza del
  /// chip GPS), si restringe a step fino al valore finale
  /// [kMaxAccuracyDisplayMeters] una volta che il segnale si è stabilizzato.
  double _currentDisplayAccuracyThreshold(DateTime now) {
    if (_recordingStart == null) return kMaxAccuracyDisplayMeters;
    final secSinceStart = now.difference(_recordingStart!).inSeconds;
    if (secSinceStart < kAccuracyStartupPhase1Seconds) {
      return kAccuracyStartupThreshold1;
    }
    if (secSinceStart < kAccuracyStartupPhase2Seconds) {
      return kAccuracyStartupThreshold2;
    }
    return kMaxAccuracyDisplayMeters;
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

    // Watchdog: aggiornato ad OGNI posizione ricevuta, valida o no, PRIMA di
    // qualsiasi filtro — distingue "GPS muto" da "GPS che manda solo scarti".
    _lastRawPositionTs = now;
    if (_isGpsFrozen) {
      _isGpsFrozen = false;
      _safeNotify();
    }

    // ── STEP 1: doppia soglia accuracy DISPLAY vs DETECTION ──────────────
    // Oltre la soglia display il punto è troppo impreciso per Kalman/
    // polyline e viene scartato, ma se è ancora entro
    // kMaxAccuracyDetectionMeters la detection waypoint viene comunque
    // eseguita sulla posizione raw, per non perdere passaggi con segnale
    // debole. La soglia display è progressiva nei primi secondi dall'avvio
    // (vedi _currentDisplayAccuracyThreshold): altrimenti la convergenza
    // normale del chip (30-60s) scarterebbe ogni punto e Kalman/IMU
    // resterebbero inizializzati a null per tutta quella finestra.
    final displayThreshold = _currentDisplayAccuracyThreshold(now);
    if (pos.accuracy > displayThreshold) {
      _consecutiveDiscarded++;
      if (pos.accuracy <= kMaxAccuracyDetectionMeters) {
        final detection = _waypointDetector.detectPassage(
            rawLatLng, now, _waypoints, _passedWaypoints);
        if (detection != null) {
          await _handleWaypointDetection(detection);
        }
      }
      if (_disposed) return;
      _safeNotify();
      return;
    }
    _consecutiveDiscarded = 0;

    // ── STEP 2: filtro jump geometrico ────────────────────────────────────
    // Punti che implicherebbero una velocità superiore a kMaxSpeedFilterKmh
    // sono fisicamente impossibili per un enduro su sentiero e vengono
    // SEMPRE scartati, senza eccezioni: non esiste più una regola di "jump
    // accettato" che permetteva al Kalman di "teletrasportarsi" su un ghost
    // point multipath. Se il segnale GPS è perso (tunnel), si prosegue con
    // l'ultima stima Kalman finché non arriva un punto plausibile; il reset
    // automatico del Kalman dopo un gap > 10s (kalman_filter.dart) gestisce
    // comunque la ripresa.
    if (_lastAcceptedRawPos != null && _lastAcceptedTs != null) {
      final dtMs = now.difference(_lastAcceptedTs!).inMilliseconds;
      if (dtMs > 0) {
        final impliedSpeedKmh = _computeGeometricSpeedKmh(
            _lastAcceptedRawPos!, rawLatLng, Duration(milliseconds: dtMs));
        if (impliedSpeedKmh > kMaxSpeedFilterKmh) {
          debugPrint(
              'GPS JUMP scartato: ${impliedSpeedKmh.toStringAsFixed(0)} km/h');
          _safeNotify();
          return;
        }
      }
    }
    _lastAcceptedRawPos = rawLatLng;
    _lastAcceptedTs = now;

    // ── STEP 3: Kalman filter 4D cinematico ─────────────────────────────────
    var filteredPos =
        _kalmanFilter.filter(pos.latitude, pos.longitude, pos.accuracy, now);

    // ── STEP 3b: sanity check post-Kalman ───────────────────────────────────
    // Se la stima Kalman implica una velocità anche più assurda della soglia
    // jump (STEP 2), lo stato interno del filtro è corrotto: si resetta e si
    // rifiltra il punto raw da zero, usandolo come nuovo anchor.
    if (_lastAcceptedFilteredPos != null && _lastFilteredTs != null) {
      final dtMsK = now.difference(_lastFilteredTs!).inMilliseconds;
      if (dtMsK > 0) {
        final kalmanImpliedSpeed = _computeGeometricSpeedKmh(
            _lastAcceptedFilteredPos!, filteredPos,
            Duration(milliseconds: dtMsK));
        if (kalmanImpliedSpeed > kMaxSpeedFilterKmh * 1.2) {
          _kalmanFilter.reset();
          filteredPos = _kalmanFilter.filter(
              pos.latitude, pos.longitude, pos.accuracy, now);
          debugPrint('KALMAN RESET: stima impossibile '
              '${kalmanImpliedSpeed.toStringAsFixed(0)} km/h');
        }
      }
    }
    _filteredPosition = filteredPos;

    // ── STEP 4: filtro display anchor-based ─────────────────────────────────
    // Fix diretto al pattern "a ventaglio": un anchor fisso si sposta solo
    // con movimento reale sostenuto (soglia adattiva alla velocità). Sotto
    // soglia non si aggiorna la polyline/distanza, ma si prosegue comunque
    // con bearing, waypoint detection, recovery e tracking live, che usano
    // sempre filteredPos direttamente.
    var updatePolyline = false;
    if (_displayAnchor == null) {
      _displayAnchor = filteredPos;
      updatePolyline = true;
    } else {
      final distFromAnchorM =
          _haversineKm(_displayAnchor!, filteredPos) * 1000.0;
      if (distFromAnchorM >= _anchorThresholdMeters()) {
        _displayAnchor = filteredPos;
        updatePolyline = true;
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

    // Sigma accel dinamico: a velocità più basse il filtro Kalman può
    // smorzare di più (meno dinamica da inseguire); a velocità da enduro
    // serve tolleranza alle brusche variazioni di direzione/velocità.
    final targetSigma = _geometricSpeedKmh < 10.0
        ? GpsKalmanFilter.kSigmaAccelWalking
        : _geometricSpeedKmh < 40.0
            ? GpsKalmanFilter.kSigmaAccelMedium
            : GpsKalmanFilter.kSigmaAccelMotorcycle;
    _kalmanFilter.updateSigmaAccel(targetSigma);

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

    // Detect waypoint passage — sempre sulla posizione filtrata Kalman,
    // confermato solo dopo 2 rilevazioni consecutive (protezione ghost point);
    // il timestamp usato è quello della PRIMA rilevazione, non della seconda.
    final detection = _waypointDetector.detectPassage(
        filteredPos, now, _waypoints, _passedWaypoints);
    if (detection != null) {
      await _handleWaypointDetection(detection);
      if (_disposed) return;
    }

    // Recovery: retroactively detect missed special starts/ends
    await _trySpecialStartRecovery(filteredPos, now);
    if (_disposed) return;
    await _trySpecialEndRecovery(filteredPos, now);
    if (_disposed) return;

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

      // Superato (entro 15m): segna come passato permanentemente per la
      // sessione, notifica una sola volta e non mostrare più avvisi per
      // questo punto, anche se il pilota torna indietro.
      if (distM <= AppConstants.dangerPassedRadiusMeters &&
          !_passedDangerPoints.contains(dp.id)) {
        _passedDangerPoints.add(dp.id);
        _alertedDangerPoints.remove(dp.id);
        if (_alertDangerPoint?.id == dp.id) {
          _alertDangerPoint = null;
          _alertDangerDistance = null;
          _dangerBlinking = false;
        }
        _dangerPassedStreamCtrl.add('✓ Punto pericolo superato');
      }
      if (_passedDangerPoints.contains(dp.id)) continue;

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
    // Solo se l'anchor display (STEP 4) si è spostato, per non accumulare
    // rumore GPS come distanza e non disegnare il pattern "a ventaglio" da
    // fermo.
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

    // Aggiorna anchor IMU con il fix GPS Kalman filtrato.
    // L'IMU usa questo per correggere la deriva del dead reckoning.
    // NOTA: questa chiamata NON influenza waypoint detection
    // né timing PS — quelli usano filteredPos direttamente.
    _imu.updateWithGps(
      position: filteredPos,
      speedKmh: _geometricSpeedKmh,
      timestamp: now,
    );

    _safeNotify();
  }

  /// Controllo periodico (ogni 3s) del watchdog GPS: se non arriva nessuna
  /// posizione raw da [kFreezeDetectionSeconds] secondi mostra il banner
  /// "GPS bloccato"; da [kFreezeRestartSeconds] secondi tenta un riavvio
  /// automatico dello stream.
  void _checkFreeze() {
    if (!_isRecording) return;
    final now = DateTime.now();

    if (_lastRawPositionTs == null) {
      // Nessun fix raw ancora arrivato dall'avvio: il chip GPS può
      // normalmente impiegare 30-60s (cold start). Durante la finestra di
      // grazia il watchdog resta inattivo, per non riavviare lo stream a
      // metà acquisizione e farla ripartire da zero all'infinito.
      final secSinceStart = _recordingStart != null
          ? now.difference(_recordingStart!).inSeconds
          : 0;
      if (secSinceStart < kStartupGracePeriodSeconds) return;

      // Oltre la finestra di grazia senza nemmeno un fix: freeze reale.
      if (!_isGpsFrozen) {
        _isGpsFrozen = true;
        _safeNotify();
        debugPrint(
            'GPS FREEZE: nessun fix raw da oltre ${kStartupGracePeriodSeconds}s dall\'avvio');
      }
      _attemptGpsRestart();
      return;
    }

    final secSinceLast = now.difference(_lastRawPositionTs!).inSeconds;

    if (secSinceLast >= kFreezeDetectionSeconds && !_isGpsFrozen) {
      _isGpsFrozen = true;
      _safeNotify();
      debugPrint('GPS FREEZE rilevato: ${secSinceLast}s senza posizioni');
    }

    if (secSinceLast >= kFreezeRestartSeconds) {
      _attemptGpsRestart();
    }
  }

  /// Riavvia lo stream GPS cancellando e ricreando la subscription.
  /// Chiamato automaticamente dal watchdog, o manualmente tramite
  /// [attemptGpsRestart] dal banner "GPS bloccato".
  Future<void> _attemptGpsRestart() async {
    if (_isRestartingGps) return;
    debugPrint('GPS RESTART automatico...');
    _isRestartingGps = true;
    _safeNotify();

    await _positionSub?.cancel();
    _positionSub = null;

    await Future.delayed(const Duration(seconds: 1));
    if (_disposed) return;

    _startPositionStream(_currentIntervalMs);

    _isRestartingGps = false;
    _lastRawPositionTs = DateTime.now();
    _safeNotify();

    debugPrint('GPS RESTART completato');
  }

  /// Riavvio manuale dello stream GPS, richiamabile dalla UI (tap sul
  /// banner "GPS bloccato") come ultima risorsa se il riavvio automatico
  /// del watchdog non ha funzionato.
  Future<void> attemptGpsRestart() => _attemptGpsRestart();

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
    _lastAcceptedFilteredPos = null;
    _lastFilteredTs = null;
    _geometricSpeedKmh = 0.0;
    _recentFilteredPoints.clear();
    _bearingDeg = 0.0;
    _recoveryAttempted.clear();
    _endRecoveryAttempted.clear();
    _waypointDetector.reset();
    _trackPoints.clear();
    _displayAnchor = null;
    _recoveryTrack.clear();
    _recoveryTimestamps.clear();
    _alertedDangerPoints.clear();
    _warningDangerPoint = null;
    _warningDangerDistance = null;
    _alertDangerPoint = null;
    _alertDangerDistance = null;
    _dangerBlinking = false;
    _freezeDetectionTimer?.cancel();
    _freezeDetectionTimer = null;
    _isGpsFrozen = false;
    _isRestartingGps = false;
    _lastRawPositionTs = null;
    _imu.stop();
    WakelockPlus.disable().ignore();
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _freezeDetectionTimer?.cancel();
    _posStreamCtrl.close();
    _recoveryStreamCtrl.close();
    _fuelPointStreamCtrl.close();
    _dangerPassedStreamCtrl.close();
    super.dispose();
  }
}
