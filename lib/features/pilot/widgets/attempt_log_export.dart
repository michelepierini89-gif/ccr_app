import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/diagnostic_log_files_service.dart';
import '../../../core/theme/app_colors.dart';

/// Condivide il log tecnico di un tentativo — cercato per finestra oraria
/// (vedi `DiagnosticLogFilesService.forAttempt`), condiviso subito se c'è
/// una sola corrispondenza, altrimenti un elenco a scelta. Usato sia dallo
/// storico tentativi sia dal visualizzatore traccia di un singolo tentativo
/// (punti 2/3 del test sul campo 22/08/2026).
Future<void> exportAttemptDiagnosticLog(
  BuildContext context, {
  required DateTime startedAt,
  DateTime? finishedAt,
}) async {
  final matches = await DiagnosticLogFilesService.instance.forAttempt(
    startedAt: startedAt,
    finishedAt: finishedAt,
  );
  if (!context.mounted) return;
  if (matches.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Nessun log tecnico trovato per questo tentativo'),
    ));
    return;
  }
  if (matches.length == 1) {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(matches.first.file.path)],
      subject: 'CCR — log tecnico tentativo',
    ));
    return;
  }
  final fmt = DateFormat('HH:mm:ss', 'it');
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cardBackground,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Più log trovati per questo tentativo',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
          for (final m in matches)
            ListTile(
              leading: const Icon(Icons.bug_report_outlined,
                  color: AppColors.accent),
              title: Text(fmt.format(m.sessionStart),
                  style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.of(ctx).pop();
                SharePlus.instance.share(ShareParams(
                  files: [XFile(m.file.path)],
                  subject: 'CCR — log tecnico tentativo',
                ));
              },
            ),
        ],
      ),
    ),
  );
}
