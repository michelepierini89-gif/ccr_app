import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/diagnostic_log_analyzer_service.dart';
import '../../../core/services/diagnostic_log_parser.dart';
import '../../../core/theme/app_colors.dart';

/// Schermata admin "Analizza log diagnostico" (Parte 2): importa un CSV
/// prodotto da `DiagnosticLogger` e ne mostra un riepilogo automatico —
/// qualità segnale, continuità/gap, timing PS, configurazione device.
class DiagnosticLogAnalyzerScreen extends StatefulWidget {
  const DiagnosticLogAnalyzerScreen({super.key});

  @override
  State<DiagnosticLogAnalyzerScreen> createState() =>
      _DiagnosticLogAnalyzerScreenState();
}

class _DiagnosticLogAnalyzerScreenState
    extends State<DiagnosticLogAnalyzerScreen> {
  String? _fileName;
  DiagnosticLogReport? _report;
  String? _error;

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    try {
      final content = utf8.decode(bytes);
      final rows = DiagnosticLogParser.parse(content);
      if (rows.isEmpty) {
        setState(() {
          _error = 'Nessuna riga valida trovata nel CSV';
          _report = null;
          _fileName = result.files.single.name;
        });
        return;
      }
      final report = DiagnosticLogAnalyzerService.analyze(rows);
      setState(() {
        _fileName = result.files.single.name;
        _report = report;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore lettura CSV: $e';
        _report = null;
      });
    }
  }

  Future<void> _exportText() async {
    final report = _report;
    if (report == null) return;
    final text = DiagnosticLogAnalyzerService.toText(report);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(utf8.encode(text),
            name: 'report_diagnostico.txt', mimeType: 'text/plain'),
      ],
      subject: 'CCR — report log diagnostico',
    ));
  }

  Future<void> _exportCsv() async {
    final report = _report;
    if (report == null) return;
    final csv = DiagnosticLogAnalyzerService.toCsv(report);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(utf8.encode(csv),
            name: 'report_diagnostico.csv', mimeType: 'text/csv'),
      ],
      subject: 'CCR — report log diagnostico',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Analizza log diagnostico',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (report != null) ...[
            IconButton(
              tooltip: 'Esporta testo',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: _exportText,
            ),
            IconButton(
              tooltip: 'Esporta CSV',
              icon: const Icon(Icons.download),
              onPressed: _exportCsv,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _importCsv,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Importa log CSV'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text(_fileName!,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
            if (report != null) ...[
              const SizedBox(height: 24),
              _section('Configurazione', [
                _row('Dispositivo',
                    '${report.deviceManufacturer ?? '?'} ${report.deviceModel ?? ''}'),
                _row('Batteria', report.batteryStatus ?? '?'),
                _row('Provider GPS', report.gpsProvider ?? '?'),
              ]),
              _section('Qualità del segnale', [
                _row('Durata sessione', _fmtDuration(report.sessionDuration)),
                _row('Fix totali / accettati',
                    '${report.fixTotal} / ${report.fixAccepted}'),
                _row('Scartati accuracy',
                    '${report.fixDiscardedAccuracy} (${report.discardedAccuracyPercent?.toStringAsFixed(1) ?? '?'}%)'),
                _row('Scartati jump',
                    '${report.fixDiscardedJump} (${report.discardedJumpPercent?.toStringAsFixed(1) ?? '?'}%)'),
                _row('Accuracy (min/mediana/max)',
                    '${_fmtM(report.accuracyMin)} / ${_fmtM(report.accuracyMedian)} / ${_fmtM(report.accuracyMax)}'),
                _row('Satelliti usati (min/mediano/max)',
                    '${report.satUsedMin ?? '?'} / ${report.satUsedMedian ?? '?'} / ${report.satUsedMax ?? '?'}'),
                _row('Distribuzione qualità GNSS',
                    report.gnssQualityDistribution.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join(', ')),
              ]),
              _section('Continuità', [
                _row('Gap totali (>5s)', '${report.gaps.length}'),
                _row('Gap cumulato',
                    '${_fmtDuration(report.gapTotalCumulato)} (${report.gapPercentOfSession.toStringAsFixed(1)}% sessione)'),
              ]),
              if (report.gaps.isNotEmpty)
                _gapsTable(report),
              _section('Timing', [
                _row('Recovery attivati', '${report.recoveries.length}'),
              ]),
              if (report.timingPerSpecial.isNotEmpty)
                _timingTable(report),
              if (report.recoveries.isNotEmpty)
                _recoveriesTable(report),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _gapsTable(DiagnosticLogReport report) {
    return _section('Elenco gap', [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.cardBackground),
          columns: const [
            DataColumn(label: Text('Inizio')),
            DataColumn(label: Text('Durata')),
            DataColumn(label: Text('Vicino a')),
          ],
          rows: [
            for (final g in report.gaps)
              DataRow(cells: [
                DataCell(Text(g.start.toString())),
                DataCell(Text('${g.duration.inSeconds}s')),
                DataCell(Text(g.nearbyLifecycleEvent ?? '—')),
              ]),
          ],
        ),
      ),
    ]);
  }

  Widget _timingTable(DiagnosticLogReport report) {
    return _section('Timing per speciale', [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.cardBackground),
          columns: const [
            DataColumn(label: Text('PS')),
            DataColumn(label: Text('Metodo ingresso')),
            DataColumn(label: Text('Metodo uscita')),
          ],
          rows: [
            for (final t in report.timingPerSpecial)
              DataRow(cells: [
                DataCell(Text(t.specialeId)),
                DataCell(Text(t.metodoIngresso ?? '—')),
                DataCell(Text(t.metodoUscita ?? '—')),
              ]),
          ],
        ),
      ),
    ]);
  }

  Widget _recoveriesTable(DiagnosticLogReport report) {
    return _section('Recovery attivati', [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.cardBackground),
          columns: const [
            DataColumn(label: Text('Orario')),
            DataColumn(label: Text('Speciale')),
            DataColumn(label: Text('Metodo')),
          ],
          rows: [
            for (final rec in report.recoveries)
              DataRow(cells: [
                DataCell(Text(rec.timestamp.toString())),
                DataCell(Text(rec.specialeId)),
                DataCell(Text(rec.metodo)),
              ]),
          ],
        ),
      ),
    ]);
  }

  String _fmtM(double? v) => v == null ? '?' : '${v.toStringAsFixed(1)}m';

  String _fmtDuration(Duration? d) {
    if (d == null) return '?';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }
}
