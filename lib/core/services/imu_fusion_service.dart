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

  // ── Heading per il display (rotazione mappa/freccia) ──
  // Indipendente dal filtro complementare giroscopio+bussola sopra: quello
  // resta usato per dead reckoning/posizione, qui invece la bussola grezza
  // pilota direttamente la rotazione mostrata a schermo, con low-pass
  // adattivo alla velocità e clamp anti-scossone.
  double _displayHeadingDeg = 0.0;

  // Alpha velocità-dipendente: da fermo filtra di più (scossoni moto ferma),
  // in movimento diventa più reattivo per seguire le curve.
  double _displayAlpha() {
    if (_speedMs < 2.0) return 0.12;
    if (_speedMs < 10.0) return 0.20;
    return 0.28;
  }

  // Variazione massima del display heading per singolo campione bussola (°).
  // Limita gli scossoni violenti che andrebbero oltre questa soglia.
  static const double kMaxHeadingDeltaPerSample = 8.0;

  // ── Sorgente del display heading in base alla velocità ──
  // Sopra questa soglia la rotta GPS diventa la sorgente principale del
  // display heading (misura il movimento reale, non risente di
  // interferenze magnetiche del veicolo). Sotto l'altra soglia governa la
  // bussola (la rotta GPS è rumorosa/instabile a bassa velocità). Tra le
  // due, transizione lineare — vedi [_gpsWeightForDisplay]. La bussola
  // resta comunque usata per la reattività immediata (variazioni rapide di
  // direzione, vedi [_updateDisplayHeading]), ma il suo contributo per
  // campione si riduce con lo stesso peso, e l'ancora GPS in
  // [updateWithGps] la richiama ad ogni fix verso la rotta reale.
  static const double kDisplayGpsPrimaryThresholdKmh = 15.0;
  static const double kDisplayCompassOnlyThresholdKmh = 5.0;

  // Peso di correzione verso il bearing GPS applicato ad ogni fix quando il
  // GPS è pienamente sorgente primaria (velocità >= soglia sopra) — più
  // alto di [kHeadingGpsAnchorWeight] (che corregge solo la deriva lenta
  // del filtro complementare interno): qui il GPS deve guidare il display,
  // non solo limitarne la deriva.
  static const double kDisplayGpsAnchorWeight = 0.6;

  double _gpsWeightForDisplay(double speedKmh) {
    if (speedKmh <= kDisplayCompassOnlyThresholdKmh) return 0.0;
    if (speedKmh >= kDisplayGpsPrimaryThresholdKmh) return 1.0;
    return (speedKmh - kDisplayCompassOnlyThresholdKmh) /
        (kDisplayGpsPrimaryThresholdKmh - kDisplayCompassOnlyThresholdKmh);
  }

  // ── Controllo di coerenza bussola/GPS ──
  // Se la bussola diverge dalla rotta GPS oltre questa soglia per più di
  // [kCompassCoherenceSustainSeconds] consecutivi, è interferenza
  // magnetica sostenuta (tipicamente il motore/telaio metallico), non
  // rumore isolato: il display heading smette di seguire la bussola
  // finché non rientra, affidandosi solo all'ancora GPS. Non esisteva
  // alcun meccanismo di questo tipo prima di questo fix (verificato — vedi
  // report): gli scarti di 10-40° osservati nel test del 17/08 passavano
  // tutti indisturbati. Soglia abbassata da 40° a 25° dopo il replay del
  // log reale (vedi report per il comportamento misurato).
  static const double kCompassGpsCoherenceThresholdDeg = 25.0;
  static const int kCompassCoherenceSustainSeconds = 5;
  DateTime? _compassDivergingSince;
  bool _compassLowConfidence = false;

  double? _lastGpsBearingDeg;

  /// Scarto istantaneo fra display heading e rotta GPS, in gradi — null se
  /// non è ancora arrivato un bearing GPS attendibile. Esposto per
  /// l'overlay diagnostico.
  double? get headingErrorDeg => _lastGpsBearingDeg == null
      ? null
      : _angularDiff(_lastGpsBearingDeg!, _displayHeadingDeg).abs();

  void _updateDisplayHeading(double compassDeg) {
    if (!_headingInitialized) {
      _displayHeadingDeg = compassDeg;
      return;
    }
    // Bussola inaffidabile (interferenza sostenuta): solo l'ancora GPS in
    // [updateWithGps] muove il display heading finché non rientra.
    if (_compassLowConfidence) return;
    double diff = _angularDiff(_displayHeadingDeg, compassDeg);
    diff = diff.clamp(-kMaxHeadingDeltaPerSample, kMaxHeadingDeltaPerSample);
    final speedKmh = _speedMs * 3.6;
    final compassAlpha = _displayAlpha() * (1 - _gpsWeightForDisplay(speedKmh));
    _displayHeadingDeg =
        (_displayHeadingDeg + compassAlpha * diff + 360) % 360;
  }

  // ── Declinazione magnetica ──
  // flutter_compass (Android: Sensor.TYPE_ROTATION_VECTOR +
  // SensorManager.getOrientation, verificato nel sorgente del plugin —
  // nessun uso di GeomagneticField) restituisce l'heading rispetto al nord
  // MAGNETICO, non geografico. La mappa e il bearing GPS sono riferiti al
  // nord geografico: senza correggere la declinazione ogni lettura bussola
  // porta un errore sistematico. Default per l'Italia centrale (~2026);
  // se non è disponibile un modello geomagnetico si affina nel tempo dallo
  // scarto medio bussola/GPS osservato durante marcia sostenuta e coerente
  // (vedi [_updateDeclinationEstimate] — solo quando il controllo di
  // coerenza sopra non segnala divergenza, altrimenti lo scarto è
  // interferenza, non declinazione).
  static const double kDefaultMagneticDeclinationDeg = 3.5;
  double _magneticDeclinationDeg = kDefaultMagneticDeclinationDeg;
  double? _declinationEstimateDeg;
  int _declinationSampleCount = 0;
  static const int kDeclinationMinSamples = 30;
  static const double kDeclinationEstimateAlpha = 0.02;

  void _updateDeclinationEstimate(
      double compassDeg, double gpsBearingDeg, double speedKmh) {
    if (speedKmh < kDisplayGpsPrimaryThresholdKmh) return;
    final diff = _angularDiff(compassDeg, gpsBearingDeg);
    if (diff.abs() > kCompassGpsCoherenceThresholdDeg) return;
    _declinationSampleCount++;
    _declinationEstimateDeg = _declinationEstimateDeg == null
        ? diff
        : _declinationEstimateDeg! * (1 - kDeclinationEstimateAlpha) +
            diff * kDeclinationEstimateAlpha;
    if (_declinationSampleCount >= kDeclinationMinSamples) {
      _magneticDeclinationDeg = _declinationEstimateDeg!.clamp(-10.0, 10.0);
    }
  }

  // Alpha per correzione deriva giroscopio con bussola, velocità-dipendente
  // (vedi _currentAlpha): da fermo la bussola deve governare quasi
  // completamente l'heading (il giroscopio non ha nulla da integrare e
  // deriva), mentre ad alta velocità il giroscopio resta dominante per non
  // introdurre jitter dalla bussola (interferenze magnetiche del motore).
  // kComplementaryAlpha è il valore di riferimento per la fascia media
  // (3-8 m/s): 0.85 = 85% giroscopio, 15% correzione bussola per campione —
  // molto più reattivo del precedente 0.96 (4% di correzione), che rendeva
  // la freccia visibilmente in ritardo sulle curve.
  static const double kComplementaryAlphaStationary = 0.50;
  static const double kComplementaryAlphaSlow = 0.70;
  static const double kComplementaryAlpha = 0.85;
  static const double kComplementaryAlphaFast = 0.92;

  /// Alpha del filtro complementare corrente, funzione della velocità IMU
  /// stimata (_speedMs, m/s): più si va piano più la bussola deve correggere
  /// rapidamente (il giroscopio integra rumore senza un vero movimento da
  /// inseguire), più si va veloce più il giroscopio resta dominante.
  double _currentAlpha() {
    if (_speedMs < 1.0) return kComplementaryAlphaStationary;
    if (_speedMs < 3.0) return kComplementaryAlphaSlow;
    if (_speedMs < 8.0) return kComplementaryAlpha;
    return kComplementaryAlphaFast;
  }

  // Scarta letture bussola implausibili (salto angolare istantaneo enorme
  // rispetto all'ultima lettura accettata): la bussola fisica non può
  // cambiare di centinaia di gradi in un campione, un salto così è quasi
  // sempre interferenza magnetica (vicino al motore/telaio metallico della
  // moto). Senza questo scarto, un singolo campione corrotto può "tirare"
  // la fusione heading verso un valore senza relazione con la direzione
  // reale di marcia.
  static const double kMaxCompassJumpDeg = 60.0;

  // ── Giroscopio (low-pass filtrato) ──
  // Senza filtro, le vibrazioni del motore (>20Hz, mai isolate dal
  // mount del telefono su moto) si accumulano nell'integrazione e
  // producono un heading instabile/imprevedibile. Alpha più alto
  // dell'accelerometro perché lo yaw reale (curve enduro) deve restare
  // pronto da seguire, a differenza della sola stima di velocità.
  double _filtGyroZ = 0.0;
  static const double kGyroLowPassAlpha = 0.35;

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

  // Timestamp dell'ultimo anchor GPS accettato (vedi updateWithGps).
  // Usato per limitare quanto a lungo il dead reckoning può estrapolare
  // senza una nuova correzione GPS.
  DateTime? _gpsAnchorTs;

  // Sotto questa velocità il dead reckoning non sposta più _fusedPosition:
  // a velocità così basse il rumore dell'accelerometro produce uno
  // spostamento stimato che è puro jitter, non un vero movimento — meglio
  // restare ancorati all'ultimo fix GPS che disegnare una deriva fittizia.
  static const double kMinPredictionSpeedKmh = 5.0;

  // Finestra massima di estrapolazione dall'ultimo anchor GPS: oltre questo
  // tempo senza un nuovo fix, il dead reckoning si ferma (niente nuovo
  // spostamento) invece di continuare a derivare senza alcuna correzione —
  // meglio una posizione leggermente vecchia che una stimata a vuoto.
  static const int kMaxPredictionWindowMs = 800;

  // ── Dead reckoning ridotto in curva (Step 47) ──
  // Il dead reckoning proietta in linea retta lungo l'ultimo heading noto:
  // corretto sui rettilinei (riduce il lag della freccia), sbagliato in
  // curva (il veicolo percorre un arco, non una retta — misurato allo
  // Step 46: +7% di scostamento dal percorso reale nei tratti ad alta
  // curvatura). Riusa la STESSA stima di velocità angolare già calcolata
  // da GpsService per sigmaAccel adattivo (bearing GPS, mai giroscopio —
  // vedi [updateWithGps]), non una seconda stima ridondante. La distanza
  // di proiezione si riduce in proporzione continua (mai a gradini) da
  // 1.0 (rettilineo) a 0.0 (curva stretta): sotto kCurvatureTaperStartDegS
  // nessuna riduzione, sopra kCurvatureTaperEndDegS proiezione annullata,
  // transizione lineare in mezzo.
  static const double kCurvatureTaperStartDegS = 10.0;
  static const double kCurvatureTaperEndDegS = 50.0;
  double _lastAngularVelocityDegS = 0.0;

  double _deadReckoningTaper() {
    if (_lastAngularVelocityDegS <= kCurvatureTaperStartDegS) return 1.0;
    if (_lastAngularVelocityDegS >= kCurvatureTaperEndDegS) return 0.0;
    return 1.0 -
        (_lastAngularVelocityDegS - kCurvatureTaperStartDegS) /
            (kCurvatureTaperEndDegS - kCurvatureTaperStartDegS);
  }

  // ── UI throttle ──
  // 16ms = 60Hz: il DOOGEE ha retto bene nel test reale a 50Hz, saliamo al
  // massimo che garantisce ancora un frame pieno a schermo (60fps) per la
  // freccia più fluida possibile.
  DateTime? _lastUiNotifyTs;
  static const int kUiUpdateIntervalMs = 16; // 60Hz

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
  double get displayHeadingDeg => _displayHeadingDeg;
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
    _displayHeadingDeg = 0.0;
    _headingInitialized = false;
    _filtGyroZ = 0.0;
    _filtAccelX = 0.0;
    _filtAccelY = 0.0;
    _speedMs = 0.0;
    _fusedPosition = null;
    _gpsAnchorTs = null;
    _lastGyroTs = null;
    _lastAccelTs = null;
    _lastUiNotifyTs = null;
    _compassDivergingSince = null;
    _compassLowConfidence = false;
    _lastGpsBearingDeg = null;
    _magneticDeclinationDeg = kDefaultMagneticDeclinationDeg;
    _declinationEstimateDeg = null;
    _declinationSampleCount = 0;
    _lastAngularVelocityDegS = 0.0;
  }

  // ─────────────────────────────────────────────────────
  // GPS ANCHOR UPDATE
  // Chiamato da GpsService ad ogni fix Kalman accettato.
  // ─────────────────────────────────────────────────────

  // Correzione heading verso il bearing geometrico GPS (calcolato da
  // GpsService su posizioni Kalman-filtrate). A differenza della bussola
  // (corretta ogni campione IMU a 50Hz con peso 2%), questa corregge solo
  // ad ogni fix GPS (~1-4Hz) con peso maggiore: senza un'ancora di questo
  // tipo, la deriva di giroscopio+bussola non aveva alcun limite superiore
  // nel corso di una sessione intera (prima il problema era mascherato da
  // un bug Riverpod che ricreava GpsService e fermava l'IMU poco dopo il
  // primo fix — risolto allo Step 28 — esponendo la deriva non corretta).
  static const double kHeadingGpsAnchorWeight = 0.15;

  // Sotto questa velocità il bearing GPS è inaffidabile (rumore/jitter da
  // fermo), coerente con GpsService.kMinBearingSpeedKmh.
  static const double kHeadingGpsAnchorMinSpeedKmh = 3.0;

  void updateWithGps({
    required LatLng position,
    required double speedKmh,
    required DateTime timestamp,
    double? gpsBearingDeg,
    double angularVelocityDegS = 0.0,
  }) {
    _gpsAnchorTs = timestamp;
    _lastAngularVelocityDegS = angularVelocityDegS;

    if (_fusedPosition == null) {
      // Prima posizione disponibile: inizializza direttamente
      _fusedPosition = position;
    } else {
      // Correzione graduale: 95% GPS, 5% dead reckoning IMU.
      // Più reattiva del precedente 90/10 per ridurre ulteriormente il lag
      // percepito tra la posizione mostrata e quella reale — la posizione
      // deve aggiornarsi quasi completamente ad ogni fix GPS.
      const kGpsWeight = 0.95;
      _fusedPosition = LatLng(
        kGpsWeight * position.latitude +
            (1 - kGpsWeight) * _fusedPosition!.latitude,
        kGpsWeight * position.longitude +
            (1 - kGpsWeight) * _fusedPosition!.longitude,
      );
    }

    if (_headingInitialized &&
        gpsBearingDeg != null &&
        speedKmh > kHeadingGpsAnchorMinSpeedKmh) {
      _lastGpsBearingDeg = gpsBearingDeg;

      // Controllo di coerenza bussola/GPS: se la bussola diverge oltre
      // soglia in modo sostenuto, è interferenza magnetica, non rumore.
      final compassGpsDiff =
          _angularDiff(gpsBearingDeg, _displayHeadingDeg).abs();
      if (compassGpsDiff > kCompassGpsCoherenceThresholdDeg) {
        _compassDivergingSince ??= timestamp;
        _compassLowConfidence = timestamp
                .difference(_compassDivergingSince!)
                .inSeconds >=
            kCompassCoherenceSustainSeconds;
      } else {
        _compassDivergingSince = null;
        _compassLowConfidence = false;
      }

      // Declinazione magnetica: si affina solo quando bussola e GPS sono
      // coerenti (altrimenti lo scarto osservato è interferenza, non
      // declinazione) e a marcia sostenuta (rotta GPS affidabile).
      _updateDeclinationEstimate(_displayHeadingDeg, gpsBearingDeg, speedKmh);

      // Ancora GPS sul display heading: peso crescente con la velocità,
      // fino a dominante sopra kDisplayGpsPrimaryThresholdKmh.
      final gpsWeight = _gpsWeightForDisplay(speedKmh) * kDisplayGpsAnchorWeight;
      if (gpsWeight > 0) {
        final displayDiff = _angularDiff(_displayHeadingDeg, gpsBearingDeg);
        _displayHeadingDeg =
            (_displayHeadingDeg + gpsWeight * displayDiff + 360) % 360;
      }

      final diff = _angularDiff(_headingDeg, gpsBearingDeg);
      _headingDeg =
          (_headingDeg + kHeadingGpsAnchorWeight * diff + 360) % 360;
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
    final rawCompassDeg = (event.heading! + 360) % 360;
    // Correzione declinazione magnetica → nord geografico (vedi
    // kDefaultMagneticDeclinationDeg): applicata qui, a monte, così ogni
    // uso a valle (display heading, filtro complementare, jump-check) è
    // già nel riferimento del bearing GPS/mappa.
    final compassDeg = (rawCompassDeg + _magneticDeclinationDeg + 360) % 360;

    _updateDisplayHeading(compassDeg);

    if (!_headingInitialized) {
      // Prima lettura bussola: inizializza heading direttamente
      _headingDeg = compassDeg;
      _lastCompassDeg = compassDeg;
      _headingInitialized = true;
      debugPrint(
          'ImuFusion: heading inizializzato a ${compassDeg.toStringAsFixed(1)}°');
      return;
    }

    // Scarta letture implausibili (interferenza magnetica): un salto
    // angolare istantaneo enorme rispetto all'ultima lettura accettata non
    // può essere un vero movimento della bussola fisica.
    final jump = _angularDiff(_lastCompassDeg, compassDeg).abs();
    if (jump > kMaxCompassJumpDeg) return;

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

    // Low-pass sul giroscopio: senza filtro le vibrazioni del motore
    // (sempre presenti su un mezzo a motore, mount rigido sul manubrio/
    // serbatoio) si integrano direttamente nello heading producendo un
    // rumore ad alta frequenza che, accumulato, sembra una rotazione
    // casuale. Stesso principio già applicato all'accelerometro.
    _filtGyroZ = kGyroLowPassAlpha * event.z + (1 - kGyroLowPassAlpha) * _filtGyroZ;

    // event.z = velocità angolare intorno all'asse verticale
    // (yaw rate) in rad/s. Su Android con telefono orientato
    // normalmente: positivo = rotazione verso destra (orario).
    // Convertiamo in gradi e integriamo. Segno configurabile via kGyroZSign.
    final deltaHeadingDeg = kGyroZSign * _filtGyroZ * dt * 180.0 / pi;

    // Filtro complementare:
    // kAlpha * (giroscopio integrato) + (1-kAlpha) * bussola
    final gyroPrediction = (_headingDeg + deltaHeadingDeg + 360) % 360;
    final diff = _angularDiff(gyroPrediction, _lastCompassDeg);
    final alpha = _currentAlpha();
    _headingDeg = (gyroPrediction + (1.0 - alpha) * diff + 360) % 360;
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

    // ZUPT (Zero Velocity Update): se la velocità stimata è quasi zero e
    // l'accelerazione filtrata è trascurabile, azzera per bloccare la deriva
    // dell'accelerometro (il GPS correggerà appena ci sarà movimento reale).
    if (_speedMs.abs() < 0.3 && _filtAccelX.abs() < 0.1 && _filtAccelY.abs() < 0.1) {
      _speedMs = 0.0;
    }
    // Velocità negativa limitata a -5 m/s (frenata brusca)

    // Dead reckoning: sposta _fusedPosition nella direzione
    // _headingDeg della distanza _speedMs * dt — solo se sopra la soglia
    // minima di velocità (altrimenti è jitter dell'accelerometro, non un
    // vero movimento) e dentro la finestra massima dall'ultimo anchor GPS
    // (oltre questo tempo l'estrapolazione senza correzione non è più
    // affidabile: meglio restare fermi sull'ultima posizione ancorata).
    final msSinceAnchor = _gpsAnchorTs != null
        ? now.difference(_gpsAnchorTs!).inMilliseconds
        : kMaxPredictionWindowMs + 1;
    final canPredict = _speedMs.abs() * 3.6 >= kMinPredictionSpeedKmh &&
        msSinceAnchor <= kMaxPredictionWindowMs;
    // Taper continuo in curva (Step 47): 1.0 in rettilineo, verso 0.0 in
    // curva stretta — vedi [_deadReckoningTaper]. Sui rettilinei il dead
    // reckoning resta invariato (riduce il lag della freccia).
    final distM = _speedMs.abs() * dt * _deadReckoningTaper();
    if (canPredict && distM > 0.001) {
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
