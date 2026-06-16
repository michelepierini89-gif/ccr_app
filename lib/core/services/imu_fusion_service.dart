import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Fonde GPS + giroscopio + accelerometro + bussola per
/// produrre posizione, heading e velocità a ~50Hz.
///
/// ARCHITETTURA:
/// - Giroscopio → heading ad alta frequenza (fast)
/// - Bussola → correzione deriva giroscopio (slow, absolute)
/// - Accelerometro → stima velocità tra fix GPS
/// - GPS anchor → correzione deriva posizione (ogni fix)
///
/// OUTPUT a ~50Hz: fusedPosition, fusedHeadingDeg, fusedSpeedKmh
/// Usato SOLO per display. Timing PS usa GPS+Kalman.
class ImuFusionService extends ChangeNotifier {
  /// Segno del giroscopio Z per la rotazione heading.
  /// +1.0 = rotazione oraria aumenta heading (default)
  /// -1.0 = invertire se la mappa ruota al contrario
  /// DA TESTARE: se durante il test la mappa ruota nella
  /// direzione opposta al movimento reale, cambiare a -1.0
  static const double kGyroZSign = 1.0;

  // ── Heading fusion (complementary filter) ──
  double _headingDeg = 0.0;
  double _lastCompassDeg = 0.0;
  bool _headingInitialized = false;

  // Alpha per correzione deriva giroscopio con bussola.
  // 0.98 = 98% giroscopio (fast), 2% correzione bussola
  // per campione. A 50Hz la bussola converge in ~2 secondi.
  static const double kComplementaryAlpha = 0.98;

  // ── Accelerometro (low-pass filtrato) ──
  double _filtAccelX = 0.0;
  double _filtAccelY = 0.0;

  // Alpha basso = meno rumore, più lag. Per enduro/moto
  // aumentare a 0.15 se serve più reattività.
  // Filtra le vibrazioni del motore (tipicamente > 20Hz).
  static const double kAccelLowPassAlpha = 0.10;

  // ── Stima velocità ──
  // Velocità corrente stimata dall'IMU (m/s).
  // Viene corretta ad ogni GPS fix con la velocità geometrica.
  double _speedMs = 0.0;

  // Decay per evitare deriva infinita della velocità:
  // 0.98 = la velocità decade del 2% per campione (50Hz).
  // Se non c'è accelerazione, la velocità scende verso zero
  // in ~1 secondo. Il GPS anchor la mantiene aggiornata.
  static const double kSpeedDecayFactor = 0.98;

  // Velocità massima credibile per enduro (m/s = 120 km/h)
  static const double kMaxSpeedMs = 33.3;

  // ── Dead reckoning ──
  // Posizione IMU stimata tra fix GPS consecutivi.
  LatLng? _fusedPosition;

  // Massimo dt accettabile tra un campione IMU e il successivo.
  // Sopra questa soglia resettiamo l'integrazione (gap).
  static const double kMaxDtSeconds = 0.5;

  // ── UI throttle ──
  DateTime? _lastUiNotifyTs;
  static const int kUiUpdateIntervalMs = 40; // 25Hz

  // ── Timestamps ──
  DateTime? _lastGyroTs;
  DateTime? _lastAccelTs;

  // ── Subscriptions ──
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _isRunning = false;
  bool _disposed = false;

  // ── Public getters ──
  LatLng? get fusedPosition => _fusedPosition;
  double get fusedHeadingDeg => _headingDeg;
  double get fusedSpeedKmh => _speedMs * 3.6;
  bool get isRunning => _isRunning;

  // ─────────────────────────────────────────────────────
  // INIT / STOP
  // ─────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;
    // flutter_compass non ha un'implementazione web: su web l'IMU fusion
    // resta disattivata e la UI usa solo GPS+Kalman per display.
    if (kIsWeb) return;
    _isRunning = true;
    _reset();

