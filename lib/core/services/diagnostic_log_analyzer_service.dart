import 'diagnostic_log_parser.dart';
import 'gnss_status_service.dart';

/// Un gap GPS (>5s senza fix) rilevato nel log, con l'evento di ciclo vita
/// app più vicino nel tempo (se ce n'è uno entro [DiagnosticLogAnalyzerService
/// .kLifecycleCorrelationWindowSeconds]) — la verifica chiave per il GPS in
/// background.
class GapEntry {
  final DateTime start;
  final Duration duration;
  final String? nearbyLifecycleEvent;

  const GapEntry({
    required this.start,
    required this.duration,
    this.nearbyLifecycleEvent,
  });
}

class RecoveryEntry {
  final DateTime timestamp;
  final String specialeId;
  final String metodo;
  const RecoveryEntry(
      {required this.timestamp, required this.specialeId, required this.metodo});
}

/// Metodo/distanza/frazione di interpolazione per l'ingresso e l'uscita di
/// una PS, ricostruiti dalle righe `timing,porta`/`timing,raggio_fallback`/
/// `timing,ps_ingresso`/`timing,ps_uscita`.
class TimingSpecialInfo {
  final String specialeId;
  final String? metodoIngresso;
  final double? fractionTIngresso;
  final double? distanzaIngressoM;
  final String? metodoUscita;
  final double? fractionTUscita;
  final double? distanzaUscitaM;

  const TimingSpecialInfo({
    required this.specialeId,
    this.metodoIngresso,
    this.fractionTIngresso,
    this.distanzaIngressoM,
    this.metodoUscita,
    this.fractionTUscita,
    this.distanzaUscitaM,
  });
}

class DiagnosticLogReport {
  // ── Qualità del segnale ──
  final Duration? sessionDuration;
  final int fixTotal;
  final int fixAccepted;
  final int fixDiscardedAccuracy;
  final int fixDiscardedJump;
  final double? accuracyMin;
  final double? accuracyMedian;
  final double? accuracyMax;
  final int? satUsedMin;
  final int? satUsedMedian;
  final int? satUsedMax;
  final Map<String, int> gnssQualityDistribution;

  // ── Continuità ──
  final List<GapEntry> gaps;
  final Duration gapTotalCumulato;
  final double gapPercentOfSession;

  // ── Timing ──
  final List<TimingSpecialInfo> timingPerSpecial;
  final List<RecoveryEntry> recoveries;

  // ── Configurazione ──
  final String? deviceManufacturer;
  final String? deviceModel;
  final String? batteryStatus;
  final String? gpsProvider;

  const DiagnosticLogReport({
    required this.sessionDuration,
    required this.fixTotal,
    required this.fixAccepted,
    required this.fixDiscardedAccuracy,
    required this.fixDiscardedJump,
    required this.accuracyMin,
    required this.accuracyMedian,
    required this.accuracyMax,
    required this.satUsedMin,
    required this.satUsedMedian,
    required this.satUsedMax,
    required this.gnssQualityDistribution,
    required this.gaps,
    required this.gapTotalCumulato,
    required this.gapPercentOfSession,
    required this.timingPerSpecial,
    required this.recoveries,
    required this.deviceManufacturer,
    required this.deviceModel,
    required this.batteryStatus,
    required this.gpsProvider,
  });

  double? get discardedAccuracyPercent =>
      fixTotal == 0 ? null : fixDiscardedAccuracy * 100 / fixTotal;
  double? get discardedJumpPercent =>
      fixTotal == 0 ? null : fixDiscardedJump * 100 / fixTotal;
}

/// Riepilogo automatico di un CSV di log diagnostico (Parte 2) — i log sono
/// completi ma troppo lunghi da leggere a mano, questo servizio ne estrae
/// le sezioni chiave (qualità segnale, continuità/gap, timing PS,
/// configurazione device) riusando [DiagnosticLogParser] e le stesse
/// soglie di qualità GNSS già definite in [GnssStatusSnapshot.quality].
class DiagnosticLogAnalyzerService {
  DiagnosticLogAnalyzerService._();

  static const int gapThresholdSeconds = 5;
  static const int lifecycleCorrelationWindowSeconds = 5;

