import 'dart:convert';
import 'track_smoother.dart';

/// Una riga del CSV prodotto da [DiagnosticLogger] (colonne fisse
/// `timestamp_ms,categoria,evento,campo1..campo12`, vedi
/// `diagnostic_logger.dart`), riletta da un file esportato dal pilota.
/// Condivisa tra il banco di replay (Parte 1A, sorgente "log diagnostico")
/// e l'analizzatore log (Parte 2) — un solo parser, nessuna duplicazione.
class DiagnosticLogRow {
  final int timestampMs;
  final String categoria;
  final String evento;
  final List<String?> campi;

  const DiagnosticLogRow({
    required this.timestampMs,
    required this.categoria,
    required this.evento,
    required this.campi,
  });

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  /// 1-based, come nella documentazione dei metodi `log*` di
  /// [DiagnosticLogger] (campo1..campo12).
  String? campo(int n) =>
      (n >= 1 && n <= campi.length) ? campi[n - 1] : null;
}

class DiagnosticLogParser {
  DiagnosticLogParser._();

  static List<DiagnosticLogRow> parse(String csvContent) {
    final lines = const LineSplitter().convert(csvContent);
    if (lines.length < 2) return [];
    final rows = <DiagnosticLogRow>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final fields = _splitCsvLine(line);
      if (fields.length < 3) continue;
      final ts = int.tryParse(fields[0]);
      if (ts == null) continue;
      final campi = <String?>[];
      for (var c = 3; c < fields.length; c++) {
        campi.add(fields[c].isEmpty ? null : fields[c]);
      }
      while (campi.length < 12) {
        campi.add(null);
      }
      rows.add(DiagnosticLogRow(
        timestampMs: ts,
        categoria: fields[1],
        evento: fields[2],
        campi: campi,
      ));
    }
    return rows;
  }

  /// Split CSV consapevole delle virgolette (i testi degli annunci vocali
  /// possono contenere virgole) — stesso schema di quoting scritto da
  /// [DiagnosticLogger._csvField].
  static List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          result.add(buf.toString());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
    }
    result.add(buf.toString());
    return result;
  }

  /// Estrae i fix GPS accettati come [RawTrackSample] — Parte 1A, sorgente
  /// "log diagnostico" per il banco di replay. campo1=latRaw, campo2=lngRaw,
  /// campo3=accuracy (righe `gps_fix,accettato`).
  static List<RawTrackSample> extractAcceptedGpsSamples(
      List<DiagnosticLogRow> rows) {
    final samples = <RawTrackSample>[];
    for (final r in rows) {
      if (r.categoria != 'gps_fix' || r.evento != 'accettato') continue;
      final lat = double.tryParse(r.campo(1) ?? '');
      final lng = double.tryParse(r.campo(2) ?? '');
      if (lat == null || lng == null) continue;
      final acc = double.tryParse(r.campo(3) ?? '') ?? 5.0;
      samples.add(RawTrackSample(lat: lat, lng: lng, accuracy: acc, timestamp: r.timestamp));
    }
    return samples;
  }
}
