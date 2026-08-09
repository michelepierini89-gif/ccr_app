import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Una riga catturata in memoria da [DiagnosticLogger] in modalità
/// [DiagnosticLogger.captureOnly] — stessa struttura di una riga CSV, senza
/// passare da file. Usata dal banco di replay (Parte 1) per leggere gli
/// eventi di timing (porta/raggio/recovery) emessi dalla pipeline durante
/// un replay, riusando gli stessi hook già cablati in `GpsService` per il
/// log diagnostico live (Parte 4) — nessuna nuova strumentazione.
class CapturedLogEntry {
  final String categoria;
  final String evento;
  final List<Object?> campi;
  const CapturedLogEntry(this.categoria, this.evento, this.campi);
}

/// Log tecnico di sessione per la diagnostica sul campo: registra in
/// memoria con flush periodico su file locale CSV (colonne fisse,
/// apribile in Excel), esportabile a fine gara. Mai sul percorso critico:
/// tutte le scritture sono in memoria, il flush su disco è asincrono e
/// periodico (30s), mai sincrono con un fix GPS o un evento di timing.
///
/// Schema CSV: `timestamp_ms,categoria,evento,campo1..campo12`. Le colonne
/// sono generiche per restare fisse tra categorie diverse; il significato
/// di campo1..N dipende dalla categoria (vedi i metodi `log*` sotto, ogni
/// chiamata documenta l'ordine dei campi che passa).
///
/// Disattivabile con [kDiagnosticLoggingEnabled] — da portare a `false`
/// quando il sistema sarà validato sul campo.
class DiagnosticLogger {
  static const bool kDiagnosticLoggingEnabled = true;

  static const int _flushIntervalSeconds = 30;
  static const int _maxFileSizeBytes = 20 * 1024 * 1024;
  static const int _fieldCount = 12;
  // Campiona 1 fix su 4 in trasferimento per contenere il volume su una
  // gara di 4-5 ore; tutti i fix in speciale (dati critici per il timing).
  static const int _transferSampleEvery = 4;
  static const int _gapThresholdSeconds = 5;
  static const int _imuHeadingLogIntervalSeconds = 5;

  /// true: nessun file, nessun flush — ogni riga finisce solo in [captured].
  /// Usato dal banco di replay (Parte 1), dove non esiste un file locale da
  /// scrivere e dove serve leggere gli eventi appena emessi, anche su web
  /// (normalmente escluso da [kDiagnosticLoggingEnabled]/`!kIsWeb`, un
  /// vincolo che riguarda solo il logging di sessioni live su device).
  final bool captureOnly;

  DiagnosticLogger({this.captureOnly = false});

  bool get isActive =>
      captureOnly || (kDiagnosticLoggingEnabled && !kIsWeb);

  final List<String> _buffer = [];
  final List<CapturedLogEntry> _captured = [];
  Timer? _flushTimer;
  File? _file;
  int _transferGpsCounter = 0;
  DateTime? _lastAnyGpsTs;
  DateTime? _lastImuHeadingLogTs;
  bool _disposed = false;

  String? get currentFilePath => _file?.path;

  /// Righe catturate finora in modalità [captureOnly] (vedi
  /// [CapturedLogEntry]). Sempre vuota se [captureOnly] è false.
  List<CapturedLogEntry> get captured => List.unmodifiable(_captured);

  /// Svuota [captured] — richiamato dal banco di replay tra una
  /// configurazione e l'altra dello stesso confronto (Parte 1C), così ogni
  /// run riparte con una cattura pulita.
  void clearCaptured() => _captured.clear();

  /// Avvia una nuova sessione: azzera il buffer/contatori e apre un nuovo
  /// file CSV con l'header. `context` raccoglie lo stato di sessione
  /// richiesto (Parte 4A "ciclo di vita app"): stato ottimizzazione
  /// batteria, provider GPS in uso, modello/produttore device.
  Future<void> startSession({
    required bool batteryOptimizationIgnored,
    required String gpsProvider,
    required String deviceManufacturer,
    required String deviceModel,
  }) async {
    if (!isActive) return;
    _buffer.clear();
    _captured.clear();
    _transferGpsCounter = 0;
    _lastAnyGpsTs = null;
    _lastImuHeadingLogTs = null;
    if (captureOnly) {
      logLifecycle('session_start');
      log('device', 'info', [
        deviceManufacturer,
        deviceModel,
        batteryOptimizationIgnored ? 'battery_ok' : 'battery_optimized',
        gpsProvider,
      ]);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sessionId = DateTime.now().millisecondsSinceEpoch;
      _file = File('${dir.path}/ccr_diagnostic_$sessionId.csv');
      final header = StringBuffer('timestamp_ms,categoria,evento');
      for (var i = 1; i <= _fieldCount; i++) {
        header.write(',campo$i');
      }
      await _file!.writeAsString('$header\n');
    } catch (_) {
      _file = null;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
        const Duration(seconds: _flushIntervalSeconds), (_) => flush());

    logLifecycle('session_start');
    log('device', 'info', [
      deviceManufacturer,
      deviceModel,
      batteryOptimizationIgnored ? 'battery_ok' : 'battery_optimized',
      gpsProvider,
    ]);
  }

