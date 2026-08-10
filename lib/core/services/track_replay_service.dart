import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/special_model.dart';
import '../models/waypoint_model.dart';
import 'diagnostic_log_parser.dart';
import 'diagnostic_logger.dart';
import 'firestore_service.dart';
import 'gps_service.dart';
import 'gpx_parser.dart';
import 'imu_fusion_service.dart';
import 'offline_queue_service.dart';
import 'track_smoother.dart';
import 'waypoint_detector.dart';

/// Banco di replay (Parte 1): rigioca una traccia GPS già registrata
/// attraverso la STESSA pipeline usata in diretta (vedi
/// `GpsService.startReplaySession`/`ingestReplaySample`, estratti in modo
/// da poter lavorare su una sequenza di campioni senza cambiare la logica
/// esistente), per validare timing e filtri senza uscire sul campo.
///
/// Ogni run costruisce un [GpsService] dedicato e "usa e getta" (mai
/// l'istanza live del pilota in gara): `_activeEventId`/`_activeUserId`
/// restano sempre null, quindi ogni scrittura Firestore nella pipeline è
/// automaticamente no-op (sono già tutte condizionate su questi due campi
/// nel codice esistente).

/// Velocità di riproduzione (1B). `fast`: elabora tutti i campioni il più
/// rapidamente possibile. Le altre applicano un ritardo reale tra un
/// campione e l'altro, proporzionale all'intervallo originale diviso il
/// fattore — utile per osservare il comportamento su una mappa live.
enum ReplaySpeed {
  fast(1),
  x2(2),
  x5(5),
  x10(10);

  final int factor;
  const ReplaySpeed(this.factor);
}

/// Esito del confronto per una singola prova speciale in una configurazione
/// (1C). [tempo] è null se la PS non risulta completata in questa run.
class ReplaySpecialResult {
  final String specialeId;
  final String specialeNome;
  final Duration? tempo;
  final DateTime? ingressoTs;
  final DateTime? uscitaTs;
  final String? metodoIngresso;
  final String? metodoUscita;
  final double? fractionTIngresso;
  final double? distanzaIngressoM;
  final double? fractionTUscita;
  final double? distanzaUscitaM;

  const ReplaySpecialResult({
    required this.specialeId,
    required this.specialeNome,
    this.tempo,
    this.ingressoTs,
    this.uscitaTs,
    this.metodoIngresso,
    this.metodoUscita,
    this.fractionTIngresso,
    this.distanzaIngressoM,
    this.fractionTUscita,
    this.distanzaUscitaM,
  });
}

/// Esito completo di una configurazione (1C): una delle tre run del
/// confronto ("Solo raggio" / "Porta + raggio" / "Porta + RTS").
class ReplayConfigResult {
  final String configNome;
  final List<ReplaySpecialResult> speciali;
  final int gateCount;
  final int radiusFallbackCount;
  final List<String> radiusFallbackReasons;
  // Fix 1 (09/08/2026) — numero di checkpoint (SpecialModel.controlPoints)
  // agganciati su [cpTotal] configurati, e distanza minima raggiunta per
  // ciascuno (id waypoint -> metri, null se mai calcolata) — per il
  // confronto "quanti CP prima/dopo il fix" richiesto sul replay
  // dell'evento reale.
  final int cpPassedCount;
  final int cpTotal;
  final Map<String, double?> cpMinDistanceMeters;
  final Set<String> cpPassedIds;

  const ReplayConfigResult({
    required this.configNome,
    required this.speciali,
    required this.gateCount,
    required this.radiusFallbackCount,
    required this.radiusFallbackReasons,
    this.cpPassedCount = 0,
    this.cpTotal = 0,
    this.cpMinDistanceMeters = const {},
    this.cpPassedIds = const {},
  });

  factory ReplayConfigResult.empty(String configNome) => ReplayConfigResult(
        configNome: configNome,
        speciali: const [],
        gateCount: 0,
        radiusFallbackCount: 0,
        radiusFallbackReasons: const [],
      );
}

class TrackReplayService {
  TrackReplayService._();

  /// Accuracy dichiarata quando la sorgente non la fornisce (1A) — GPX non
  /// porta mai l'accuracy del chip.
  static const double defaultAccuracyMeters = 5.0;

  static const String configRadiusOnly = 'Solo raggio';
  static const String configGateRadius = 'Porta + raggio';
  static const String configGateRts = 'Porta + RTS';

  // ── 1A: sorgenti di input — producono tutte List<RawTrackSample> ────────