  static DiagnosticLogReport analyze(List<DiagnosticLogRow> rows) {
    if (rows.isEmpty) {
      return const DiagnosticLogReport(
        sessionDuration: null,
        fixTotal: 0,
        fixAccepted: 0,
        fixDiscardedAccuracy: 0,
        fixDiscardedJump: 0,
        accuracyMin: null,
        accuracyMedian: null,
        accuracyMax: null,
        satUsedMin: null,
        satUsedMedian: null,
        satUsedMax: null,
        gnssQualityDistribution: {},
        gaps: [],
        gapTotalCumulato: Duration.zero,
        gapPercentOfSession: 0,
        timingPerSpecial: [],
        recoveries: [],
        deviceManufacturer: null,
        deviceModel: null,
        batteryStatus: null,
        gpsProvider: null,
      );
    }

    final sorted = [...rows]..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final sessionDuration = Duration(
        milliseconds: sorted.last.timestampMs - sorted.first.timestampMs);

    // ── Qualità del segnale ──
    var fixTotal = 0;
    var fixAccepted = 0;
    var fixDiscardedAccuracy = 0;
    var fixDiscardedJump = 0;
    final accuracies = <double>[];
    final satUsedList = <int>[];
    final gnssQualityDistribution = <String, int>{};

    for (final r in sorted) {
      if (r.categoria != 'gps_fix') continue;
      fixTotal++;
      final accuracy = double.tryParse(r.campo(3) ?? '');
      if (accuracy != null) accuracies.add(accuracy);
      if (r.evento == 'accettato') {
        fixAccepted++;
        final satUsed = int.tryParse(r.campo(8) ?? '');
        final satVisible = int.tryParse(r.campo(9) ?? '');
        final avgCn0 = double.tryParse(r.campo(10) ?? '');
        if (satUsed != null) satUsedList.add(satUsed);
        if (satUsed != null && satVisible != null && avgCn0 != null) {
          final snapshot = GnssStatusSnapshot(
            satellitesVisible: satVisible,
            satellitesUsed: satUsed,
            avgCn0: avgCn0,
            constellations: const [],
            hasDualFrequency: false,
          );
          final label = snapshot.quality.label;
          gnssQualityDistribution[label] =
              (gnssQualityDistribution[label] ?? 0) + 1;
        }
      } else if (r.evento == 'scartato-accuracy') {
        fixDiscardedAccuracy++;
      } else if (r.evento == 'scartato-jump') {
        fixDiscardedJump++;
      }
    }

    // ── Continuità: gap + correlazione lifecycle ──
    final lifecycleRows =
        sorted.where((r) => r.categoria == 'lifecycle').toList();
    final gaps = <GapEntry>[];
    var gapTotalMs = 0;
    for (final r in sorted) {
      if (r.categoria != 'gps_gap' || r.evento != 'gap') continue;
      final gapSeconds = double.tryParse(r.campo(1) ?? '');
      if (gapSeconds == null) continue;
      final gapMs = (gapSeconds * 1000).round();
      final end = r.timestamp;
      final start = end.subtract(Duration(milliseconds: gapMs));
      gapTotalMs += gapMs;

      String? nearby;
      Duration? bestDiff;
      for (final lr in lifecycleRows) {
        final diff = lr.timestamp.difference(start).abs();
        if (diff.inSeconds > lifecycleCorrelationWindowSeconds) continue;
        if (bestDiff == null || diff < bestDiff) {
          bestDiff = diff;
          nearby = lr.evento;
        }
      }
      gaps.add(GapEntry(
          start: start,
          duration: Duration(milliseconds: gapMs),
          nearbyLifecycleEvent: nearby));
    }
    final gapPercent = sessionDuration.inMilliseconds == 0
        ? 0.0
        : gapTotalMs * 100 / sessionDuration.inMilliseconds;

    // ── Timing per PS ──
    final gateInfo = <String, (double fractionT, double distM)>{};
    final radiusReasons = <String, String>{};
    final entryMethod = <String, String>{};
    final exitMethod = <String, String>{};
    final recoveries = <RecoveryEntry>[];
    final specialIds = <String>{};

    for (final r in sorted) {
      if (r.categoria == 'timing') {
        if (r.evento == 'porta') {
          final wpId = r.campo(1);
          final fractionT = double.tryParse(r.campo(3) ?? '');
          final dist = double.tryParse(r.campo(4) ?? '');
          if (wpId != null && fractionT != null && dist != null) {
            gateInfo[wpId] = (fractionT, dist);
          }
        } else if (r.evento == 'raggio_fallback') {
          final wpId = r.campo(1);
          if (wpId != null) radiusReasons[wpId] = r.campo(2) ?? '';
        } else if (r.evento == 'recovery') {
          final specId = r.campo(1);
          final metodo = r.campo(2);
          if (specId != null && metodo != null) {
            recoveries.add(RecoveryEntry(
                timestamp: r.timestamp, specialeId: specId, metodo: metodo));
          }
        } else if (r.evento == 'ps_ingresso') {
          final specId = r.campo(1);
          final metodo = r.campo(2);
          if (specId != null && metodo != null) {
            entryMethod[specId] = metodo;
            specialIds.add(specId);
          }
        } else if (r.evento == 'ps_uscita') {
          final specId = r.campo(1);
          final metodo = r.campo(2);
          if (specId != null && metodo != null) {
            exitMethod[specId] = metodo;
            specialIds.add(specId);
          }
        }
      }
    }

    // Il log non registra quale waypoint (inizio/fine) appartiene a quale
    // PS: usiamo l'ordine di apparizione dei campi porta/raggio come
    // corrispondenza best-effort (ogni waypointId è unico per costruzione,
    // ma il log salva solo l'id, non a quale specialeId appartiene) — qui
    // ci limitiamo a riportare metodo per PS; distanza/frazione sono
    // disponibili solo quando l'id waypoint compare anche altrove nel
    // report testuale grezzo, quindi restano associate ai soli metodi
    // 'gate' letti da ps_ingresso/ps_uscita quando l'unico waypoint gated
    // registrato in quella finestra corrisponde.
    final timingPerSpecial = <TimingSpecialInfo>[];
    for (final specId in specialIds) {
      timingPerSpecial.add(TimingSpecialInfo(
        specialeId: specId,
        metodoIngresso: entryMethod[specId],
        metodoUscita: exitMethod[specId],
      ));
    }

    // ── Configurazione ──
    final deviceRow =
        sorted.where((r) => r.categoria == 'device' && r.evento == 'info').firstOrNull;

    return DiagnosticLogReport(
      sessionDuration: sessionDuration,
      fixTotal: fixTotal,
      fixAccepted: fixAccepted,
      fixDiscardedAccuracy: fixDiscardedAccuracy,
      fixDiscardedJump: fixDiscardedJump,
      accuracyMin: _min(accuracies),
      accuracyMedian: _median(accuracies),
      accuracyMax: _max(accuracies),
      satUsedMin: _min(satUsedList)?.toInt(),
      satUsedMedian: _median(satUsedList.map((e) => e.toDouble()).toList())?.round(),
      satUsedMax: _max(satUsedList)?.toInt(),
      gnssQualityDistribution: gnssQualityDistribution,
      gaps: gaps,
      gapTotalCumulato: Duration(milliseconds: gapTotalMs),
      gapPercentOfSession: gapPercent,
      timingPerSpecial: timingPerSpecial,
      recoveries: recoveries,
      deviceManufacturer: deviceRow?.campo(1),
      deviceModel: deviceRow?.campo(2),
      batteryStatus: deviceRow?.campo(3),
      gpsProvider: deviceRow?.campo(4),
    );
  }