  Future<void> stopSession() async {
    if (!isActive) return;
    logLifecycle('session_end');
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
  }

  // ── Riga CSV generica ───────────────────────────────────────────────────

  void log(String categoria, String evento, [List<Object?> fields = const []]) {
    if (!isActive || _disposed) return;
    if (captureOnly) {
      _captured.add(CapturedLogEntry(categoria, evento, fields));
      return;
    }
    final row = StringBuffer()
      ..write(DateTime.now().millisecondsSinceEpoch)
      ..write(',')
      ..write(_csvField(categoria))
      ..write(',')
      ..write(_csvField(evento));
    for (var i = 0; i < _fieldCount; i++) {
      row.write(',');
      if (i < fields.length && fields[i] != null) {
        row.write(_csvField(fields[i].toString()));
      }
    }
    _buffer.add(row.toString());
  }

  String _csvField(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  // ── Ciclo di vita app ────────────────────────────────────────────────────

  /// [evento]: resumed|inactive|paused|detached|hidden, oppure eventi
  /// custom (foreground_service_start/stop, gps_manual_restart).
  void logLifecycle(String evento, [List<Object?> fields = const []]) =>
      log('lifecycle', evento, fields);

  // ── Fix GPS (campo1: latRaw, campo2: lngRaw, campo3: accuracy,
  //    campo4: discardValue, campo5: latKalman, campo6: lngKalman,
  //    campo7: speedKmh, campo8: satUsed, campo9: satVisible,
  //    campo10: avgCn0) ──────────────────────────────────────────────────

  /// `outcome`: accettato | scartato-accuracy | scartato-jump.
  /// Applica da sola il campionamento 1/4 in trasferimento — chiamare per
  /// OGNI fix ricevuto (accettato o scartato), il metodo decide se
  /// scrivere la riga.
  void logGpsFix({
    required bool inSpecial,
    required String outcome,
    required double latRaw,
    required double lngRaw,
    required double accuracy,
    double? discardValue,
    double? latKalman,
    double? lngKalman,
    double? speedKmh,
    int? satUsed,
    int? satVisible,
    double? avgCn0,
  }) {
    if (!isActive || _disposed) return;
    final now = DateTime.now();
    _checkGap(now);
    if (!inSpecial) {
      _transferGpsCounter++;
      if (_transferGpsCounter % _transferSampleEvery != 0) return;
    }
    log('gps_fix', outcome, [
      latRaw,
      lngRaw,
      accuracy,
      discardValue,
      latKalman,
      lngKalman,
      speedKmh,
      satUsed,
      satVisible,
      avgCn0,
    ]);
  }

  void _checkGap(DateTime now) {
    final last = _lastAnyGpsTs;
    if (last != null) {
      final gapSeconds = now.difference(last).inMilliseconds / 1000.0;
      if (gapSeconds > _gapThresholdSeconds) {
        log('gps_gap', 'gap', [gapSeconds.toStringAsFixed(1)]);
      }
    }
    _lastAnyGpsTs = now;
  }

  // ── Eventi di timing ─────────────────────────────────────────────────────

  /// Attraversamento porta virtuale.
  /// campo1: waypointId, campo2: timestampInterpolato, campo3: fractionT,
  /// campo4: distanzaDalWaypointMetri.
  void logGateCrossing(String waypointId, DateTime interpolatedTs,
          double fractionT, double distanceMeters) =>
      log('timing', 'porta', [
        waypointId,
        interpolatedTs.millisecondsSinceEpoch,
        fractionT.toStringAsFixed(3),
        distanceMeters.toStringAsFixed(1),
      ]);

  /// Fallback al raggio quando la porta non ha rilevato l'attraversamento.
  /// campo1: waypointId, campo2: motivo.
  void logRadiusFallback(String waypointId, String reason) =>
      log('timing', 'raggio_fallback', [waypointId, reason]);

  /// Recovery attivato (PS chiusa/recuperata retroattivamente).
  /// campo1: specialeId, campo2: metodo.
  void logRecovery(String specialeId, String metodo) =>
      log('timing', 'recovery', [specialeId, metodo]);

  /// Ingresso/uscita PS. campo1: specialeId, campo2: timingMethod.
  void logSpecialEntry(String specialeId, String timingMethod) =>
      log('timing', 'ps_ingresso', [specialeId, timingMethod]);

  void logSpecialExit(String specialeId, String timingMethod) =>
      log('timing', 'ps_uscita', [specialeId, timingMethod]);

  /// Fix 1/2 — una scrittura è stata evitata perché per [waypointId]
  /// esisteva già un passaggio di precedenza pari o superiore (vedi
  /// `timingMethodRank`/`GpsService._registerPassage`). Copre sia il caso
  /// diretto (un fallback tenta di sovrascrivere un dato migliore) sia il
  /// caso "porta orfana" (Fix 2: la chiusura di una speciale trova un
  /// attraversamento porta già registrato prima che la speciale risultasse
  /// aperta, e lo usa al posto del proprio ricalcolo).
  /// campo1: waypointId, campo2: metodo esistente (vincitore), campo3:
  /// distanza esistente, campo4: metodo scartato, campo5: distanza scartata.
  void logOverwriteAvoided(
    String waypointId,
    String existingMethod,
    double? existingDistanceMeters,
    String discardedMethod,
    double? discardedDistanceMeters,
  ) =>
      log('timing', 'sovrascrittura_evitata', [
        waypointId,
        existingMethod,
        existingDistanceMeters?.toStringAsFixed(1),
        discardedMethod,
        discardedDistanceMeters?.toStringAsFixed(1),
      ]);

  /// Fix 3 — la curvatura della traccia di riferimento nella finestra
  /// attorno a [waypointId] supera la soglia di affidabilità: la porta non
  /// è stata costruita, il rilevamento per questo waypoint ricade sul solo
  /// raggio. campo1: waypointId, campo2: variazione di bearing (gradi).
  void logUnreliableGateBearing(String waypointId, double bearingVariationDeg) =>
      log('timing', 'porta_inaffidabile',
          [waypointId, bearingVariationDeg.toStringAsFixed(1)]);

  /// Fix 4 — riassunto di un cluster di fix consecutivi scartati dal filtro
  /// jump (STEP 2): distingue un multipath sostenuto (più scarti di fila
  /// con posizione media lontana dalla traccia di riferimento) dal rumore
  /// isolato (un singolo scarto). campo1: numero di scarti nel cluster,
  /// campo2/3: lat/lng medi del cluster, campo4: distanza tra la posizione
  /// media e il punto più vicino della traccia di riferimento (null se non
  /// disponibile).
  void logJumpCluster(
    int count,
    double avgLat,
    double avgLng,
    double? distanceToReferenceTrackMeters,
  ) =>
      log('gps_fix', 'jump_cluster_riassunto', [
        count,
        avgLat,
        avgLng,
        distanceToReferenceTrackMeters?.toStringAsFixed(1),
      ]);

  // ── IMU (campo1: headingDisplay, campo2: headingGps) ────────────────────

  /// Throttled internamente a 1 riga ogni 5s (spec 4A) — chiamare da un
  /// listener ad alta frequenza (es. ogni update IMU), il metodo scarta le
  /// chiamate troppo ravvicinate.
  void logImuHeading(double headingDisplayDeg, double headingGpsDeg) {
    if (!isActive || _disposed) return;
    final now = DateTime.now();
    final last = _lastImuHeadingLogTs;
    if (last != null &&
        now.difference(last).inSeconds < _imuHeadingLogIntervalSeconds) {
      return;
    }
    _lastImuHeadingLogTs = now;
    log('imu', 'heading', [
      headingDisplayDeg.toStringAsFixed(1),
      headingGpsDeg.toStringAsFixed(1),
    ]);
  }

  // ── Annunci vocali (campo1: priorita, campo2: testo) ────────────────────

  void logVoiceAnnouncement(String priority, String text) =>
      log('voice', 'annuncio', [priority, text]);

  // ── Flush + rotazione ────────────────────────────────────────────────────

  Future<void> flush() async {
    if (!isActive || _buffer.isEmpty || _file == null) return;
    final chunk = '${_buffer.join('\n')}\n';
    _buffer.clear();
    try {
      await _file!.writeAsString(chunk, mode: FileMode.append, flush: false);
      final len = await _file!.length();
      if (len > _maxFileSizeBytes) await _rotate();
    } catch (_) {
      // Mai bloccare/rilanciare: il logging non deve mai interrompere il
      // percorso critico (registrazione GPS).
    }
  }

  /// Rotazione: mantiene le righe più recenti, scarta la metà più vecchia
  /// del file (escluso l'header, sempre mantenuto).
  Future<void> _rotate() async {
    final file = _file;
    if (file == null) return;
    try {
      final lines = await file.readAsLines();
      if (lines.length < 4) return;
      final header = lines.first;
      final body = lines.sublist(1);
      final keep = body.sublist(body.length ~/ 2);
      await file.writeAsString('$header\n${keep.join('\n')}\n');
    } catch (_) {}
  }
}
