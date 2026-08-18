import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

/// Step 47, Parte 2E — vista admin dei tentativi per pilota su un evento di
/// allenamento: un pilota per riquadro, i suoi tentativi (in corso o
/// completati) con orario di partenza e durata.
class TrainingAttemptsScreen extends ConsumerWidget {
  final String eventId;
  const TrainingAttemptsScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrationsAsync = ref.watch(registrationsProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Tentativi per pilota')),
      body: registrationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Errore: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (registrations) {
          final approved = registrations
              .where((r) => r.stato == RegistrationStatus.approvato)
              .toList()
            ..sort((a, b) => '${a.nome} ${a.cognome}'
                .compareTo('${b.nome} ${b.cognome}'));
          if (approved.isEmpty) {
            return const Center(
              child: Text('Nessun pilota iscritto',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: approved.length,
            itemBuilder: (context, i) =>
                _PilotAttemptsCard(eventId: eventId, registration: approved[i]),
          );
        },
      ),
    );
  }
}

class _PilotAttemptsCard extends ConsumerWidget {
  final String eventId;
  final RegistrationModel registration;
  const _PilotAttemptsCard({required this.eventId, required this.registration});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(
        attemptsStreamProvider((eventId: eventId, userId: registration.userId)));

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
          Text('${registration.nome} ${registration.cognome}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          if (registration.teamName != null)
            Text(registration.teamName!,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          attemptsAsync.when(
            loading: () => const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Text('Errore: $e',
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
            data: (attempts) {
              if (attempts.isEmpty) {
                return const Text('Nessun tentativo',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12));
              }
              return Column(
                children: attempts
                    .map((a) => _AttemptRow(attempt: a))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  final AttemptModel attempt;
  const _AttemptRow({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final inProgress = attempt.isInProgress;
    final durata = attempt.durata;
    final durataStr = durata == null
        ? null
        : '${durata.inMinutes}m ${durata.inSeconds % 60}s';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            inProgress ? Icons.play_circle_outline : Icons.check_circle_outline,
            size: 16,
            color: inProgress ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 8),
          Text('Tentativo ${attempt.attemptNumber}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          const SizedBox(width: 8),
          Text(DateFormat('dd/MM HH:mm').format(attempt.startedAt),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const Spacer(),
          Text(
            inProgress ? 'in corso' : (durataStr ?? '—'),
            style: TextStyle(
                color: inProgress ? AppColors.warning : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