  static double? _min(List<num> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a < b ? a : b).toDouble();
  }

  static double? _max(List<num> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b).toDouble();
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  // ── Esportazione ──

  static String toText(DiagnosticLogReport r) {
    final buf = StringBuffer();
    buf.writeln('=== CCR — Report log diagnostico ===');
    buf.writeln();
    buf.writeln('-- Configurazione --');
    buf.writeln('Dispositivo: ${r.deviceManufacturer ?? '?'} ${r.deviceModel ?? ''}');
    buf.writeln('Batteria: ${r.batteryStatus ?? '?'}');
    buf.writeln('Provider GPS: ${r.gpsProvider ?? '?'}');
    buf.writeln();
    buf.writeln('-- Qualità del segnale --');
    buf.writeln('Durata sessione: ${_fmtDuration(r.sessionDuration)}');
    buf.writeln('Fix totali: ${r.fixTotal} (accettati: ${r.fixAccepted})');
    buf.writeln('Scartati accuracy: ${r.fixDiscardedAccuracy} '
        '(${r.discardedAccuracyPercent?.toStringAsFixed(1) ?? '?'}%)');
    buf.writeln('Scartati jump: ${r.fixDiscardedJump} '
        '(${r.discardedJumpPercent?.toStringAsFixed(1) ?? '?'}%)');
    buf.writeln('Accuracy dichiarata — min: ${r.accuracyMin?.toStringAsFixed(1) ?? '?'}m, '
        'mediana: ${r.accuracyMedian?.toStringAsFixed(1) ?? '?'}m, '
        'max: ${r.accuracyMax?.toStringAsFixed(1) ?? '?'}m');
    buf.writeln('Satelliti usati — min: ${r.satUsedMin ?? '?'}, '
        'mediano: ${r.satUsedMedian ?? '?'}, max: ${r.satUsedMax ?? '?'}');
    buf.writeln('Distribuzione qualità GNSS: ${r.gnssQualityDistribution}');
    buf.writeln();
    buf.writeln('-- Continuità --');
    buf.writeln('Gap totali (>${gapThresholdSeconds}s): ${r.gaps.length}');
    buf.writeln('Gap cumulato: ${_fmtDuration(r.gapTotalCumulato)} '
        '(${r.gapPercentOfSession.toStringAsFixed(1)}% della sessione)');
    for (final g in r.gaps) {
      buf.writeln('  ${g.start.toIso8601String()} — durata ${g.duration.inSeconds}s'
          '${g.nearbyLifecycleEvent != null ? ' — vicino a "${g.nearbyLifecycleEvent}"' : ''}');
    }
    buf.writeln();
    buf.writeln('-- Timing --');
    for (final t in r.timingPerSpecial) {
      buf.writeln('  PS ${t.specialeId}: ingresso=${t.metodoIngresso ?? '?'} '
          'uscita=${t.metodoUscita ?? '?'}');
    }
    buf.writeln('Recovery attivati: ${r.recoveries.length}');
    for (final rec in r.recoveries) {
      buf.writeln('  ${rec.timestamp.toIso8601String()} — ${rec.specialeId}: ${rec.metodo}');
    }
    return buf.toString();
  }

  static String toCsv(DiagnosticLogReport r) {
    final buf = StringBuffer('sezione,chiave,valore\n');
    buf.writeln('configurazione,dispositivo,${r.deviceManufacturer ?? ''} ${r.deviceModel ?? ''}');
    buf.writeln('configurazione,batteria,${r.batteryStatus ?? ''}');
    buf.writeln('configurazione,provider_gps,${r.gpsProvider ?? ''}');
    buf.writeln('qualita_segnale,durata_sessione_s,${r.sessionDuration?.inSeconds ?? ''}');
    buf.writeln('qualita_segnale,fix_totali,${r.fixTotal}');
    buf.writeln('qualita_segnale,fix_accettati,${r.fixAccepted}');
    buf.writeln('qualita_segnale,scartati_accuracy,${r.fixDiscardedAccuracy}');
    buf.writeln('qualita_segnale,scartati_jump,${r.fixDiscardedJump}');
    buf.writeln('qualita_segnale,accuracy_min_m,${r.accuracyMin ?? ''}');
    buf.writeln('qualita_segnale,accuracy_mediana_m,${r.accuracyMedian ?? ''}');
    buf.writeln('qualita_segnale,accuracy_max_m,${r.accuracyMax ?? ''}');
    buf.writeln('qualita_segnale,sat_usati_min,${r.satUsedMin ?? ''}');
    buf.writeln('qualita_segnale,sat_usati_mediano,${r.satUsedMedian ?? ''}');
    buf.writeln('qualita_segnale,sat_usati_max,${r.satUsedMax ?? ''}');
    buf.writeln('continuita,gap_totali,${r.gaps.length}');
    buf.writeln('continuita,gap_cumulato_s,${r.gapTotalCumulato.inSeconds}');
    buf.writeln('continuita,gap_percento_sessione,${r.gapPercentOfSession.toStringAsFixed(2)}');
    for (var i = 0; i < r.gaps.length; i++) {
      final g = r.gaps[i];
      buf.writeln('gap,${g.start.toIso8601String()},'
          '${g.duration.inSeconds}s${g.nearbyLifecycleEvent != null ? ' (${g.nearbyLifecycleEvent})' : ''}');
    }
    for (final t in r.timingPerSpecial) {
      buf.writeln('timing,${t.specialeId}_ingresso,${t.metodoIngresso ?? ''}');
      buf.writeln('timing,${t.specialeId}_uscita,${t.metodoUscita ?? ''}');
    }
    for (final rec in r.recoveries) {
      buf.writeln('recovery,${rec.timestamp.toIso8601String()},${rec.specialeId}:${rec.metodo}');
    }
    return buf.toString();
  }

  static String _fmtDuration(Duration? d) {
    if (d == null) return '?';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }
}