    // Bussola: inizializza heading prima di avviare giroscopio
    // per evitare che parta da 0° per default.
    _compassSub = FlutterCompass.events?.listen(_onCompass);

    // Attendi fino a 2 secondi per il primo fix bussola
    await Future.delayed(const Duration(seconds: 2));

    // Giroscopio: aggiornamenti rapidi per heading
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~50Hz
    ).listen(_onGyroscope);

    // Accelerometro: userAccelerometer esclude la gravità
    // (Android calcola già la componente gravitazionale)
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~50Hz
    ).listen(_onAccelerometer);

    debugPrint('ImuFusionService: avviato');
  }

  void stop() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _compassSub?.cancel();
    _gyroSub = null;
    _accelSub = null;
    _compassSub = null;
    _isRunning = false;
    _reset();
    debugPrint('ImuFusionService: fermato');
  }

  void _reset() {
    _headingDeg = 0.0;
    _headingInitialized = false;
    _filtAccelX = 0.0;
    _filtAccelY = 0.0;
    _speedMs = 0.0;
    _fusedPosition = null;
    _lastGyroTs = null;
    _lastAccelTs = null;
    _lastUiNotifyTs = null;
  }

  // ─────────────────────────────────────────────────────
  // GPS ANCHOR UPDATE
  // Chiamato da GpsService ad ogni fix Kalman accettato.
  // ─────────────────────────────────────────────────────

  void updateWithGps({
    required LatLng position,
    required double speedKmh,
    required DateTime timestamp,
  }) {
    if (_fusedPosition == null) {
      // Prima posizione disponibile: inizializza direttamente
      _fusedPosition = position;
    } else {
      // Correzione graduale: 80% GPS, 20% dead reckoning IMU.
      // Evita salti bruschi se il GPS era leggermente sfasato.
      const kGpsWeight = 0.80;
      _fusedPosition = LatLng(
        kGpsWeight * position.latitude +
            (1 - kGpsWeight) * _fusedPosition!.latitude,
        kGpsWeight * position.longitude +
            (1 - kGpsWeight) * _fusedPosition!.longitude,
      );
    }

    // Sincronizza velocità IMU con GPS quando affidabile
    if (speedKmh > 3.0) {
      _speedMs = speedKmh / 3.6;
    }

    _safeNotify();
  }

  // ─────────────────────────────────────────────────────
  // BUSSOLA → correzione deriva heading giroscopio
  // ─────────────────────────────────────────────────────

  void _onCompass(CompassEvent event) {
    if (event.heading == null || event.heading!.isNaN) return;
    final compassDeg = (event.heading! + 360) % 360;

    if (!_headingInitialized) {
      // Prima lettura bussola: inizializza heading direttamente
      _headingDeg = compassDeg;
      _lastCompassDeg = compassDeg;
      _headingInitialized = true;
      debugPrint(
          'ImuFusion: heading inizializzato a ${compassDeg.toStringAsFixed(1)}°');
      return;
    }

    _lastCompassDeg = compassDeg;
    // Il filtro complementare viene applicato in _onGyroscope
    // usando _lastCompassDeg, non qui, per mantenere
    // la cadenza del giroscopio come base temporale.
  }

  // ─────────────────────────────────────────────────────
  // GIROSCOPIO → heading ad alta frequenza
  // ─────────────────────────────────────────────────────

  void _onGyroscope(GyroscopeEvent event) {
    final now = DateTime.now();
    if (!_headingInitialized) return;

    final dt = _lastGyroTs != null
        ? now.difference(_lastGyroTs!).inMicroseconds / 1e6
        : 0.02; // default 50Hz se prima lettura
    _lastGyroTs = now;

    if (dt > kMaxDtSeconds) return; // gap troppo grande, skip

    // event.z = velocità angolare intorno all'asse verticale
    // (yaw rate) in rad/s. Su Android con telefono orientato
    // normalmente: positivo = rotazione verso destra (orario).
    // Convertiamo in gradi e integriamo. Segno configurabile via kGyroZSign.
    final deltaHeadingDeg = kGyroZSign * event.z * dt * 180.0 / pi;

    // Filtro complementare:
    // kAlpha * (giroscopio integrato) + (1-kAlpha) * bussola
    final gyroPrediction = (_headingDeg + deltaHeadingDeg + 360) % 360;
    final diff = _angularDiff(gyroPrediction, _lastCompassDeg);
    _headingDeg =
        (gyroPrediction + (1.0 - kComplementaryAlpha) * diff + 360) % 360;
  }

  // ─────────────────────────────────────────────────────
  // ACCELEROMETRO → stima velocità + dead reckoning
  // ─────────────────────────────────────────────────────

  void _onAccelerometer(UserAccelerometerEvent event) {
    final now = DateTime.now();
    if (!_headingInitialized || _fusedPosition == null) return;

    final dt = _lastAccelTs != null
        ? now.difference(_lastAccelTs!).inMicroseconds / 1e6
        : 0.02;
    _lastAccelTs = now;

    if (dt > kMaxDtSeconds) return;

    // Low-pass filter: rimuove vibrazioni motore (>20Hz)
    // e irregolarità del fondo stradale.
    _filtAccelX =
        kAccelLowPassAlpha * event.x + (1 - kAccelLowPassAlpha) * _filtAccelX;
    _filtAccelY =
        kAccelLowPassAlpha * event.y + (1 - kAccelLowPassAlpha) * _filtAccelY;

    // Proiezione dell'accelerazione sul vettore di heading.
    // Il telefono è in coordinate device (X=destra, Y=avanti
    // tenendo il telefono verticale). Usiamo l'heading dal
    // filtro complementare per ruotare nel frame geografico.
    // NB: stiamo assumendo il telefono in posizione verticale.
    // Per uso su moto il telefono è tipicamente sullo
    // stelo dello sterzo o sul serbatoio.
    final headingRad = _headingDeg * pi / 180.0;
    final aForward =
        _filtAccelX * sin(headingRad) + _filtAccelY * cos(headingRad);

    // Integra accelerazione → velocità con decay
    _speedMs = (_speedMs + aForward * dt) * kSpeedDecayFactor;
    _speedMs = _speedMs.clamp(-5.0, kMaxSpeedMs);
    // Velocità negativa limitata a -5 m/s (frenata brusca)

    // Dead reckoning: sposta _fusedPosition nella direzione
    // _headingDeg della distanza _speedMs * dt
    final distM = _speedMs.abs() * dt;
    if (distM > 0.001) {
      // > 1mm: sposta
      _fusedPosition = _movePosition(
        _fusedPosition!,
        _speedMs >= 0 ? _headingDeg : (_headingDeg + 180) % 360,
        distM,
      );
    }

    final now2 = DateTime.now();
    if (_lastUiNotifyTs == null ||
        now2.difference(_lastUiNotifyTs!).inMilliseconds >=
            kUiUpdateIntervalMs) {
      _lastUiNotifyTs = now2;
      _safeNotify(); // 25Hz alla UI
    }
  }

  // ─────────────────────────────────────────────────────
  // UTILITY
  // ─────────────────────────────────────────────────────

  /// Sposta una posizione di [distanceM] metri nella
  /// direzione [bearingDeg] gradi (0=Nord, 90=Est).
  static LatLng _movePosition(LatLng from, double bearingDeg, double distanceM) {
    const earthRadiusM = 6371000.0;
    final lat1 = from.latitude * pi / 180;
    final lng1 = from.longitude * pi / 180;
    final brng = bearingDeg * pi / 180;
    final d = distanceM / earthRadiusM;

    final lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng));
    final lng2 = lng1 +
        atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));

    return LatLng(lat2 * 180 / pi, lng2 * 180 / pi);
  }

  /// Differenza angolare minima da [from] a [to], con segno.
  static double _angularDiff(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