  /// Sorgente 1: traccia grezza completa di un pilota salvata su Firestore
  /// da `saveFullPilotTrack` (posizione + accuracy + timestamp per fix
  /// accettato). Lista vuota se il pilota non ha mai completato una
  /// sessione dopo l'introduzione di questo campo (Step 35).
  static Future<List<RawTrackSample>> loadFromFirestore(
    FirestoreService firestoreService,
    String eventId,
    String userId,
  ) =>
      firestoreService.getFullPilotTrack(eventId, userId);

  /// Sorgente 2: CSV di log diagnostico (Parte 4) — usa i soli fix
  /// `gps_fix,accettato` (posizione RAW, non quella già filtrata Kalman:
  /// il replay deve rifiltrare da zero).
  static List<RawTrackSample> loadFromDiagnosticCsv(String csvContent) =>
      DiagnosticLogParser.extractAcceptedGpsSamples(
          DiagnosticLogParser.parse(csvContent));

  /// Sorgente 3: file GPX importato, con timestamp per punto.
  static List<RawTrackSample> loadFromGpx(
    String gpxContent, {
    double defaultAccuracy = defaultAccuracyMeters,
  }) =>
      GpxParser.parseGpxSamples(gpxContent,
          defaultAccuracyMeters: defaultAccuracy);

  // ── 1B/1C: esecuzione ────────────────────────────────────────────────────

  /// Tutti i waypoint di [specials] (inizio/fine/controlPoints), nell'ordine
  /// atteso da `GpsService.startReplaySession`.
  static List<WaypointModel> _allWaypoints(List<SpecialModel> specials) => [
        for (final s in specials) s.waypointInizio,
        for (final s in specials) s.waypointFine,
        for (final s in specials) ...s.controlPoints,
      ];

