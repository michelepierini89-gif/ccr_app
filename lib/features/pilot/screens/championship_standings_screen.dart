import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/championship_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';
import '../../admin/screens/championship_screen.dart';

// ── Async provider for standings computation ─────────────────────────────────

final _champStandingsProvider = FutureProvider.family<
    List<ChampStandingEntry>, String>((ref, championshipId) async {
  final svc = ref.read(firestoreServiceProvider);

  // Load championship
  final champSnap = await svc.getChampionshipById(championshipId).first;
  if (champSnap == null || champSnap.eventIds.isEmpty) return [];

  // For each event: load data and compute standings
  final teamTimes = <String, Duration>{};
  final teamEvents = <String, int>{};

  for (final eventId in champSnap.eventIds) {
    final event = await svc.getEvent(eventId);
    if (event == null) continue;

    final passages = await svc.getPassagesOnce(eventId);
    final registrations = await svc.getRegistrationsOnce(eventId);
    final teams = await svc.getTeamsOnce(eventId);
    final withdrawals = await svc.getWithdrawalsOnce(eventId);

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: registrations,
      teams: teams,
      withdrawals: withdrawals,
      liveTracking: const <GpsPointModel>[],
    );

    for (final e in entries) {
      if (e.ritirato || e.tempoTotale == Duration.zero) continue;
      final key = e.teamNome.toLowerCase().trim();
      teamTimes[key] =
          (teamTimes[key] ?? Duration.zero) + e.tempoTotale;
      teamEvents[key] = (teamEvents[key] ?? 0) + 1;
      // Store display name (first occurrence wins)
      _displayNames[key] ??= e.teamNome;
    }
  }

  final result = teamTimes.entries.map((kv) {
    final name = _displayNames[kv.key] ?? kv.key;
    return ChampStandingEntry(
      teamNome: name,
      totalTime: kv.value,
      eventsScored: teamEvents[kv.key] ?? 0,
    );
  }).toList()
    ..sort((a, b) => a.totalTime.compareTo(b.totalTime));

  _displayNames.clear();
  return result;
});

final _champInfoProvider =
    StreamProvider.family<ChampionshipModel?, String>((ref, id) {
  return ref.watch(firestoreServiceProvider).getChampionshipById(id);
});

// Mutable helper — cleared between computations
final _displayNames = <String, String>{};

// ── Standings screen ──────────────────────────────────────────────────────────

class ChampionshipStandingsScreen extends ConsumerWidget {
  final String championshipId;
  const ChampionshipStandingsScreen({
    super.key,
    required this.championshipId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final champAsync = ref.watch(_champInfoProvider(championshipId));
    final standingsAsync = ref.watch(_champStandingsProvider(championshipId));

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
                ref.invalidate(_champStandingsProvider(championshipId)),
          ),
        ],
      ),
      body: standingsAsync.when(
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
                const SizedBox(height: 8),
                const Text(
                    'Controlla la connessione e riprova.',
                    style: TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(
                      _champStandingsProvider(championshipId)),
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
          if (standings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.leaderboard_outlined,
                      color: color.withValues(alpha: 0.5), size: 64),
                  const SizedBox(height: 16),
                  const Text('Nessun dato disponibile',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'I tempi appariranno qui al termine delle gare del campionato.',
                      style: TextStyle(
                          color: AppColors.textSecondary, height: 1.5),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // Championship header
              if (champ != null) ...[
                Container(
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
                              'Stagione ${champ.stagione} · ${champ.eventIds.length} gare · ${standings.length} classificati',
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
                const SizedBox(height: 16),
              ],

              // Podium (top 3)
              if (standings.length >= 2) ...[
                const Text('Podio',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildPodium(standings.take(3).toList(), color),
                const SizedBox(height: 20),
              ],

              // Full table
              const Text('Classifica completa',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...standings.asMap().entries.map((e) {
                final pos = e.key + 1;
                final entry = e.value;
                final podiumColor = _podiumColor(pos);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: podiumColor != null
                          ? podiumColor.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: podiumColor != null
                            ? Icon(_podiumIcon(pos),
                                color: podiumColor, size: 20)
                            : Text(
                                '$pos',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.teamNome,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            Text(
                              '${entry.eventsScored} gare completate',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        entry.totalFormatted,
                        style: TextStyle(
                          color: podiumColor ?? AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPodium(List<ChampStandingEntry> top, Color accentColor) {
    final medals = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final heights = [80.0, 60.0, 50.0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: top.asMap().entries.map((e) {
        final idx = e.key;
        final entry = e.value;
        final c = medals[idx.clamp(0, 2)];
        final h = heights[idx.clamp(0, 2)];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(entry.teamNome,
                    style: TextStyle(
                        color: c, fontSize: 11, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(entry.totalFormatted,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border.all(color: c.withValues(alpha: 0.6)),
                  ),
                  child: Center(
                    child: Text(
                      '${idx + 1}°',
                      style: TextStyle(
                          color: c,
                          fontWeight: FontWeight.w900,
                          fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color? _podiumColor(int pos) => switch (pos) {
        1 => const Color(0xFFFFD700),
        2 => const Color(0xFFC0C0C0),
        3 => const Color(0xFFCD7F32),
        _ => null,
      };

  IconData _podiumIcon(int pos) => switch (pos) {
        1 => Icons.emoji_events,
        2 => Icons.workspace_premium,
        _ => Icons.military_tech,
      };
}
