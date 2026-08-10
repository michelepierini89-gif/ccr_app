import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/waypoint_model.dart';
import '../models/gps_point_model.dart';
import '../models/special_model.dart';
import '../constants/app_constants.dart';
import '../services/waypoint_detector.dart';
import '../services/battery_setup_service.dart';
import '../services/diagnostic_logger.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue_service.dart';
import '../services/gnss_status_service.dart';
import '../services/imu_fusion_service.dart';
import '../services/track_smoother.dart';
import '../services/voice_alert_service.dart';
import '../utils/kalman_filter.dart';

enum GpsMode { idle, transfer, inSpecial, nearWaypoint }

/// Fix 1 — Esito della regola di precedenza esplicita tra metodi di timing
/// (vedi `timingMethodRank` in waypoint_detector.dart): [timestamp] e
/// [timingMethod] sono il valore da usare per il waypoint, [usedExisting] è
/// true quando un passaggio già noto (di precedenza pari o superiore) ha
/// prevalso sul candidato proposto in questa chiamata — segnale di "porta
/// orfana" (Fix 2) quando chi chiama è una recovery.
typedef PassageResolution = ({
  DateTime timestamp,
  String timingMethod,
  bool usedExisting,
});

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

  // Fix 4 — oltre questo intervallo tra i due fix filtrati che delimitano
  // un attraversamento porta, il segmento è "a cavallo di un gap": la
  // porta viene comunque registrata (l'interpolazione lineare resta il
  // miglior dato disponibile), ma con timingMethod 'gate_gap' invece di
  // 'gate', per segnalare all'admin che il tempo è meno affidabile.
  static const int kGateGapThresholdMs = 2000;

  // Bearing: sotto questa velocità geometrica il bearing resta congelato
  // (evita jitter della freccia da fermo); sopra, smoothing esponenziale.
  static const double kMinBearingSpeedKmh = 3.0;
  static const double kBearingSmoothingAlpha = 0.4;

  // Distanza minima (m) tra due fix consecutivi richiesta da Geolocator,
  // fissa per tutte le modalità — 0 causava l'accettazione di ogni
  // scatter GPS come punto valido (pattern a ventaglio).
  static const int kDistanceFilterMeters = 2;

  // Blocco C4 (Parte 3 — ora impostazione utente invece di costante di
  // compilazione): FusedLocationProviderClient (default, forceLocationManager
  // false) applica una propria fusione/smoothing di Google Play Services che
  // si somma al nostro Kalman + IMU, potenzialmente aggiungendo lag. true
  // forza il LocationManager grezzo di Android (nessuna fusione Google prima
  // del nostro filtro) — persistito in SharedPreferences, così si può
  // confrontare sul campo senza ricompilare.
  static const String kUseRawLocationManagerPrefsKey =
      'gps_use_raw_location_manager';

  final FirestoreService _firestoreService;
  final OfflineQueueService _offlineQueue;
  final ImuFusionService _imu;
  final GnssStatusService? _gnssStatus;
  final VoiceAlertService? _voiceAlerts;
  final DiagnosticLogger? _diagLogger;
  final SharedPreferences? _prefs;

  bool _useRawLocationManager;
  bool get useRawLocationManager => _useRawLocationManager;

  GpsService(this._firestoreService, this._offlineQueue, this._imu,
      [this._gnssStatus, this._voiceAlerts, this._diagLogger, this._prefs])
      : _useRawLocationManager =
            _prefs?.getBool(kUseRawLocationManagerPrefsKey) ?? false;

  /// Cambia il provider GPS grezzo/fuso (Parte 3). Se la registrazione è
  /// attiva riavvia subito lo stream con le nuove impostazioni; altrimenti
  /// il valore persistito si applica al prossimo `startRecording()`.
  Future<void> setUseRawLocationManager(bool value) async {
    if (_useRawLocationManager == value) return;
    _useRawLocationManager = value;
    await _prefs?.setBool(kUseRawLocationManagerPrefsKey, value);
    if (_isRecording) {
      _diagLogger?.logLifecycle(
          'gps_provider_changed', [value ? 'raw' : 'fused']);
      _startPositionStream(_currentIntervalMs);
    }
    _safeNotify();
  }

  // Blocco C3: quando GnssStatusService segnala qualità CRITICA (<5
  // satelliti usati), il campo accuracy dichiarato dal chip resta
  // ottimistico — questo fattore gonfia l'accuracy effettiva usata da
  // filtri e Kalman, alzando la diffidenza anche verso fix che si
  // dichiarano precisi. 1.0 = nessun effetto (piattaforme non Android, o
  // GnssStatusService non ancora iniziato/quality non critica).
  static const double _kCriticalGnssDistrustFactor = 2.0;

  double _effectiveAccuracy(double declaredAccuracy) {
    if (_gnssStatus?.lastSnapshot?.quality == GnssQuality.critica) {
      return declaredAccuracy * _kCriticalGnssDistrustFactor;
    }
    return declaredAccuracy;
  }

  /// Servizio di fusione IMU (giroscopio + accelerometro + bussola) usato
  /// SOLO per il display a 50Hz (freccia, polyline live, velocità UI).
  /// MAI per waypoint detection, timing PS o recovery.
  ImuFusionService get imu => _imu;

  final StreamController<Position> _posStreamCtrl =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _posStreamCtrl.stream;

  bool _isRecording = false;
  // Parte 1 — banco di replay: true SOLO durante una sessione avviata da
  // [startReplaySession], mai durante una registrazione live. Guarda
  // [_startPositionStream] per evitare di toccare il Geolocator reale
  // quando la pipeline sta rigiocando campioni forniti esplicitamente.
  bool _replayMode = false;
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

  // Fix 1 (09/08/2026) — checkpoint su traiettoria: _waypoints è diviso in
  // due liste disgiunte, ricostruite ad ogni _resetSessionState. I
  // checkpoint (SpecialModel.controlPoints) usano SOLO
  // WaypointDetector.detectCheckpointPassage (segmento, no doppia
  // conferma); tutto il resto (inizio/fine PS, zone velocità) resta sul
  // percorso esistente porta+raggio con doppia conferma. _cpMinDistance/
  // _cpMinDistanceMethod tracciano, per ogni checkpoint non ancora passato,
  // la distanza minima vista finora e il metodo con cui è stata misurata —
  // usati per il log diagnostico di fine sessione (Parte 5), indipendente
  // dal fatto che il CP sia stato agganciato o meno.
  List<WaypointModel> _checkpointWaypoints = [];
  List<WaypointModel> _nonCheckpointWaypoints = [];
  final Map<String, double> _cpMinDistance = {};
  final Map<String, String> _cpMinDistanceMethod = {};

  // Fix 4 — polyline di riferimento tenuta anche dopo attachGates (che la
  // usa solo transitoriamente): serve a stimare la distanza tra un cluster
  // di jump scartati e il percorso atteso (vedi _flushJumpCluster).
  List<LatLng> _referenceTrack = const [];

  // Zone a velocità controllata: i punti di inizio/fine sono iniettati in
  // _waypoints come WaypointType.intermedio sintetici (riusano la doppia
  // conferma di WaypointDetector) e mappati qui all'id della zona.
  List<SpeedZoneModel> _speedZones = [];
  final Map<String, String> _zoneStartToZone = {};
  final Map<String, String> _zoneEndToZone = {};
  final Map<String, DateTime> _zoneEntryTimestamps = {};
  // Raggio di detection più ampio (AppConstants.speedZoneRadiusMeters) per
  // inizio/fine zona velocità: una mancata conferma dell'uscita blocca il
  // banner live per il resto della sessione, un rischio peggiore di una
  // precisione minore sul punto esatto (qui non c'è alcun impatto sul
  // timing PS, solo sul calcolo della velocità media nella zona).
  final Map<String, double> _zoneRadiusOverrides = {};
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

  // Fix 1/2 — registro del passaggio più affidabile finora noto per ogni
  // waypoint gated (inizio/fine PS, zone velocità), a prescindere da
  // quando/se la SpecialEntry corrispondente è aperta. È il meccanismo che
  // impedisce a un fallback (raggio/recovery/forfait) di sovrascrivere un
  // attraversamento porta già rilevato, ed è anche il modo in cui un
  // attraversamento "orfano" (porta di fine rilevata mentre la speciale non
  // risultava aperta) sopravvive fino a quando la speciale viene chiusa da
  // un altro meccanismo — vedi _registerPassage.
  final Map<String,
      ({DateTime timestamp, String timingMethod, double? distanceMeters})>
      _bestPassageByWaypoint = {};
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
  // Accuracy (metri) del fix raw corrispondente a ogni punto di
  // _recoveryTrack — mantenuta in parallelo solo per alimentare
  // TrackSmoother (Blocco B) col ricalcolo post-gara: il forward pass RTS
  // ha bisogno del rumore di misura reale di ogni campione, non di un
  // valore costante assunto a posteriori.
  final List<double> _recoveryAccuracies = [];

  // Kalman 4D filter (kinematic: position + velocity) + accuracy filtering
  final GpsKalmanFilter _kalmanFilter =
      GpsKalmanFilter(sigmaAccel: GpsKalmanFilter.kSigmaAccelMotorcycle);
  int _consecutiveDiscarded = 0;
  LatLng? _filteredPosition;

  // Geometric jump filter state (raw points, before Kalman)
  LatLng? _lastAcceptedRawPos;
  DateTime? _lastAcceptedTs;

  // Fix 4 — posizioni scartate dal filtro jump da quando è stato accettato
  // l'ultimo fix, usate per riassumere il cluster (dimensione + posizione
  // media + scarto dalla traccia di riferimento) al prossimo fix accettato:
  // distingue un multipath sostenuto (più scarti ravvicinati e sistematici)
  // dal rumore isolato (un singolo scarto).
  final List<LatLng> _jumpClusterBuffer = [];

  // Doppia conferma waypoint: protegge la rilevazione PS dai ghost points.
  final WaypointDetector _waypointDetector = WaypointDetector();

  // Geometric speed (between consecutive filtered points) + bearing state
  LatLng? _lastAcceptedFilteredPos;
  DateTime? _lastFilteredTs;
  double _geometricSpeedKmh = 0.0;
  final List<LatLng> _recentFilteredPoints = []; // circular buffer, last 5
  double _bearingDeg = 0.0;

  // Special-start recovery
  // 120m (era 80m): raggio aumentato dopo il test in cui una PS saltata
  // interamente (segnale debole sul suo waypoint START) non veniva mai
  // recuperata, bloccando FINE GARA — vedi anche _tryRecoverSkippedSpecials.
  static const double kSpecialStartRecoveryRadiusMeters = 120.0;
  static const int kSpecialStartRecoveryLookbackSeconds = 30;
  final Set<String> _recoveryAttempted = {};
  final StreamController<String> _recoveryStreamCtrl =
      StreamController<String>.broadcast();

  // Special-end recovery (recovery retroattivo della fine PS, speculare
  // al recovery dell'inizio sopra)
  // 120m (era 80m), stesso motivo del raggio start sopra.
  static const double kSpecialEndRecoveryRadiusMeters = 120.0;
  static const int kSpecialEndRecoveryLookbackSeconds = 30;
  final Set<String> _endRecoveryAttempted = {};

  // Fuel point ("punto ristoro") passage notifications
  final StreamController<String> _fuelPointStreamCtrl =
      StreamController<String>.broadcast();

  // _lastRawPositionTs è aggiornato ad OGNI posizione ricevuta (valida o
  // scartata dai filtri), per distinguere "GPS che non manda più nulla" da
  // "GPS che manda solo punti scartati". Usato solo per decidere quando
  // mostrare il pulsante manuale "Ripristina GPS" — nessun controllo
  // periodico, nessun riavvio automatico: solo il pilota decide se e
  // quando riavviare lo stream.
  DateTime? _lastRawPositionTs;
  bool _isRestartingGps = false;
  int _currentIntervalMs = AppConstants.gpsIntervalTransferMs;

  /// Soglia di inattività GPS oltre la quale il pulsante manuale
  /// "Ripristina GPS" diventa visibile in UI.
  static const int kGpsStaleSeconds = 30;

  // Le scritture Firestore del live tracking sono throttlate
  // indipendentemente dalla cadenza dei fix GPS (che resta piena per
  // Kalman/waypoint detection/polyline locale): la mappa live admin non ha
  // bisogno di più di un aggiornamento ogni 2s, mentre la cadenza GPS in
  // modalità inSpecial/nearWaypoint arriva fino a 4Hz (250ms) — senza
  // questo limite si arriverebbe a migliaia di scritture/ora per pilota.
  static const int kFirestoreUpdateIntervalMs = 2000;
  DateTime? _lastFirestoreUpdateTs;

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

  /// Fix 1/2 — metodo di timing vincente per [waypointId] secondo il
  /// registro di precedenza (`_bestPassageByWaypoint`): riflette il dato
  /// EFFETTIVAMENTE usato per l'ingresso/uscita PS, anche quando è stato
  /// scritto da una recovery che ha trovato — e usato — una porta orfana
  /// invece del proprio ricalcolo. Null se il waypoint non ha ancora alcun
  /// passaggio registrato in questa sessione.
  String? timingMethodFor(String waypointId) =>
      _bestPassageByWaypoint[waypointId]?.timingMethod;

  /// Distanza (metri) dal waypoint del passaggio vincente per [waypointId],
  /// se disponibile (popolata solo per porta/recovery con ricerca a
  /// distanza, non per le stime a tempo fisso).
  double? passageDistanceFor(String waypointId) =>
      _bestPassageByWaypoint[waypointId]?.distanceMeters;
  DateTime? get recordingStart => _recordingStart;
  Duration get elapsed => _recordingStart != null
      ? DateTime.now().difference(_recordingStart!)
      : Duration.zero;
  List<WaypointModel> get remainingWaypoints =>
      _waypoints.where((w) => !_passedWaypoints.contains(w.id)).toList();

  /// Fix 1 — true se [waypointId] risulta passato in questa sessione. Usato
  /// dal banco di replay per contare i checkpoint agganciati per pilota
  /// (Parte 1, confronto prima/dopo il fix del rilevamento su traiettoria).
  bool isWaypointPassed(String waypointId) =>
      _passedWaypoints.contains(waypointId);

  /// Traccia grezza completa (posizione Kalman-filtrata + accuracy raw +
  /// timestamp) della sessione corrente, un campione per ogni fix
  /// accettato — usata per il ricalcolo post-gara (Blocco B,
  /// [TrackSmoother]). Va letta PRIMA di [stopRecording] (che azzera i
  /// buffer sottostanti), come già fatto per [localTrack].
  List<RawTrackSample> get fullTrackSamples => List.generate(
        _recoveryTrack.length,
        (i) => RawTrackSample(
          lat: _recoveryTrack[i].latitude,
          lng: _recoveryTrack[i].longitude,
          accuracy: _recoveryAccuracies[i],
          timestamp: _recoveryTimestamps[i],
        ),
      );

  /// Etichetta specifica del waypoint più vicino in modalità nearWaypoint
  /// (es. "Inizio PS1", "Fine PS3", "Checkpoint PS2"), o null se non
  /// disponibile — usata per sostituire il generico "WAYPOINT VICINO".
  String? get nearestWaypointLabel => _nearestWaypointLabel;
  String? _nearestWaypointLabel;

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

  /// Timestamp dell'ultimo fix GPS accettato (passato accuracy + jump
  /// filter) — usato per il contatore nella notifica persistente (Parte 5)
  /// e per [isGpsStale].
  DateTime? get lastAcceptedFixTime => _lastAcceptedTs;

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

  /// Zona a velocità controllata in cui il pilota si trova attualmente
  /// (tra l'ingresso e l'uscita), o null se non è in nessuna zona. Usata
  /// per il banner live di velocità — a differenza della violazione (solo
  /// admin, calcolata all'uscita zona), questo è solo un indicatore
  /// informativo per il pilota durante la guida.
  SpeedZoneModel? get activeSpeedZone {
    if (_zoneEntryTimestamps.isEmpty) return null;
    final zoneId = _zoneEntryTimestamps.keys.first;
    return _speedZones.where((z) => z.id == zoneId).firstOrNull;
  }

  /// IDs dei punti pericolo già superati (entro 15m) in questa sessione.
  Set<String> get passedDangerPoints => Set.unmodifiable(_passedDangerPoints);

  /// Emette un messaggio quando un punto pericolo viene superato per la
  /// prima volta in questa sessione (mostrare una SnackBar verde, 2s).
  Stream<String> get dangerPassedStream => _dangerPassedStreamCtrl.stream;

  /// True se non arriva nessuna posizione GPS (valida o no) da almeno
  /// [kGpsStaleSeconds] secondi durante una registrazione attiva E il
  /// pilota era in movimento. Da fermo è normale ricevere pochi update
  /// (distanceFilter li scarta), quindi non segnalare stale.
  bool get isGpsStale {
    if (!_isRecording) return false;
    // Da fermo (<2 km/h) il distanceFilter scarta i fix: non è un problema.
    if (_geometricSpeedKmh < 2.0) return false;
    final reference = _lastRawPositionTs ?? _recordingStart;
    if (reference == null) return false;
    return DateTime.now().difference(reference).inSeconds >= kGpsStaleSeconds;
  }

  /// True durante il riavvio manuale dello stream GPS (richiesto dal pilota).
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
    if (_geometricSpeedKmh > 60) return 1.5;
    if (_geometricSpeedKmh > 20) return 2.5;
    if (_geometricSpeedKmh > 5) return 4.0;
    return 3.0;
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
  /// Crea una [SpecialEntry] solo se [specialeId] corrisponde a una speciale
  /// realmente presente in [_specials] (la lista caricata dall'admin per
  /// l'evento corrente). Nessun percorso di recovery può quindi inventare
  /// una PS con id/nome arbitrario: se la speciale non esiste più (es.
  /// cancellata lato admin dopo che i waypoint erano già stati caricati),
  /// non viene creato nulla e viene solo loggato un warning di debug.
  /// Numero progressivo (1-based) di [specialId] tra le speciali non
  /// annullate, ordinate per `ordine` — usato solo per comporre gli
  /// annunci vocali ("prova speciale N", Blocco D4).
  int _specialNumero(String specialId) {
    final ordered = _specials.where((s) => !s.annullata).toList()
      ..sort((a, b) => a.ordine.compareTo(b.ordine));
    final idx = ordered.indexWhere((s) => s.id == specialId);
    return idx >= 0 ? idx + 1 : 1;
  }

  void _addSpecialEntry({
    required String specialeId,
    required DateTime entryTime,
    bool recoveredStart = false,
  }) {
    final special = _specials.where((s) => s.id == specialeId).firstOrNull;
    if (special == null) {
      debugPrint(
          'SPECIAL ENTRY SCARTATA: nessuna speciale con id $specialeId in _specials');
      return;
    }
    assert(_specials.any((s) => s.id == specialeId));
    _specialEntries.add(SpecialEntry(
      specialeId: special.id,
      specialeNome: special.nome,
      entryTime: entryTime,
      recoveredStart: recoveredStart,
    ));
  }

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

      // Fix 1 — non sovrascrivere un passaggio già noto più preciso (in
      // pratica qui il candidato vince quasi sempre, dato che il guard
      // _passedWaypoints sopra impedisce di arrivarci due volte per lo
      // stesso waypoint — instradato comunque per coerenza col resto della
      // pipeline).
      final resolution = _registerPassage(
          inizioId, recoveredTime, 'recovery',
          candidateDistanceMeters: bestDistM);
      final entryTime = resolution.timestamp;

      // Register inizio waypoint as passed to block double-detection
      _passedWaypoints.add(inizioId);
      _passages.add(
          WaypointPassage(waypoint: special.waypointInizio, timestamp: entryTime));

      // Open the special with the recovered entry time
      _currentSpecialId = special.id;
      _currentSpecialNome = special.nome;
      _addSpecialEntry(
        specialeId: special.id,
        entryTime: entryTime,
        recoveredStart: true,
      );

      // Notify the UI
      _recoveryStreamCtrl.add('⚡ Inizio ${special.nome} recuperato');
      _diagLogger?.logRecovery(special.id, 'inizio_speciale');

      // Persist in Firestore with recoveredStart flag so admins can review it
      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: inizioId,
            waypointNome: special.waypointInizio.nome,
            timestamp: entryTime,
            recoveredStart: true,
            timingMethod: resolution.timingMethod,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: inizioId,
            waypointNome: special.waypointInizio.nome,
            timestamp: entryTime,
            timingMethod: resolution.timingMethod,
          );
        }
      }
    }
  }

  /// Recupera retroattivamente speciali precedenti a [nextSpecial] (per
  /// `ordine`) che non hanno NESSUN passaggio registrato — non solo "fine non
  /// rilevata" (vedi lo stale-close in [_handleWaypointDetection]), ma
  /// "mai avviata", tipicamente perché il segnale GPS era troppo debole
  /// vicino al suo waypoint START e [_trySpecialStartRecovery] non è mai
  /// scattato (richiede di passare entro 3× il raggio di recovery).
  ///
  /// Chiamato PRIMA di aprire l'ingresso di [nextSpecial], così le speciali
  /// restano sempre in ordine corretto. Esamina ogni speciale precedente (in
  /// ordine decrescente): quelle con già un passaggio registrato vengono
  /// saltate (possono non essere adiacenti — es. PS2 mai avviata e PS3
  /// avviata normalmente ma non chiusa, prima di PS4), le altre vengono
  /// recuperate. Per ciascuna speciale saltata: cerca nell'INTERA traccia di
  /// recovery della sessione (non un'ultima finestra di secondi)
  /// il punto più vicino al waypoint START, poi — usando quel timestamp come
  /// nuovo inizio — il punto più vicino al waypoint FINE nella finestra da
  /// quell'inizio a [nextStartTs]. Se uno dei due non viene trovato entro
  /// [kSpecialStartRecoveryRadiusMeters]/[kSpecialEndRecoveryRadiusMeters],
  /// usa un fallback a tempo stimato e marca `timingError:
  /// 'speciale_non_rilevata'` per la verifica admin — mai bloccare FINE GARA.
  Future<void> _tryRecoverSkippedSpecials(
      SpecialModel nextSpecial, DateTime nextStartTs) async {
    final ordered = _specials.where((s) => !s.annullata).toList()
      ..sort((a, b) => a.ordine.compareTo(b.ordine));
    final nextIdx = ordered.indexWhere((s) => s.id == nextSpecial.id);
    if (nextIdx <= 0) return;

    for (int i = nextIdx - 1; i >= 0; i--) {
      if (_disposed) return;
      final prev = ordered[i];
      // Non break: due speciali non adiacenti possono essere entrambe
      // saltate (es. PS2 mai avviata, PS3 avviata normalmente ma con fine
      // non rilevata, PS4 in arrivo) — ognuna va valutata indipendentemente.
      if (_specialEntries.any((e) => e.specialeId == prev.id)) continue;

      final startWp = prev.waypointInizio;
      final startPt = LatLng(startWp.lat, startWp.lng);
      double bestStartDistM = double.infinity;
      int bestStartIdx = -1;
      for (int j = 0; j < _recoveryTrack.length; j++) {
        final d = _haversineKm(_recoveryTrack[j], startPt) * 1000.0;
        if (d < bestStartDistM) {
          bestStartDistM = d;
          bestStartIdx = j;
        }
      }

      final bool recoveredStart =
          bestStartIdx >= 0 && bestStartDistM < kSpecialStartRecoveryRadiusMeters;
      // Fix 1 — 'recovery' se un punto reale è stato trovato entro il
      // raggio, 'forfait' se si tratta di una stima a tempo (nessun dato
      // GPS a supporto): precedenza più bassa, così un dato migliore
      // trovato altrove (es. una porta orfana) non viene mai scartato a
      // favore di una pura stima.
      final startCandidateMethod = recoveredStart ? 'recovery' : 'forfait';
      final startCandidateTs = recoveredStart
          ? _recoveryTimestamps[bestStartIdx]
          : nextStartTs.subtract(const Duration(minutes: 2));
      final startResolution = _registerPassage(
          startWp.id, startCandidateTs, startCandidateMethod,
          candidateDistanceMeters: recoveredStart ? bestStartDistM : null);
      final entryTime = startResolution.timestamp;

      debugPrint('RECOVERY SKIPPED speciale ${prev.id}: '
          'inizio ${recoveredStart ? "recuperato" : "stimato"} a $entryTime');

      _passedWaypoints.add(startWp.id);
      _passages.add(WaypointPassage(waypoint: startWp, timestamp: entryTime));
      final entriesBefore = _specialEntries.length;
      _addSpecialEntry(
        specialeId: prev.id,
        entryTime: entryTime,
        recoveredStart: recoveredStart,
      );
      if (_specialEntries.length == entriesBefore) continue;
      _recoveryAttempted.add(prev.id);

      // Recovery immediato anche della fine, nella finestra da entryTime a
      // nextStartTs (l'intera durata della speciale saltata).
      final endWp = prev.waypointFine;
      final endPt = LatLng(endWp.lat, endWp.lng);
      double bestEndDistM = double.infinity;
      int bestEndIdx = -1;
      for (int j = _recoveryTrack.length - 1; j >= 0; j--) {
        if (_recoveryTimestamps[j].isBefore(entryTime)) break;
        final d = _haversineKm(_recoveryTrack[j], endPt) * 1000.0;
        if (d < bestEndDistM) {
          bestEndDistM = d;
          bestEndIdx = j;
        }
      }

      final bool recoveredEnd =
          bestEndIdx >= 0 && bestEndDistM < kSpecialEndRecoveryRadiusMeters;
      final endCandidateMethod = recoveredEnd ? 'recovery' : 'forfait';
      final endCandidateTs = recoveredEnd
          ? _recoveryTimestamps[bestEndIdx]
          : nextStartTs.subtract(const Duration(seconds: 1));
      final endResolution = _registerPassage(
          endWp.id, endCandidateTs, endCandidateMethod,
          candidateDistanceMeters: recoveredEnd ? bestEndDistM : null);
      final exitTime = endResolution.timestamp;

      // Fix 2 — se il valore vincente non è il nostro candidato fresco, è
      // perché esisteva già un passaggio migliore (tipicamente una porta
      // rilevata "a vuoto" mentre questa speciale non risultava ancora
      // aperta): segnalalo all'admin come nota, la sequenza delle speciali
      // ha avuto un'anomalia da verificare — non un errore di misura.
      final bool closedFromOrphan = endResolution.usedExisting &&
          endResolution.timingMethod != endCandidateMethod;
      final String? timingError = closedFromOrphan
          ? 'chiusura_da_porta_orfana'
          : ((recoveredStart && recoveredEnd) ? null : 'speciale_non_rilevata');

      final entryIdx = _specialEntries.length - 1;
      _specialEntries[entryIdx] = _specialEntries[entryIdx].withExit(exitTime);
      _endRecoveryAttempted.add(prev.id);
      _passedWaypoints.add(endWp.id);
      _passages.add(WaypointPassage(waypoint: endWp, timestamp: exitTime));

      _recoveryStreamCtrl.add(timingError == null
          ? '⚡ ${prev.nome} recuperata (non rilevata in tempo reale)'
          : '⚠ ${prev.nome} non rilevata — penalità automatica');
      _diagLogger?.logRecovery(prev.id, 'speciale_saltata');

      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: startWp.id,
            waypointNome: startWp.nome,
            timestamp: entryTime,
            recoveredStart: recoveredStart,
            timingMethod: startResolution.timingMethod,
          );
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
            timestamp: exitTime,
            recoveredEnd: true,
            timingError: timingError,
            timingMethod: endResolution.timingMethod,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: startWp.id,
            waypointNome: startWp.nome,
            timestamp: entryTime,
            timingMethod: startResolution.timingMethod,
          );
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
            timestamp: exitTime,
            timingMethod: endResolution.timingMethod,
          );
        }
      }
    }
  }

  /// Fix 1/2 — punto unico di scrittura nel registro [_bestPassageByWaypoint]:
  /// va chiamato da OGNI meccanismo che produce un candidato ingresso/uscita
  /// PS (rilevamento diretto, le tre recovery, la chiusura da FINE GARA, lo
  /// skip manuale) prima di scrivere effettivamente su [_specialEntries]/
  /// Firestore. Un passaggio esistente di precedenza pari o superiore a
  /// [candidateMethod] non viene mai sostituito — questo è sia la garanzia
  /// "non peggiorare mai un dato preciso" (Fix 1) sia il meccanismo con cui
  /// una porta di fine rilevata "a vuoto" (Fix 2, speciale non ancora
  /// aperta) sopravvive fino a quando qualcuno tenta di chiudere quella
  /// speciale.
  PassageResolution _registerPassage(
    String waypointId,
    DateTime candidateTs,
    String candidateMethod, {
    double? candidateDistanceMeters,
  }) {
    final existing = _bestPassageByWaypoint[waypointId];
    final candidateRank = timingMethodRank[candidateMethod] ?? 99;
    if (existing != null) {
      final existingRank = timingMethodRank[existing.timingMethod] ?? 99;
      if (existingRank <= candidateRank) {
        if (existing.timingMethod != candidateMethod ||
            existing.timestamp != candidateTs) {
          _diagLogger?.logOverwriteAvoided(
            waypointId,
            existing.timingMethod,
            existing.distanceMeters,
            candidateMethod,
            candidateDistanceMeters,
          );
        }
        return (
          timestamp: existing.timestamp,
          timingMethod: existing.timingMethod,
          usedExisting: true,
        );
      }
    }
    _bestPassageByWaypoint[waypointId] = (
      timestamp: candidateTs,
      timingMethod: candidateMethod,
      distanceMeters: candidateDistanceMeters,
    );
    return (
      timestamp: candidateTs,
      timingMethod: candidateMethod,
      usedExisting: false,
    );
  }

  /// Fix 4 — chiamato appena un fix viene accettato: se nel frattempo si
  /// erano accumulati scarti jump consecutivi, riassume il cluster (numero,
  /// posizione media, distanza tra la media e il punto più vicino della
  /// traccia di riferimento) e lo logga, poi svuota il buffer. Una distanza
  /// piccola e sistematica indica multipath sostenuto (il chip resta
  /// "agganciato" a una soluzione errata per qualche secondo); un cluster
  /// piccolo o una distanza grande e variabile indicano piuttosto rumore
  /// isolato o un vero spostamento del pilota.
  void _flushJumpCluster() {
    if (_jumpClusterBuffer.isEmpty) return;
    final count = _jumpClusterBuffer.length;
    final avgLat =
        _jumpClusterBuffer.map((p) => p.latitude).reduce((a, b) => a + b) /
            count;
    final avgLng =
        _jumpClusterBuffer.map((p) => p.longitude).reduce((a, b) => a + b) /
            count;
    double? nearestDist;
    final avgPos = LatLng(avgLat, avgLng);
    for (final rp in _referenceTrack) {
      final d = _haversineKm(avgPos, rp) * 1000.0;
      if (nearestDist == null || d < nearestDist) nearestDist = d;
    }
    _diagLogger?.logJumpCluster(count, avgLat, avgLng, nearestDist);
    _jumpClusterBuffer.clear();
  }

  /// Fix 1 — callback di [WaypointDetector.detectCheckpointPassage]:
  /// aggiorna la distanza minima vista finora per [waypointId], per il log
  /// diagnostico di fine sessione (Parte 5), a prescindere dal fatto che il
  /// CP sia stato agganciato in questa chiamata.
  void _recordCheckpointDistanceSample(
      String waypointId, double distanceMeters, String method) {
    final best = _cpMinDistance[waypointId];
    if (best == null || distanceMeters < best) {
      _cpMinDistance[waypointId] = distanceMeters;
      _cpMinDistanceMethod[waypointId] = method;
    }
  }

  /// Fix 1 — righe di log diagnostico di fine sessione per ogni checkpoint
  /// configurato in questa sessione: distanza minima raggiunta dalla
  /// traiettoria, se è stato registrato, e con quale metodo (punto o
  /// segmento) è stata misurata quella distanza minima. Chiamato sia da
  /// [stopRecording] sia da [endReplaySession] — prima che il logger venga
  /// chiuso/il replay smontato.
  void _logCheckpointDiagnostics() {
    for (final wp in _checkpointWaypoints) {
      final minDist = _cpMinDistance[wp.id];
      final method = _cpMinDistanceMethod[wp.id];
      final registered = _passedWaypoints.contains(wp.id);
      _diagLogger?.logCheckpointSummary(wp.id, minDist, registered, method);
    }
  }

  /// Registra un passaggio waypoint confermato da [WaypointDetector]:
  /// aggiorna i passaggi, l'apertura/chiusura delle speciali e persiste su
  /// Firestore (con fallback su coda offline). Usata sia per i punti che
  /// superano il filtro accuracy display, sia per i punti scartati dal
  /// display ma ancora validi per la detection (STEP 1).
  Future<void> _handleWaypointDetection(
    WaypointPassageResult detection, {
    String timingMethod = 'radius',
  }) async {
    final wp = detection.waypoint;
    final resolution = _registerPassage(
      wp.id,
      detection.timestamp,
      timingMethod,
      candidateDistanceMeters: detection.distanceMeters,
    );
    final passageTs = resolution.timestamp;
    final method = resolution.timingMethod;

    _passedWaypoints.add(wp.id);
    final passage = WaypointPassage(waypoint: wp, timestamp: passageTs);
    _passages.add(passage);

    if ((method == 'gate' || method == 'gate_gap') &&
        detection.fractionT != null &&
        detection.distanceMeters != null) {
      _diagLogger?.logGateCrossing(wp.id, detection.timestamp,
          detection.fractionT!, detection.distanceMeters!);
    } else if (method == 'radius') {
      _diagLogger?.logRadiusFallback(
          wp.id, wp.gate != null ? 'nessuna_intersezione' : 'porta_assente');
    }

    // Special entry/exit detection
    if (_inizioToSpecial.containsKey(wp.id)) {
      final specialId = _inizioToSpecial[wp.id]!;
      if (_currentSpecialId != null && _currentSpecialId != specialId) {
        // La speciale precedente non è mai stata chiusa (fine non rilevata
        // e nessun recovery opportunistico è scattato): senza questo, resta
        // aperta per sempre e blocca FINE GARA. Chiudila ora con recovery a
        // finestra ampia prima di aprire la nuova.
        final staleIdx = _specialEntries.lastIndexWhere((e) =>
            e.specialeId == _currentSpecialId && e.exitTime == null);
        if (staleIdx >= 0) {
          await _closeOpenSpecial(
              staleIdx, passageTs, passageTs, 'recovery_impreciso');
          if (_disposed) return;
        }
        _currentSpecialId = null;
        _currentSpecialNome = null;
      }
      if (_currentSpecialId == null) {
        final special = _specials.where((s) => s.id == specialId).firstOrNull;
        if (special == null) {
          // wp.id è mappato a uno specialeId non (più) presente in _specials
          // (es. speciale cancellata lato admin dopo il caricamento dei
          // waypoint): nessuna SpecialEntry va creata con id/nome arbitrario.
          debugPrint(
              'WAYPOINT INIZIO IGNORATO: speciale $specialId non trovata in _specials');
        } else {
          // Recupera eventuali speciali precedenti saltate per intero (mai
          // avviate) PRIMA di aprire questa, così l'ordine resta corretto.
          await _tryRecoverSkippedSpecials(special, passageTs);
          if (_disposed) return;
          _currentSpecialId = specialId;
          _currentSpecialNome = special.nome;
          _addSpecialEntry(specialeId: specialId, entryTime: passageTs);
          _diagLogger?.logSpecialEntry(specialId, method);
          _voiceAlerts?.announceSpecialStartCrossed(
              specialId, _specialNumero(specialId));
        }
      }
    } else if (_fineToSpecial.containsKey(wp.id)) {
      // Fix 2 — un attraversamento della porta di fine è un fatto fisico
      // misurato: va registrato SEMPRE, indipendentemente da
      // _currentSpecialId (che può essere rimasto bloccato su una speciale
      // precedente mai chiusa, es. la sua fine mai rilevata). Cerca la
      // SpecialEntry per specialId esplicitamente, non "quella aperta
      // qualunque essa sia". Se non esiste ancora (speciale non aperta), il
      // passaggio resta comunque nel registro _bestPassageByWaypoint sopra
      // come "orfano": la prossima recovery che tenta di chiudere questa
      // speciale lo troverà e lo userà al posto di un ricalcolo impreciso.
      final specialId = _fineToSpecial[wp.id]!;
      final idx = _specialEntries.lastIndexWhere(
          (e) => e.specialeId == specialId && e.exitTime == null);
      if (idx >= 0) {
        final entry = _specialEntries[idx].withExit(passageTs);
        _specialEntries[idx] = entry;
        _diagLogger?.logSpecialExit(specialId, method);
        _voiceAlerts?.announceSpecialEndCrossed(
            specialId, _specialNumero(specialId), entry.elapsed!);
        if (_currentSpecialId == specialId) {
          _currentSpecialId = null;
          _currentSpecialNome = null;
        }
      } else {
        debugPrint(
            'PORTA FINE ORFANA: speciale $specialId non ancora aperta al '
            'momento dell\'attraversamento — passaggio conservato per una '
            'chiusura successiva');
      }
    } else if (_zoneStartToZone.containsKey(wp.id)) {
      final zoneId = _zoneStartToZone[wp.id]!;
      _zoneEntryTimestamps[zoneId] = passageTs;
      final zone = _speedZones.where((z) => z.id == zoneId).firstOrNull;
      if (zone != null) {
        _voiceAlerts?.announceSpeedZoneEntry(zoneId, zone.maxSpeedKmh);
      }
    } else if (_zoneEndToZone.containsKey(wp.id)) {
      final zoneId = _zoneEndToZone[wp.id]!;
      final entryTs = _zoneEntryTimestamps.remove(zoneId);
      _checkSpeedZoneViolation(zoneId, entryTs, passageTs);
      // Fix 7 (09/08/2026) — annuncio di uscita mancante: simmetrico a
      // announceSpeedZoneEntry sopra, stessa priorità/categoria.
      _voiceAlerts?.announceSpeedZoneExit(zoneId);
    } else {
      // Nessuna delle mappe sopra: waypoint intermedio "puro", cioè un
      // checkpoint obbligatorio (non zona velocità) — Blocco D4.
      _voiceAlerts?.announceCheckpointPassed(wp.id);
    }

    if (_activeEventId != null && _activeUserId != null) {
      try {
        await _firestoreService.recordWaypointPassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: wp.id,
          waypointNome: wp.nome,
          timestamp: passage.timestamp,
          timingMethod: method,
        );
      } catch (_) {
        await _offlineQueue.queuePassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: wp.id,
          waypointNome: wp.nome,
          timestamp: passage.timestamp,
          timingMethod: method,
        );
      }
    }
  }

  /// Chiude una speciale ancora aperta (entry senza exitTime) all'indice
  /// [entryIdx] di [_specialEntries]. Cerca nel buffer [_recoveryTrack] il
  /// punto più vicino al waypoint di fine della speciale, in una finestra
  /// AMPIA che parte dall'orario di inizio della speciale stessa fino a
  /// [now] (non solo gli ultimi secondi, a differenza di
  /// [_trySpecialEndRecovery] che copre solo il caso "siamo ancora vicini
  /// alla fine"). Se trovato entro [kSpecialEndRecoveryRadiusMeters] usa
  /// quel timestamp come fine reale (recovery preciso); altrimenti chiude
  /// con [fallbackTime] e marca [fallbackTimingError] per la verifica
  /// admin, così la speciale successiva può sempre procedere e FINE GARA
  /// resta sbloccabile.
  Future<void> _closeOpenSpecial(
    int entryIdx,
    DateTime now,
    DateTime fallbackTime,
    String fallbackTimingError,
  ) async {
    final entry = _specialEntries[entryIdx];
    final special =
        _specials.where((s) => s.id == entry.specialeId).firstOrNull;
    if (special == null) return;
    final endWp = special.waypointFine;
    final endPt = LatLng(endWp.lat, endWp.lng);

    double bestDistM = double.infinity;
    int bestIdx = -1;
    for (int i = _recoveryTrack.length - 1; i >= 0; i--) {
      if (_recoveryTimestamps[i].isBefore(entry.entryTime)) break;
      final d = _haversineKm(_recoveryTrack[i], endPt) * 1000.0;
      if (d < bestDistM) {
        bestDistM = d;
        bestIdx = i;
      }
    }

    final bool foundPrecise =
        bestIdx >= 0 && bestDistM < kSpecialEndRecoveryRadiusMeters;
    // Fix 1 — 'recovery' se un punto reale è stato trovato entro il raggio,
    // 'forfait' se si tratta di una stima a tempo fisso (nessun dato GPS a
    // supporto).
    final candidateMethod = foundPrecise ? 'recovery' : 'forfait';
    final candidateTs = foundPrecise ? _recoveryTimestamps[bestIdx] : fallbackTime;
    final resolution = _registerPassage(endWp.id, candidateTs, candidateMethod,
        candidateDistanceMeters: foundPrecise ? bestDistM : null);
    final exitTime = resolution.timestamp;

    // Fix 2 — se un passaggio già noto (tipicamente una porta rilevata "a
    // vuoto" mentre questa speciale non risultava ancora aperta) ha vinto
    // sul nostro candidato, usalo e segnalalo come nota invece che come
    // stima grezza: è più preciso, non meno.
    final closedFromOrphan =
        resolution.usedExisting && resolution.timingMethod != candidateMethod;
    String? timingError;
    if (closedFromOrphan) {
      timingError = 'chiusura_da_porta_orfana';
      debugPrint('RECOVERY END (finestra ampia) speciale ${special.id}: '
          'porta orfana già registrata usata al posto della ricerca a raggio');
      _recoveryStreamCtrl.add('⚡ Fine ${special.nome} recuperata (porta)');
      _diagLogger?.logRecovery(special.id, 'chiusura_da_porta_orfana');
    } else if (foundPrecise) {
      debugPrint('RECOVERY END (finestra ampia) speciale ${special.id}: '
          'fine retroattiva a $exitTime (dist: ${bestDistM.toStringAsFixed(1)}m)');
      _recoveryStreamCtrl.add('⚡ Fine ${special.nome} recuperata');
      _diagLogger?.logRecovery(special.id, 'chiusura_speciale_precisa');
    } else {
      timingError = fallbackTimingError;
      debugPrint('RECOVERY END (finestra ampia) speciale ${special.id}: '
          'nessun punto entro ${kSpecialEndRecoveryRadiusMeters}m, '
          'chiusa con stima ($fallbackTimingError)');
      _diagLogger?.logRecovery(special.id, 'chiusura_speciale_stimata:$fallbackTimingError');
      _recoveryStreamCtrl
          .add('⚠ Fine ${special.nome} stimata — verifica admin');
    }

    _specialEntries[entryIdx] = entry.withExit(exitTime);
    if (_currentSpecialId == special.id) {
      _currentSpecialId = null;
      _currentSpecialNome = null;
    }
    _endRecoveryAttempted.add(special.id);
    _passedWaypoints.add(endWp.id);
    _passages.add(WaypointPassage(waypoint: endWp, timestamp: exitTime));

    if (_activeEventId != null && _activeUserId != null) {
      try {
        await _firestoreService.recordWaypointPassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: endWp.id,
          waypointNome: endWp.nome,
          timestamp: exitTime,
          recoveredEnd: true,
          timingError: timingError,
          timingMethod: resolution.timingMethod,
        );
      } catch (_) {
        await _offlineQueue.queuePassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: endWp.id,
          waypointNome: endWp.nome,
          timestamp: exitTime,
          timingMethod: resolution.timingMethod,
        );
      }
    }
  }

  /// Chiude tutte le speciali ancora aperte (FIX 6): chiamato da FINE GARA
  /// quando il pilota è tornato vicino al punto di partenza senza aver
  /// chiuso regolarmente tutte le PS. Nessun effetto sulle speciali già
  /// concluse normalmente. Va chiamato PRIMA di [blockFurtherWrites]/
  /// [stopRecording], perché usa [_recoveryTrack] e l'accesso a Firestore
  /// ancora attivi.
  Future<void> closeAllOpenSpecialsForFineGara() =>
      closeAllOpenSpecialsAt(DateTime.now());

  /// Stessa logica di [closeAllOpenSpecialsForFineGara], con [now] esplicito
  /// invece di `DateTime.now()` — usato anche a fine replay (Parte 1) per
  /// chiudere PS ancora aperte al timestamp dell'ultimo campione rigiocato.
  Future<void> closeAllOpenSpecialsAt(DateTime now) async {
    for (int i = 0; i < _specialEntries.length; i++) {
      if (_disposed) return;
      if (_specialEntries[i].exitTime != null) continue;
      await _closeOpenSpecial(i, now, now, 'chiusa_da_FINE_GARA');
    }
  }

  /// Calcola la velocità media nella zona [zoneId] tra [entryTs] e [exitTs]
  /// e, se supera il limite, persiste una [SpeedZoneViolation] su Firestore.
  /// Best-effort e silenzioso: il pilota non viene mai avvisato, lo scopre
  /// solo dalla classifica (penalità applicata da ClassificaEngine).
  void _checkSpeedZoneViolation(
      String zoneId, DateTime? entryTs, DateTime exitTs) {
    if (entryTs == null || !exitTs.isAfter(entryTs)) return;
    final zone = _speedZones.where((z) => z.id == zoneId).firstOrNull;
    if (zone == null) return;
    if (_activeEventId == null || _activeUserId == null) return;

    final elapsedSeconds = exitTs.difference(entryTs).inMilliseconds / 1000.0;
    final avgSpeedKmh = (zone.lengthMeters / elapsedSeconds) * 3.6;
    if (avgSpeedKmh <= zone.maxSpeedKmh) return;

    _firestoreService
        .recordSpeedZoneViolation(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          zoneId: zone.id,
          avgSpeedKmh: avgSpeedKmh,
          limitKmh: zone.maxSpeedKmh,
          timestamp: exitTs,
        )
        .catchError((_) {});
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

      // Fix 1 — non sovrascrivere un passaggio già noto più preciso (Fix 2:
      // può essere una porta orfana rilevata prima che questa speciale
      // risultasse ancora aperta).
      final resolution = _registerPassage(
          endWp.id, recoveredTime, 'recovery',
          candidateDistanceMeters: bestDistM);
      final exitTime = resolution.timestamp;
      final closedFromOrphan =
          resolution.usedExisting && resolution.timingMethod != 'recovery';

      // Registra fine PS retroattiva
      _specialEntries[entryIdx] = _specialEntries[entryIdx].withExit(exitTime);
      if (_currentSpecialId == special.id) {
        _currentSpecialId = null;
        _currentSpecialNome = null;
      }
      _passedWaypoints.add(endWp.id);
      _passages.add(WaypointPassage(waypoint: endWp, timestamp: exitTime));

      debugPrint('RECOVERY END speciale ${special.id}: '
          'fine retroattiva a $exitTime '
          '(dist: ${bestDistM.toStringAsFixed(1)}m)');

      _recoveryStreamCtrl.add('⚡ Fine ${special.nome} recuperata');
      _diagLogger?.logRecovery(special.id,
          closedFromOrphan ? 'chiusura_da_porta_orfana' : 'fine_speciale_retroattiva');

      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
            timestamp: exitTime,
            recoveredEnd: true,
            timingError: closedFromOrphan ? 'chiusura_da_porta_orfana' : null,
            timingMethod: resolution.timingMethod,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: endWp.id,
            waypointNome: endWp.nome,
            timestamp: exitTime,
            timingMethod: resolution.timingMethod,
          );
        }
      }
    }
  }

  /// Salta volontariamente la PS corrente (o la prima non ancora avviata).
  /// Registra inizio e fine con [timingError: 'speciale_saltata'] su
  /// Firestore: ClassificaEngine applicherà la penalità forfettaria.
  Future<void> skipCurrentSpecial() async {
    final now = DateTime.now();

    SpecialModel? toSkip;
    if (_currentSpecialId != null) {
      toSkip = _specials.where((s) => s.id == _currentSpecialId).firstOrNull;
    } else {
      final ordered = _specials.where((s) => !s.annullata).toList()
        ..sort((a, b) => a.ordine.compareTo(b.ordine));
      for (final s in ordered) {
        if (!_passedWaypoints.contains(s.waypointInizio.id)) {
          toSkip = s;
          break;
        }
      }
    }
    if (toSkip == null) return;

    final startWp = toSkip.waypointInizio;
    final endWp = toSkip.waypointFine;
    final startTs = now.subtract(const Duration(seconds: 1));

    // Marca tutti i waypoint della speciale come passati
    _passedWaypoints.add(startWp.id);
    _passedWaypoints.add(endWp.id);
    for (final cp in toSkip.controlPoints) {
      _passedWaypoints.add(cp.id);
    }

    // Apri e chiudi la SpecialEntry con flag skipped
    final entryIdx = _specialEntries.lastIndexWhere(
        (e) => e.specialeId == toSkip!.id && e.exitTime == null);
    final DateTime entryTime;
    if (entryIdx >= 0) {
      entryTime = _specialEntries[entryIdx].entryTime;
      _specialEntries[entryIdx] = _specialEntries[entryIdx].withExit(now);
    } else {
      entryTime = startTs;
      _addSpecialEntry(specialeId: toSkip.id, entryTime: entryTime);
      if (_specialEntries.isNotEmpty) {
        _specialEntries[_specialEntries.length - 1] =
            _specialEntries.last.withExit(now);
      }
    }

    _currentSpecialId = null;
    _currentSpecialNome = null;

    _passages.add(WaypointPassage(waypoint: startWp, timestamp: entryTime));
    _passages.add(WaypointPassage(waypoint: endWp, timestamp: now));

    // Skip manuale: azione esplicita del pilota/admin, non un fallback
    // automatico — non passa dalla regola di precedenza di _registerPassage
    // (che qui vincolerebbe uno 'skip' a non poter mai sostituire un dato
    // migliore già noto: questa azione deve invece avere sempre effetto
    // quando richiesta esplicitamente). Il registro viene comunque
    // aggiornato direttamente per restare coerente con eventuali letture
    // future.
    _bestPassageByWaypoint[startWp.id] =
        (timestamp: entryTime, timingMethod: 'forfait', distanceMeters: null);
    _bestPassageByWaypoint[endWp.id] =
        (timestamp: now, timingMethod: 'forfait', distanceMeters: null);

    if (_activeEventId != null && _activeUserId != null) {
      try {
        await _firestoreService.recordWaypointPassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: startWp.id,
          waypointNome: startWp.nome,
          timestamp: entryTime,
          timingError: 'speciale_saltata',
          timingMethod: 'forfait',
        );
        await _firestoreService.recordWaypointPassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: endWp.id,
          waypointNome: endWp.nome,
          timestamp: now,
          timingError: 'speciale_saltata',
          timingMethod: 'forfait',
        );
      } catch (_) {
        await _offlineQueue.queuePassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: endWp.id,
          waypointNome: endWp.nome,
          timestamp: now,
          timingMethod: 'forfait',
        );
      }
    }

    _recoveryStreamCtrl.add('⏭ ${toSkip.nome} saltata — penalità applicata');
    _diagLogger?.logRecovery(toSkip.id, 'salto_manuale');
    _safeNotify();
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

  /// Reset dello stato di sessione (specials/waypoints/porte virtuali,
  /// punti pericolo/ristoro/zone velocità, buffer Kalman/recovery/display) —
  /// condiviso da [startRecording] (sessione live) e [startReplaySession]
  /// (Parte 1, banco di replay): stessa identica logica, nessuna
  /// duplicazione. Non tocca `_activeEventId`/`_activeUserId`/`_writesBlocked`
  /// (identità di sessione, solo live) né alcun side-effect esterno.
  /// Solo per il banco di replay (Parte 1) — riproduce ESATTAMENTE il
  /// comportamento dei checkpoint prima del Fix 1 (09/08/2026): raggio
  /// fisso storico (20m, il valore in produzione prima di questo fix) +
  /// doppia conferma su due fix consecutivi, via lo stesso
  /// `WaypointDetector.detectPassage` usato per inizio/fine PS. Serve
  /// esclusivamente al confronto "quanti CP agganciati prima/dopo" richiesto
  /// sul replay — mai usato nel percorso live.
  static const double kLegacyCheckpointRadiusMeters = 20.0;

  void _resetSessionState({
    required List<WaypointModel> waypoints,
    List<SpecialModel> specials = const [],
    List<WaypointModel> fuelPoints = const [],
    List<DangerPointModel> dangerPoints = const [],
    List<SpeedZoneModel> speedZones = const [],
    List<LatLng> referenceTrack = const [],
    bool legacyCheckpointDetection = false,
  }) {
    _specials = specials;
    _inizioToSpecial.clear();
    _fineToSpecial.clear();
    for (final s in specials) {
      _inizioToSpecial[s.waypointInizio.id] = s.id;
      _fineToSpecial[s.waypointFine.id] = s.id;
    }

    // Zone a velocità controllata: i punti inizio/fine vengono iniettati
    // tra i waypoint generici (tipo intermedio, doppia conferma riusata)
    // e mappati qui all'id della zona per il calcolo della velocità media.
    _speedZones = speedZones;
    _zoneStartToZone.clear();
    _zoneEndToZone.clear();
    _zoneEntryTimestamps.clear();
    _zoneRadiusOverrides.clear();
    final zoneWaypoints = <WaypointModel>[];
    for (final z in speedZones) {
      final startId = '${z.id}_start';
      final endId = '${z.id}_end';
      _zoneStartToZone[startId] = z.id;
      _zoneEndToZone[endId] = z.id;
      _zoneRadiusOverrides[startId] = AppConstants.speedZoneRadiusMeters;
      _zoneRadiusOverrides[endId] = AppConstants.speedZoneRadiusMeters;
      zoneWaypoints.add(WaypointModel(
        id: startId,
        nome: 'Zona ${z.nome} - inizio',
        lat: z.startLat,
        lng: z.startLng,
        type: WaypointType.intermedio,
      ));
      zoneWaypoints.add(WaypointModel(
        id: endId,
        nome: 'Zona ${z.nome} - fine',
        lat: z.endLat,
        lng: z.endLng,
        type: WaypointType.intermedio,
      ));
    }
    // Fix 4 — tenuta per stimare la distanza tra un cluster di jump
    // scartati e il percorso atteso (vedi _flushJumpCluster).
    _referenceTrack = referenceTrack;

    // Porte virtuali (Blocco A): attaccate solo a inizio/fine PS e a
    // ingresso/uscita zona velocità — per i checkpoint intermedi resta il
    // solo metodo a raggio (A5: lì conta solo il passaggio, non l'istante).
    // Fix 3 — semi-larghezza personalizzabile per waypoint
    // (WaypointModel.gateHalfWidthMeters); se la curvatura locale della
    // traccia è troppo accentuata, buildGate ritorna null e lo notifica qui
    // per il log diagnostico (il waypoint ricade sul solo raggio).
    _waypoints = WaypointDetector.attachGates(
      [...waypoints, ...zoneWaypoints],
      referenceTrack,
      shouldGate: (w) =>
          w.type == WaypointType.inizio ||
          w.type == WaypointType.fine ||
          _zoneStartToZone.containsKey(w.id) ||
          _zoneEndToZone.containsKey(w.id),
      onUnreliableBearing: (w, variationDeg) =>
          _diagLogger?.logUnreliableGateBearing(w.id, variationDeg),
    );

    // Fix 1 — checkpoint (controlPoints di ogni speciale) isolati dal resto
    // dei waypoint: sono l'unico caso rilevato su traiettoria/segmento
    // invece che con porta+raggio.
    final checkpointIds = <String>{
      for (final s in specials) ...s.controlPoints.map((cp) => cp.id),
    };
    if (legacyCheckpointDetection) {
      // Confronto before/after (Parte 1): i CP restano nel percorso
      // porta+raggio esistente, con la soglia storica invece del nuovo
      // default — detectGateCrossing li ignora comunque (mai gated), quindi
      // finiscono sempre nel fallback a raggio con doppia conferma.
      _checkpointWaypoints = [];
      _nonCheckpointWaypoints = _waypoints;
      for (final id in checkpointIds) {
        _zoneRadiusOverrides[id] = kLegacyCheckpointRadiusMeters;
      }
    } else {
      _checkpointWaypoints =
          _waypoints.where((w) => checkpointIds.contains(w.id)).toList();
      _nonCheckpointWaypoints =
          _waypoints.where((w) => !checkpointIds.contains(w.id)).toList();
    }
    _cpMinDistance.clear();
    _cpMinDistanceMethod.clear();

    _passedWaypoints.clear();
    _bestPassageByWaypoint.clear();
    _jumpClusterBuffer.clear();
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
    _recoveryAccuracies.clear();
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
    _nearestWaypointLabel = null;
    _lastRawPositionTs = null;
    _lastFirestoreUpdateTs = null;
    _isRestartingGps = false;
  }

  Future<void> startRecording({
    required String eventId,
    required String userId,
    required List<WaypointModel> waypoints,
    List<SpecialModel> specials = const [],
    List<WaypointModel> fuelPoints = const [],
    List<DangerPointModel> dangerPoints = const [],
    List<SpeedZoneModel> speedZones = const [],
    // Polyline GPX di riferimento dell'evento, usata una sola volta qui per
    // costruire le porte virtuali di inizio/fine PS e zone velocità (Blocco
    // A — timing di precisione). Se vuota, tutti i waypoint restano senza
    // porta e il rilevamento ricade sul metodo a raggio esistente.
    List<LatLng> referenceTrack = const [],
    // Percorso alternativo (10/08/2026, Parte 5) — 'A' o 'B': la variante
    // ATTIVA sull'evento nel momento in cui il pilota preme START, salvata
    // sul suo documento di tracking così che il ricalcolo tempi
    // ufficiali/il replay/la classifica possano sempre risalire a quale
    // percorso ha corso REALMENTE, anche se l'admin cambia
    // `event.activeRouteId` più tardi (anche per errore). Obbligatorio: non
    // deve esistere un percorso "che il chiamante ha dimenticato di
    // specificare".
    required String routeVariantId,
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
    _resetSessionState(
      waypoints: waypoints,
      specials: specials,
      fuelPoints: fuelPoints,
      dangerPoints: dangerPoints,
      speedZones: speedZones,
      referenceTrack: referenceTrack,
    );
    _isRecording = true;
    _mode = GpsMode.transfer;
    _recordingStart = DateTime.now();
    _replayMode = false;
    _gnssStatus?.start();
    unawaited(_voiceAlerts?.start());
    if (_diagLogger?.isActive == true) {
      unawaited(() async {
        final batteryOk =
            await BatterySetupService.isIgnoringBatteryOptimizations();
        final manufacturer = await BatterySetupService.manufacturer();
        final model = await BatterySetupService.deviceModel();
        await _diagLogger!.startSession(
          batteryOptimizationIgnored: batteryOk,
          gpsProvider: _useRawLocationManager ? 'raw' : 'fused',
          deviceManufacturer: manufacturer,
          deviceModel: model,
        );
        _diagLogger.logLifecycle('foreground_service_start');
      }());
    }
    // Notifica IMMEDIATA: la schermata di navigazione deve apparire subito,
    // indipendentemente da quanto impiega il GPS a fornire un fix. Tutto
    // quello che segue (IMU, stream posizione) avviene in background mentre
    // l'utente vede già la mappa e i controlli attivi.
    _safeNotify();

    WakelockPlus.enable().ignore();
    await _imu.start();

    _firestoreService
        .setRaceStatus(eventId, userId, 'racing', routeVariantId: routeVariantId)
        .catchError((_) {});
    _firestoreService
        .saveRouteVariantUsed(eventId, userId, routeVariantId)
        .catchError((_) {});
    _startPositionStream(AppConstants.gpsIntervalTransferMs);
  }

  // ── Parte 1 — Banco di replay ───────────────────────────────────────────
  //
  // Rigioca una sequenza di campioni attraverso ESATTAMENTE la stessa
  // pipeline della registrazione live (STEP 1-6 di [_onPosition]: filtro
  // accuracy, filtro jump, Kalman 4D, filtro anchor, porte virtuali,
  // fallback a raggio, recovery) — nessuna riscrittura della logica.
  // `_activeEventId`/`_activeUserId` restano SEMPRE null durante il replay:
  // ogni scrittura Firestore/offline-queue nella pipeline è già condizionata
  // su questi due campi (vedi `_handleWaypointDetection`,
  // `_checkSpeedZoneViolation`, il tracking live in `_onPosition`), quindi
  // restano automaticamente no-op senza bisogno di altri guard. Wakelock,
  // IMU, GNSS, TTS e permessi non vengono mai toccati: l'istanza va creata
  // apposta per il replay (mai la stessa del pilota in gara).
  //
  // Un'istanza di GpsService dedicata al replay va costruita con
  // `_gnssStatus`/`_voiceAlerts` a null e con un [DiagnosticLogger] in
  // modalità `captureOnly` per raccogliere metodo/frazione/distanza di ogni
  // attraversamento porta — vedi `track_replay_service.dart`.

  /// Inizializza una sessione di replay con la stessa identica logica di
  /// [startRecording] (vedi [_resetSessionState]) ma senza alcun
  /// side-effect live: nessun permesso richiesto, nessuna scrittura
  /// Firestore, nessuno stream GPS reale. [sessionStart] sostituisce
  /// `DateTime.now()` come riferimento per la soglia di accuracy
  /// progressiva e la finestra di grazia iniziale (10s) — di norma il
  /// timestamp del primo campione della traccia.
  void startReplaySession({
    required List<WaypointModel> waypoints,
    required DateTime sessionStart,
    List<SpecialModel> specials = const [],
    List<WaypointModel> fuelPoints = const [],
    List<DangerPointModel> dangerPoints = const [],
    List<SpeedZoneModel> speedZones = const [],
    List<LatLng> referenceTrack = const [],
    // Fix 1 (09/08/2026) — solo per il confronto before/after nel banco di
    // replay (vedi TrackReplayService, kLegacyCheckpointRadiusMeters): mai
    // true nel percorso live.
    bool legacyCheckpointDetection = false,
  }) {
    _resetSessionState(
      waypoints: waypoints,
      specials: specials,
      fuelPoints: fuelPoints,
      dangerPoints: dangerPoints,
      speedZones: speedZones,
      referenceTrack: referenceTrack,
      legacyCheckpointDetection: legacyCheckpointDetection,
    );
    _replayMode = true;
    _isRecording = true;
    _mode = GpsMode.transfer;
    _recordingStart = sessionStart;
  }

  /// Fa avanzare la pipeline di un campione — stesso codice esatto di
  /// [_onPosition] usato in diretta, con [sampleTimestamp] al posto di
  /// `DateTime.now()` per rispettare la timeline originale della traccia
  /// rigiocata. Va atteso (await) in ordine, un campione alla volta: il
  /// Kalman e i filtri jump/anchor dipendono dallo stato del campione
  /// precedente esattamente come in diretta.
  Future<void> ingestReplaySample(Position pos, DateTime sampleTimestamp) =>
      _onPosition(pos, nowOverride: sampleTimestamp);

  /// Termina la sessione di replay: solo stato locale (a differenza di
  /// [stopRecording], nessun side-effect live da fermare perché nessuno è
  /// mai stato avviato).
  void endReplaySession() {
    _flushJumpCluster();
    _logCheckpointDiagnostics();
    _isRecording = false;
    _mode = GpsMode.idle;
    _replayMode = false;
  }

  void _startPositionStream(int intervalMs) {
    _currentIntervalMs = intervalMs;
    // Parte 1 — banco di replay: nessuno stream GPS reale, i campioni
    // arrivano da [ingestReplaySample]. Il cambio di modalità durante il
    // replay aggiorna comunque _currentIntervalMs sopra per coerenza, ma
    // non deve mai toccare Geolocator (niente hardware/permessi in un
    // contesto di replay, anche su piattaforme diverse da Android).
    if (_replayMode) return;
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
        forceLocationManager: _useRawLocationManager,
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

  /// Etichetta descrittiva per [wp] (es. "Inizio PS1", "Fine PS3",
  /// "Checkpoint PS2"), risolta tramite le mappe inizio/fine speciale e la
  /// lista dei control points. Le zone a velocità controllata (waypoint
  /// sintetici) non hanno un'etichetta utile per il pilota: null in quel caso.
  String? _labelFor(WaypointModel wp) {
    switch (wp.type) {
      case WaypointType.inizio:
        final sid = _inizioToSpecial[wp.id];
        final s = sid != null
            ? _specials.where((sp) => sp.id == sid).firstOrNull
            : null;
        return 'Inizio ${s?.nome ?? wp.nome}';
      case WaypointType.fine:
        final sid = _fineToSpecial[wp.id];
        final s = sid != null
            ? _specials.where((sp) => sp.id == sid).firstOrNull
            : null;
        return 'Fine ${s?.nome ?? wp.nome}';
      case WaypointType.intermedio:
        if (_zoneStartToZone.containsKey(wp.id) ||
            _zoneEndToZone.containsKey(wp.id)) {
          return null;
        }
        for (final s in _specials) {
          if (s.controlPoints.any((cp) => cp.id == wp.id)) {
            return 'Checkpoint ${s.nome}';
          }
        }
        return 'Checkpoint';
    }
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

  // Parte 1 — banco di replay: [nowOverride] sostituisce `DateTime.now()`
  // per rispettare la timeline originale di una traccia rigiocata (vedi
  // [ingestReplaySample]). Sempre null nel percorso live (stream reale
  // via .listen(_onPosition, ...)), quindi il comportamento in diretta è
  // identico a prima — nessuna logica cambiata, solo l'origine di `now`.
  Future<void> _onPosition(Position pos, {DateTime? nowOverride}) async {
    // Always store raw position and emit stream — UI uses it for accuracy display.
    _lastPosition = pos;
    _posStreamCtrl.add(pos);

    final now = nowOverride ?? DateTime.now();
    final rawLatLng = LatLng(pos.latitude, pos.longitude);

    // Aggiornato ad OGNI posizione ricevuta, valida o no, PRIMA di
    // qualsiasi filtro — usato solo da [isGpsStale] per il pulsante
    // manuale "Ripristina GPS".
    _lastRawPositionTs = now;

    // ── STEP 1: doppia soglia accuracy DISPLAY vs DETECTION ──────────────
    // Oltre la soglia display il punto è troppo impreciso per Kalman/
    // polyline e viene scartato, ma se è ancora entro
    // kMaxAccuracyDetectionMeters la detection waypoint viene comunque
    // eseguita sulla posizione raw, per non perdere passaggi con segnale
    // debole. La soglia display è progressiva nei primi secondi dall'avvio
    // (vedi _currentDisplayAccuracyThreshold): altrimenti la convergenza
    // normale del chip (30-60s) scarterebbe ogni punto e Kalman/IMU
    // resterebbero inizializzati a null per tutta quella finestra.
    final effectiveAccuracy = _effectiveAccuracy(pos.accuracy);
    final displayThreshold = _currentDisplayAccuracyThreshold(now);
    if (effectiveAccuracy > displayThreshold) {
      _consecutiveDiscarded++;
      _diagLogger?.logGpsFix(
        inSpecial: _currentSpecialId != null,
        outcome: 'scartato-accuracy',
        latRaw: pos.latitude,
        lngRaw: pos.longitude,
        accuracy: pos.accuracy,
        discardValue: effectiveAccuracy,
      );
      if (effectiveAccuracy <= kMaxAccuracyDetectionMeters) {
        final detection = _waypointDetector.detectPassage(
            rawLatLng, now, _nonCheckpointWaypoints, _passedWaypoints,
            radiusOverrides: _zoneRadiusOverrides);
        if (detection != null) {
          await _handleWaypointDetection(detection);
          if (_disposed) return;
        }
        // Fix 1 — checkpoint su questo fix scartato dal display: nessun
        // punto precedente affidabile da usare per un segmento in questo
        // ramo (il fix corrente stesso è sotto la sola soglia detection,
        // più larga di quella display), quindi solo distanza puntuale.
        final cpDetection = _waypointDetector.detectCheckpointPassage(
          null,
          rawLatLng,
          null,
          now,
          _checkpointWaypoints,
          _passedWaypoints,
          onDistanceSample: _recordCheckpointDistanceSample,
        );
        if (cpDetection != null) {
          await _handleWaypointDetection(cpDetection,
              timingMethod: cpDetection.detectionMethod ?? 'cp_point');
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
          _diagLogger?.logGpsFix(
            inSpecial: _currentSpecialId != null,
            outcome: 'scartato-jump',
            latRaw: pos.latitude,
            lngRaw: pos.longitude,
            accuracy: pos.accuracy,
            discardValue: impliedSpeedKmh,
          );
          // Fix 4 — accumula per il riassunto di cluster: un multipath
          // sostenuto (più scarti ravvicinati con posizione sistematica)
          // è diagnosticamente diverso da un singolo scarto isolato.
          _jumpClusterBuffer.add(rawLatLng);
          _safeNotify();
          return;
        }
      }
    }
    _flushJumpCluster();
    _lastAcceptedRawPos = rawLatLng;
    _lastAcceptedTs = now;

    // ── STEP 3: Kalman filter 4D cinematico ─────────────────────────────────
    var filteredPos = _kalmanFilter.filter(
        pos.latitude, pos.longitude, effectiveAccuracy, now);

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
              pos.latitude, pos.longitude, effectiveAccuracy, now);
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
    // Catturati PRIMA dell'overwrite sotto: servono al rilevamento porta
    // virtuale (Blocco A2), che ha bisogno del segmento prev->curr esatto
    // dei punti filtrati Kalman, non solo della velocità geometrica.
    final previousFilteredPosForGate = _lastAcceptedFilteredPos;
    final previousFilteredTsForGate = _lastFilteredTs;
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

    final gnssSnapshot = _gnssStatus?.lastSnapshot;
    _diagLogger?.logGpsFix(
      inSpecial: _currentSpecialId != null,
      outcome: 'accettato',
      latRaw: pos.latitude,
      lngRaw: pos.longitude,
      accuracy: pos.accuracy,
      latKalman: filteredPos.latitude,
      lngKalman: filteredPos.longitude,
      speedKmh: _geometricSpeedKmh,
      satUsed: gnssSnapshot?.satellitesUsed,
      satVisible: gnssSnapshot?.satellitesVisible,
      avgCn0: gnssSnapshot?.avgCn0,
    );

    // Recovery track: ogni punto accettato, per il lookback inizio speciale
    _recoveryTrack.add(filteredPos);
    _recoveryTimestamps.add(now);
    _recoveryAccuracies.add(pos.accuracy);

    // Nessuna waypoint detection né recovery nei primi 10s dall'avvio: il
    // buffer GPS si sta ancora inizializzando (fix qualità scarsa,
    // posizione non ancora stabile) e un punto corrotto in questa fase può
    // generare falsi positivi (es. "IN SPECIALE" subito dopo START con la
    // speciale a centinaia di metri di distanza). Il punto viene comunque
    // accumulato sopra in _recoveryTrack per non perdere dati validi.
    final secondsSinceStart = _recordingStart != null
        ? now.difference(_recordingStart!).inSeconds
        : 999;
    if (secondsSinceStart >= 10) {
      // Precedenza timing (Blocco A4): porta virtuale > raggio > recovery.
      // La porta usa il segmento tra l'ultimo punto filtrato e quello
      // corrente per un'interpolazione al millisecondo; se non attraversa
      // nessuna porta (es. gap GPS proprio sulla linea, o ingresso
      // laterale fuori porta), si ricade sul metodo a raggio esistente,
      // che resta invariato e non rimosso.
      WaypointPassageResult? detection;
      var timingMethod = 'radius';
      if (previousFilteredPosForGate != null &&
          previousFilteredTsForGate != null) {
        detection = _waypointDetector.detectGateCrossing(
          previousFilteredPosForGate,
          filteredPos,
          previousFilteredTsForGate,
          now,
          _waypoints,
          _passedWaypoints,
        );
        if (detection != null) {
          // Fix 4 — l'interpolazione lineare resta valida anche a cavallo
          // di un gap, ma un gap ampio tra i due fix che delimitano
          // l'attraversamento rende il tempo meno affidabile: lo si
          // segnala con un metodo distinto invece di un semplice 'gate',
          // così l'admin sa che va guardato con più attenzione.
          final gapMs =
              now.difference(previousFilteredTsForGate).inMilliseconds;
          timingMethod = gapMs > kGateGapThresholdMs ? 'gate_gap' : 'gate';
        }
      }

      // Detect waypoint passage a raggio — sempre sulla posizione filtrata
      // Kalman, confermato solo dopo 2 rilevazioni consecutive (protezione
      // ghost point); il timestamp usato è quello della PRIMA rilevazione,
      // non della seconda. Provato solo se la porta non ha già rilevato un
      // attraversamento in questo fix.
      detection ??= _waypointDetector.detectPassage(
          filteredPos, now, _nonCheckpointWaypoints, _passedWaypoints,
          radiusOverrides: _zoneRadiusOverrides);
      if (detection != null) {
        await _handleWaypointDetection(detection, timingMethod: timingMethod);
        if (_disposed) return;
      }

      // Fix 1 — checkpoint su traiettoria: testato SEMPRE (indipendente dal
      // blocco sopra, mai lo stesso waypoint id), usando il segmento
      // punto-precedente->punto-corrente Kalman-filtrato, entrambi già
      // passati dai filtri accuracy/jump (STEP 1/2) — protezione ghost
      // point per costruzione, non serve un controllo esplicito qui.
      final cpDetection = _waypointDetector.detectCheckpointPassage(
        previousFilteredPosForGate,
        filteredPos,
        previousFilteredTsForGate,
        now,
        _checkpointWaypoints,
        _passedWaypoints,
        onDistanceSample: _recordCheckpointDistanceSample,
      );
      if (cpDetection != null) {
        await _handleWaypointDetection(cpDetection,
            timingMethod: cpDetection.detectionMethod ?? 'cp_point');
        if (_disposed) return;
      }

      // Recovery: retroactively detect missed special starts/ends
      await _trySpecialStartRecovery(filteredPos, now);
      if (_disposed) return;
      await _trySpecialEndRecovery(filteredPos, now);
      if (_disposed) return;

      // Blocco D4: avvisi vocali di avvicinamento a inizio/fine PS e zone
      // a velocità controllata. Soglie/dedupe gestite interamente da
      // VoiceAlertService (D3) — qui solo il calcolo della distanza.
      if (_voiceAlerts != null) {
        if (_currentSpecialId == null) {
          final nextSpecial = _specials
              .where((s) =>
                  !s.annullata && !_passedWaypoints.contains(s.waypointInizio.id))
              .toList()
            ..sort((a, b) => a.ordine.compareTo(b.ordine));
          if (nextSpecial.isNotEmpty) {
            final next = nextSpecial.first;
            final d = _haversineKm(filteredPos,
                    LatLng(next.waypointInizio.lat, next.waypointInizio.lng)) *
                1000.0;
            _voiceAlerts.checkSpecialStartApproach(
                next.id, _specialNumero(next.id), d);
          }
        } else {
          final current =
              _specials.where((s) => s.id == _currentSpecialId).firstOrNull;
          if (current != null) {
            final d = _haversineKm(filteredPos,
                    LatLng(current.waypointFine.lat, current.waypointFine.lng)) *
                1000.0;
            _voiceAlerts.checkSpecialEndApproach(
                current.id, _specialNumero(current.id), d);
          }
        }

        for (final zone in _speedZones) {
          if (_passedWaypoints.contains('${zone.id}_start')) continue;
          final d = _haversineKm(filteredPos, zone.startLatLng) * 1000.0;
          _voiceAlerts.checkSpeedZoneApproach(zone.id, d, zone.maxSpeedKmh);
        }
      }
    }

    // Fuel point passage: mark as passed once within radius, notify exactly once.
    // After this, the "approaching" banner stops even if a GPS jump brings the
    // pilot virtually back near the fuel point.
    for (final fp in _fuelPoints) {
      if (_passedFuelPoints.contains(fp.id)) continue;
      final distM = _haversineKm(filteredPos, LatLng(fp.lat, fp.lng)) * 1000.0;
      _voiceAlerts?.checkFuelPointApproach(fp.id, distM);
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
      if (!_passedDangerPoints.contains(dp.id)) {
        _voiceAlerts?.checkDangerApproach(dp.id, dp.comment, distM);
      }

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
    final nearestWp = WaypointDetector.nearestWaypoint(filteredPos, remainingForMode);
    _nearestWaypointLabel = nearestWp != null ? _labelFor(nearestWp) : null;
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
    // Throttlato a kFirestoreUpdateIntervalMs: la cadenza dei fix GPS sopra
    // (fino a 4Hz) resta piena per Kalman/detection/polyline, solo questa
    // scrittura verso la mappa live admin è limitata.
    if (_activeEventId != null && _activeUserId != null) {
      final dueForFirestore = _lastFirestoreUpdateTs == null ||
          now.difference(_lastFirestoreUpdateTs!).inMilliseconds >=
              kFirestoreUpdateIntervalMs;
      if (dueForFirestore && !_writesBlocked) {
        _lastFirestoreUpdateTs = now;
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
      gpsBearingDeg: _bearingDeg,
    );

    _safeNotify();
  }

  /// Riavvia lo stream GPS cancellando e ricreando la subscription.
  /// Richiamato SOLO dalla UI (pulsante "Ripristina GPS"): nessun
  /// controllo periodico, nessun riavvio automatico — il pilota decide
  /// se e quando riavviare.
  Future<void> restartGps() async {
    if (_isRestartingGps) return;
    debugPrint('GPS RESTART manuale...');
    _diagLogger?.logLifecycle('gps_manual_restart');
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

  Future<void> stopRecording() async {
    _flushJumpCluster();
    unawaited(_voiceAlerts?.stop());
    _positionSub?.cancel();
    _positionSub = null;
    _isRecording = false;
    _writesBlocked = false;
    _mode = GpsMode.idle;
    _activeEventId = null;
    _activeUserId = null;
    _currentSpecialId = null;
    _currentSpecialNome = null;
    _zoneEntryTimestamps.clear();
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
    _nearestWaypointLabel = null;
    _trackPoints.clear();
    _displayAnchor = null;
    _recoveryTrack.clear();
    _recoveryTimestamps.clear();
    _recoveryAccuracies.clear();
    _alertedDangerPoints.clear();
    _warningDangerPoint = null;
    _warningDangerDistance = null;
    _alertDangerPoint = null;
    _alertDangerDistance = null;
    _dangerBlinking = false;
    _isRestartingGps = false;
    _lastRawPositionTs = null;
    _lastFirestoreUpdateTs = null;
    _imu.stop();
    WakelockPlus.disable().ignore();
    _logCheckpointDiagnostics();
    _diagLogger?.logLifecycle('foreground_service_stop');
    unawaited(_diagLogger?.stopSession());
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _posStreamCtrl.close();
    _recoveryStreamCtrl.close();
    _fuelPointStreamCtrl.close();
    _dangerPassedStreamCtrl.close();
    super.dispose();
  }
}
