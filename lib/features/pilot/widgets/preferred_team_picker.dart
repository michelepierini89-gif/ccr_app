import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/pilot_stats_provider.dart';

/// Apre un bottom sheet con l'elenco delle squadre con cui il pilota ha già
/// corso (da [pilotStatsProvider], calcolato sulle iscrizioni approvate —
/// nessun bisogno di essere dentro un evento specifico) per scegliere/
/// cambiare la squadra preferita. Usato dal profilo pilota e dall'invito
/// nella pagina statistiche.
Future<void> showPreferredTeamPicker(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) return;

  final messenger = ScaffoldMessenger.of(context);

  List<String> teamNames;
  try {
    teamNames = (await ref.read(pilotStatsProvider.future)).raceTeamNames;
  } catch (_) {
    teamNames = const [];
  }

  if (!context.mounted) return;

  if (teamNames.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
            'Devi aver corso almeno una gara con una squadra prima di poterla impostare come preferita.'),
        backgroundColor: AppColors.warning,
      ),
    );
    return;
  }

  final currentPreferred =
      ref.read(currentUserModelProvider).valueOrNull?.preferredTeamName;

  final chosen = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.cardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scegli la squadra preferita',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tra le squadre con cui hai già corso.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...teamNames.map((name) {
              final isCurrent = currentPreferred != null &&
                  currentPreferred.trim().toLowerCase() ==
                      name.trim().toLowerCase();
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.star : Icons.star_border,
                  color: isCurrent ? AppColors.warning : AppColors.textSecondary,
                ),
                title: Text(name,
                    style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.of(ctx).pop(name),
              );
            }),
          ],
        ),
      ),
    ),
  );

  if (chosen == null || !context.mounted) return;

  try {
    await ref.read(firestoreServiceProvider).savePreferredTeamName(uid, chosen);
    ref.invalidate(currentUserModelProvider);
    ref.invalidate(pilotStatsProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('"$chosen" impostata come squadra preferita'),
        backgroundColor: AppColors.success,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.error),
    );
  }
}
