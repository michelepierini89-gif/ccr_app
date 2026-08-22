import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Un log tecnico locale (`ccr_diagnostic_{sessionId}.csv`, vedi
/// `DiagnosticLogger.startSession`) — una sessione di registrazione GPS,
/// gara o tentativo di allenamento, produce un file.
class DiagnosticLogFile {
  final File file;
  final int sessionTimestampMs;
  final DateTime sessionStart;
  final int sizeBytes;

  const DiagnosticLogFile({
    required this.file,
    required this.sessionTimestampMs,
    required this.sessionStart,
    required this.sizeBytes,
  });
}

/// Bug segnalato dopo il primo test sul campo di un evento di allenamento
/// (22/08/2026, punto 2): il pulsante "Esporta log tecnico" viveva solo
/// nella schermata di riepilogo post-gara (`RaceResultScreen`), mai
/// raggiungibile in allenamento (nessun riepilogo equivalente, vedi
/// `_finishRace` in `gps_recording_screen.dart` che si limita a uno
/// SnackBar). Il logger stesso è confermato attivo per un tentativo
/// (`GpsService.startRecording` chiama `DiagnosticLogger.startSession`
/// incondizionatamente, indipendentemente da `tipoEvento`) — mancava solo
/// un modo per raggiungere i file già scritti.
///
/// Ogni sessione produce un file separato su disco (mai in Firestore): per
/// esportare il log di un tentativo passato non basta l'ultimo path in
/// memoria (`DiagnosticLogger.currentFilePath`, valido solo per la sessione
/// corrente) — questo servizio elenca tutti i file locali e permette di
/// risalire a quello di un tentativo specifico dall'orario di inizio/fine
/// (nessun collegamento esplicito file↔tentativo è mai stato scritto: un
/// tentativo genera comunque una nuova sessione diagnostica praticamente
/// nello stesso istante, vedi `_startRace`, quindi la finestra oraria basta
/// — best-effort, coerente con lo stile già adottato per l'allenamento allo
/// Step 47/48).
class DiagnosticLogFilesService {
  DiagnosticLogFilesService._();
  static final DiagnosticLogFilesService instance =
      DiagnosticLogFilesService._();

  static final RegExp _fileNamePattern =
      RegExp(r'^ccr_diagnostic_(\d+)\.csv$');

  /// Tutti i log tecnici locali, più recente prima. Sempre vuota su web
  /// (`DiagnosticLogger.isActive` è sempre `false` lì, nessun file scritto).
  Future<List<DiagnosticLogFile>> listAll() async {
    if (kIsWeb) return const [];
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!dir.existsSync()) return const [];
      final result = <DiagnosticLogFile>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final match = _fileNamePattern.firstMatch(name);
        if (match == null) continue;
        final ts = int.tryParse(match.group(1)!);
        if (ts == null) continue;
        final size = await entity.length();
        result.add(DiagnosticLogFile(
          file: entity,
          sessionTimestampMs: ts,
          sessionStart: DateTime.fromMillisecondsSinceEpoch(ts),
          sizeBytes: size,
        ));
      }
      result.sort(
          (a, b) => b.sessionTimestampMs.compareTo(a.sessionTimestampMs));
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Log la cui sessione ricade nella finestra temporale di un tentativo —
  /// tolleranza di 2 minuti prima dell'inizio (differenza fra creazione del
  /// tentativo su Firestore e apertura effettiva del file, entrambe
  /// asincrone) e fino a fine tentativo (o ad ora se ancora in corso), più 2
  /// minuti oltre per coprire l'ultimo flush.
  Future<List<DiagnosticLogFile>> forAttempt({
    required DateTime startedAt,
    DateTime? finishedAt,
  }) async {
    final all = await listAll();
    final lowerBound = startedAt.subtract(const Duration(minutes: 2));
    final upperBound =
        (finishedAt ?? DateTime.now()).add(const Duration(minutes: 2));
    return all
        .where((f) =>
            f.sessionStart.isAfter(lowerBound) &&
            f.sessionStart.isBefore(upperBound))
        .toList();
  }
}
