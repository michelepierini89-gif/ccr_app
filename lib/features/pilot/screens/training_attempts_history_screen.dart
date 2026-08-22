import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format_utils.dart';
import '../providers/training_attempts_history_provider.dart';
import '../widgets/attempt_log_export.dart';
import 'training_attempt_track_screen.dart';

/// Storico dei tentativi del pilota su un evento di allenamento (punto 3
/// del test sul campo 22/08/2026) — data/ora, durata, tempo per ogni PS con
/// indicazione di record personale e "conta per la classifica", CP mancati
/// e penalità, stato. Più recente prima (stesso ordine di
/// `myAttemptsHistoryProvider`).
class TrainingAttemptsHistoryScreen extends ConsumerWidget {
  final String eventId;
  const TrainingAttemptsHistoryScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(myAttemptsHistoryProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('I miei tentativi')),
      body: SafeArea(
        bottom: true,
        child: historyAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent)),
          error: (e, _) => Center(
              child: Text('Errore: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (entries) {
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nessun tentativo ancora. Avvia il GPS per registrare il '
                    'primo.',
                    style: TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (ctx, i) =>
                  _AttemptCard(eventId: eventId, entry: entries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  final String eventId;
  final AttemptHistoryEntry entry;
  const _AttemptCard({required this.eventId, required this.entry});

  (String, Color) _statusLabel() {
    switch (entry.attempt.status) {
      case AttemptStatus.completed:
        return ('COMPLETATO', AppColors.success);
      case AttemptStatus.inProgress:
        return ('IN CORSO', AppColors.warning);
      case AttemptStatus.abandoned:
        return ('ABBANDONATO', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm', 'it');
    final (statusText, statusColor) = _statusLabel();
    final durata = entry.attempt.durata;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tentativo ${entry.attempt.attemptNumber}',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text(fmtDate.format(entry.attempt.startedAt.toLocal()),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          if (durata != null) ...[
            const SizedBox(height: 4),
            Text('Durata: ${TimeFormatUtils.formatRaceTime(durata)}',
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          for (final row in entry.speciali) _SpecialRow(row: row),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrainingAttemptTrackScreen(
                        eventId: eventId,
                        attempt: entry.attempt,
                        speciali: entry.speciali,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                  ),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Traccia'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => exportAttemptDiagnosticLog(
                    context,
                    startedAt: entry.attempt.startedAt,
                    finishedAt: entry.attempt.finishedAt,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  icon: const Icon(Icons.bug_report_outlined, size: 16),
                  label: const Text('Log'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpecialRow extends StatelessWidget {
  final AttemptSpecialRow row;
  const _SpecialRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final tempo = row.tempo;
    final done = tempo != null;
    final hasMissedCp =
        done && !tempo.controlPointsOk && !tempo.skipped && !tempo.notDetected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.specialeNome,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
              ),
              if (row.countsForClassifica)
                Tooltip(
                  message: 'Il giro che conta per la classifica',
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border:
                          Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                    ),
                    child: const Text('CLASSIFICA',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              if (row.isPersonalRecord)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                  ),
                  child: const Text('RECORD',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
              Text(
                done ? tempo.tempoFormatted : '—',
                style: TextStyle(
                  color: done ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: done ? FontWeight.bold : FontWeight.normal,
                  fontFamily: done ? 'monospace' : null,
                ),
              ),
            ],
          ),
          if (done && tempo.skipped)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('⏭ Salto volontario — penalità applicata',
                  style: TextStyle(color: AppColors.warning, fontSize: 11)),
            )
          else if (done && tempo.notDetected)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('⚠ Tempo forfettario applicato — speciale non rilevata',
                  style: TextStyle(color: AppColors.warning, fontSize: 11)),
            )
          else if (hasMissedCp)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '⚠ ${tempo.missedCpPositions.length} CP mancati'
                '${tempo.penaltySeconds > 0 ? ' — +${tempo.penaltySeconds}s penalità' : ''}',
                style: const TextStyle(color: AppColors.warning, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