  /// Esegue [samples] attraverso la pipeline live completa (STEP 1-6 di
  /// `GpsService._onPosition`: filtro accuracy, jump, Kalman 4D, anchor,
  /// porte virtuali, fallback a raggio, recovery) con [referenceTrack] come
  /// polyline per costruire le porte — vuota forza il fallback a raggio per
  /// tutti (config "Solo raggio", comportamento storico), popolata riproduce
  /// il comportamento attuale (config "Porta + raggio").
  static Future<ReplayConfigResult> runFullPipeline({
    required String configNome,
    required List<RawTrackSample> samples,
    required List<SpecialModel> specials,
    required List<LatLng> referenceTrack,
    required FirestoreService firestoreService,
    required SharedPreferences prefs,
    ReplaySpeed speed = ReplaySpeed.fast,
    void Function(int index, int total)? onProgress,
    // Fix 1 (09/08/2026) — true riproduce il comportamento CHECKPOINT
    // storico (raggio 20m + doppia conferma, come prima del fix) invece del
    // nuovo rilevamento su traiettoria: usato solo dal confronto
    // before/after, mai dalle run normali del banco di replay.
    bool legacyCheckpointDetection = false,
  }) async {
    if (samples.length < 2) return ReplayConfigResult.empty(configNome);

    final diag = DiagnosticLogger(captureOnly: true);
    final gps = GpsService(
      firestoreService,
      OfflineQueueService(prefs),
      ImuFusionService(),
      null, // GnssStatusService: nessun dato satellite nel replay
      null, // VoiceAlertService: nessun TTS nel replay
      diag,
      null, // SharedPreferences per useRawLocationManager: irrilevante nel replay
    );

    gps.startReplaySession(
      waypoints: _allWaypoints(specials),
      legacyCheckpointDetection: legacyCheckpointDetection,
      specials: specials,
      referenceTrack: referenceTrack,
      sessionStart: samples.first.timestamp,
    );

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final pos = Position(
        latitude: s.lat,
        longitude: s.lng,
        timestamp: s.timestamp,
        accuracy: s.accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      await gps.ingestReplaySample(pos, s.timestamp);
      onProgress?.call(i + 1, samples.length);
      if (speed != ReplaySpeed.fast && i > 0) {
        final realDeltaMs =
            s.timestamp.difference(samples[i - 1].timestamp).inMilliseconds;
        final delayMs = realDeltaMs ~/ speed.factor;
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    await gps.closeAllOpenSpecialsAt(samples.last.timestamp);

    // Fix 1 — endReplaySession() emette il riepilogo diagnostico dei
    // checkpoint (vedi GpsService._logCheckpointDiagnostics): va chiamato
    // PRIMA di leggere diag.captured, non dopo.
    gps.endReplaySession();
    final result = _buildFullPipelineResult(configNome, specials, gps, diag);
    gps.dispose();
    return result;
  }

  static ReplayConfigResult _buildFullPipelineResult(
    String configNome,
    List<SpecialModel> specials,
    GpsService gps,
    DiagnosticLogger diag,
  ) {
    // campo1=waypointId, campo3/campo4=fractionT/distanza (String) per le
    // porte; campo1=waypointId, campo2=motivo per il fallback a raggio.
    final gateInfo = <String, (double, double)>{};
    var gateCount = 0;
    var radiusFallbackCount = 0;
    final radiusFallbackReasons = <String>[];

    // Fix 1 — conteggio CP agganciati via GpsService.isWaypointPassed,
    // valido in ENTRAMBE le modalità (legacy incluso, dove
    // _checkpointWaypoints resta vuoto e quindi non emette alcun log
    // 'checkpoint'/'riepilogo' — vedi sotto). Il log diagnostico stesso
    // (distanza minima per CP) è disponibile SOLO nella modalità nuova, e
    // va letto separatamente per non falsare il conteggio in modalità
    // legacy.
    final cpIds = <String>{
      for (final s in specials)
        if (!s.annullata) ...s.controlPoints.map((cp) => cp.id),
    };
    final cpTotal = cpIds.length;
    final cpPassedIds = cpIds.where(gps.isWaypointPassed).toSet();
    final cpPassedCount = cpPassedIds.length;
    final cpMinDistanceMeters = <String, double?>{};

    for (final e in diag.captured) {
      if (e.categoria == 'checkpoint' && e.evento == 'riepilogo') {
        final wpId = e.campi[0] as String;
        final minDist = double.tryParse('${e.campi[1]}');
        cpMinDistanceMeters[wpId] = minDist;
        continue;
      }
      if (e.categoria != 'timing') continue;
      if (e.evento == 'porta') {
        gateCount++;
        final wpId = e.campi[0] as String;
        final fractionT = double.tryParse('${e.campi[2]}') ?? 0;
        final dist = double.tryParse('${e.campi[3]}') ?? 0;
        gateInfo[wpId] = (fractionT, dist);
      } else if (e.evento == 'raggio_fallback') {
        radiusFallbackCount++;
        radiusFallbackReasons.add('${e.campi[0]}: ${e.campi[1]}');
      }
    }

    final speciali = <ReplaySpecialResult>[];
    for (final s in specials) {
      if (s.annullata) continue;
      final entry =
          gps.specialEntries.where((e) => e.specialeId == s.id).lastOrNull;
      // Fix 1/2 — il metodo EFFETTIVAMENTE vincente (registro di
      // precedenza), non solo quello del primo tentativo: una recovery che
      // ha usato una porta orfana risulta correttamente 'gate'/'gate_gap',
      // non 'recovery'.
      final metodoIn = gps.timingMethodFor(s.waypointInizio.id);
      final metodoOut = gps.timingMethodFor(s.waypointFine.id);
      final gateIn = (metodoIn == 'gate' || metodoIn == 'gate_gap')
          ? gateInfo[s.waypointInizio.id]
          : null;
      final gateOut = (metodoOut == 'gate' || metodoOut == 'gate_gap')
          ? gateInfo[s.waypointFine.id]
          : null;
      speciali.add(ReplaySpecialResult(
        specialeId: s.id,
        specialeNome: s.nome,
        tempo: entry?.elapsed,
        ingressoTs: entry?.entryTime,
        uscitaTs: entry?.exitTime,
        metodoIngresso: metodoIn,
        metodoUscita: metodoOut,
        fractionTIngresso: gateIn?.$1,
        distanzaIngressoM: gateIn?.$2 ?? gps.passageDistanceFor(s.waypointInizio.id),
        fractionTUscita: gateOut?.$1,
        distanzaUscitaM: gateOut?.$2 ?? gps.passageDistanceFor(s.waypointFine.id),
      ));
    }

    return ReplayConfigResult(
      configNome: configNome,
      speciali: speciali,
      gateCount: gateCount,
      radiusFallbackCount: radiusFallbackCount,
      radiusFallbackReasons: radiusFallbackReasons,
      cpPassedCount: cpPassedCount,
      cpTotal: cpTotal,
      cpMinDistanceMeters: cpMinDistanceMeters,
      cpPassedIds: cpPassedIds,
    );
  }

  /// Config "Porta + RTS": smussa [samples] con [TrackSmoother] e riesegue
  /// SOLO il rilevamento porta/raggio (no Kalman/filtri accuracy/jump — la
  /// traccia è già pulita) via `WaypointDetector.rerunGateRadiusDetection`,
  /// la stessa funzione usata da "Tempi ufficiali" (`timing_screen.dart`) —
  /// nessuna nuova logica, solo riuso.
  static ReplayConfigResult runSmoothedGateRerun({
    required List<RawTrackSample> samples,
    required List<SpecialModel> specials,
    required List<LatLng> referenceTrack,
  }) {
    if (samples.length < 2) return ReplayConfigResult.empty(configGateRts);
    final smoothed = TrackSmoother.smooth(samples);

    final gatedBySpecial = <String, (WaypointModel, WaypointModel)>{};
    for (final s in specials) {
      if (s.annullata) continue;
      final gIni = WaypointDetector.buildGate(
        s.waypointInizio,
        referenceTrack,
        halfWidthMeters: s.waypointInizio.gateHalfWidthMeters ??
            WaypointDetector.kGateHalfWidthMeters,
      );
      final gFin = WaypointDetector.buildGate(
        s.waypointFine,
        referenceTrack,
        halfWidthMeters: s.waypointFine.gateHalfWidthMeters ??
            WaypointDetector.kGateHalfWidthMeters,
      );
      gatedBySpecial[s.id] = (
        gIni == null ? s.waypointInizio : s.waypointInizio.copyWithGate(gIni),
        gFin == null ? s.waypointFine : s.waypointFine.copyWithGate(gFin),
      );
    }

    final rerun =
        WaypointDetector.rerunGateRadiusDetection(smoothed, gatedBySpecial);

    final speciali = <ReplaySpecialResult>[];
    var gateCount = 0;
    var radiusCount = 0;
    for (final s in specials) {
      if (s.annullata) continue;
      final r = rerun[s.id];
      if (r?.startMethod == 'gate') gateCount++;
      if (r?.startMethod == 'radius') radiusCount++;
      if (r?.endMethod == 'gate') gateCount++;
      if (r?.endMethod == 'radius') radiusCount++;
      speciali.add(ReplaySpecialResult(
        specialeId: s.id,
        specialeNome: s.nome,
        tempo: r != null ? Duration(milliseconds: r.durationMs) : null,
        ingressoTs: r?.startTimestamp,
        uscitaTs: r?.endTimestamp,
        metodoIngresso: r?.startMethod,
        metodoUscita: r?.endMethod,
        fractionTIngresso: r?.startFractionT,
        distanzaIngressoM: r?.startDistanceMeters,
        fractionTUscita: r?.endFractionT,
        distanzaUscitaM: r?.endDistanceMeters,
      ));
    }

    return ReplayConfigResult(
      configNome: configGateRts,
      speciali: speciali,
      gateCount: gateCount,
      radiusFallbackCount: radiusCount,
      radiusFallbackReasons: const [],
    );
  }

  /// Esegue le tre configurazioni minime richieste (1C) sulla stessa
  /// traccia e le ritorna nell'ordine: Solo raggio, Porta + raggio,
  /// Porta + RTS.
  static Future<List<ReplayConfigResult>> runComparison({
    required List<RawTrackSample> samples,
    required List<SpecialModel> specials,
    required List<LatLng> referenceTrack,
    required FirestoreService firestoreService,
    required SharedPreferences prefs,
    ReplaySpeed speed = ReplaySpeed.fast,
    void Function(String configNome, int index, int total)? onProgress,
  }) async {
    final radiusOnly = await runFullPipeline(
      configNome: configRadiusOnly,
      samples: samples,
      specials: specials,
      referenceTrack: const [],
      firestoreService: firestoreService,
      prefs: prefs,
      speed: speed,
      onProgress: (i, t) => onProgress?.call(configRadiusOnly, i, t),
    );
    final gateRadius = await runFullPipeline(
      configNome: configGateRadius,
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
      firestoreService: firestoreService,
      prefs: prefs,
      speed: speed,
      onProgress: (i, t) => onProgress?.call(configGateRadius, i, t),
    );
    final gateRts = runSmoothedGateRerun(
      samples: samples,
      specials: specials,
      referenceTrack: referenceTrack,
    );
    return [radiusOnly, gateRadius, gateRts];
  }

  // ── 1D: esportazione CSV dei risultati ──────────────────────────────────

  static String exportComparisonCsv(List<ReplayConfigResult> configs) {
    final buf = StringBuffer(
        'speciale,configurazione,tempo_ms,metodo_ingresso,metodo_uscita,'
        'fraction_t_ingresso,distanza_ingresso_m,fraction_t_uscita,'
        'distanza_uscita_m\n');
    for (final cfg in configs) {
      for (final sp in cfg.speciali) {
        buf.writeln([
          sp.specialeNome,
          cfg.configNome,
          sp.tempo?.inMilliseconds ?? '',
          sp.metodoIngresso ?? '',
          sp.metodoUscita ?? '',
          sp.fractionTIngresso?.toStringAsFixed(3) ?? '',
          sp.distanzaIngressoM?.toStringAsFixed(1) ?? '',
          sp.fractionTUscita?.toStringAsFixed(3) ?? '',
          sp.distanzaUscitaM?.toStringAsFixed(1) ?? '',
        ].join(','));
      }
    }
    return buf.toString();
  }
}
