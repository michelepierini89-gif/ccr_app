import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/championship_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../../classifica/widgets/championship_standings_table.dart';

final _champInfoProvider =
    StreamProvider.family<ChampionshipModel?, String>((ref, id) {
  return ref.watch(firestoreServiceProvider).getChampionshipById(id);
});

// ── Standings screen (lato pilota) ────────────────────────────────────────────

class ChampionshipStandingsScreen extends ConsumerWidget {
  final String championshipId;
  const ChampionshipStandingsScreen({
    super.key,
    required this.championshipId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final champAsync = ref.watch(_champInfoProvider(championshipId));
    final champ = champAsync.valueOrNull;
    final color = champ != null
        ? AppColors.specialColors[
            champ.colorIndex.clamp(0, AppColors.specialColors.length - 1)]
        : AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(champ?.nome ?? 'Classifica campionato'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
            onPressed: () =>
                ref.invalidate(championshipStandingsProvider(championshipId)),
          ),
        ],
      ),
      body: champAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
            child: Text('Errore: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (champ) {
          if (champ == null) {
            return const Center(
                child: Text('Campionato non trovato',
                    style: TextStyle(color: AppColors.textSecondary)));
          }
          if (!champ.classPublished) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_empty,
                        color: color.withValues(alpha: 0.5), size: 64),
                    const SizedBox(height: 16),
                    const Text('Classifica non ancora pubblicata',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text(
                        'La classifica del campionato sarà visibile qui '
                        'non appena verrà pubblicata.',
                        style: TextStyle(
                            color: AppColors.textSecondary, height: 1.5),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          final standingsAsync =
              ref.watch(championshipStandingsProvider(championshipId));
          final myEntryIdAsync =
              ref.watch(myChampionshipEntryIdProvider(championshipId));

          return standingsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    const Text('Impossibile calcolare la classifica',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(
                          championshipStandingsProvider(championshipId)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            data: (standings) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.emoji_events, color: color, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(champ.nome,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text(
                                  'Stagione ${champ.stagione} · ${champ.eventIds.length} gare · ${standings.teams.length} classificati',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ChampionshipStandingsTable(
                      teams: standings.teams,
                      color: color,
                      highlightTeamId: myEntryIdAsync.valueOrNull,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
