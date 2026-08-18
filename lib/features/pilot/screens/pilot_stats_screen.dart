import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/pilot_stats_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar_by_id.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pilot_stats_provider.dart';
import '../providers/training_stats_provider.dart';
import '../widgets/preferred_team_picker.dart';

class PilotStatsScreen extends ConsumerWidget {
  const PilotStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(pilotStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Le mie statistiche'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
            onPressed: () => ref.invalidate(pilotStatsProvider),
          ),
        ],
      ),
      body: SafeArea(bottom: true, child: statsAsync.when(
        loading: () => const _StatsSkeleton(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Impossibile calcolare le statistiche',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(pilotStatsProvider),
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
        data: (stats) {
          if (!stats.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                        size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Nessuna gara disputata ancora.\nIscriviti al prossimo evento!',
                      style: TextStyle(
                          color: AppColors.textSecondary, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatCard(
                icon: Icons.flag_outlined,
                color: AppColors.accent,
                label: 'Gare disputate',
                value: stats.gareDisputate,
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.emoji_events,
                color: AppColors.warning,
                label: 'Gare vinte',
                value: stats.gareVinte,
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.military_tech,
                color: AppColors.success,
                label: 'Gare a podio (top 3)',
                value: stats.garePodio,
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.bolt,
                color: AppColors.warning,
                label: 'Speciali vinte',
                value: stats.specialiVinte,
              ),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.workspace_premium,
                color: AppColors.success,
                label: 'Speciali a podio',
                value: stats.specialiPodio,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.textSecondary, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Le statistiche si basano sui risultati della squadra: '
                        'una vittoria di squadra conta come vittoria per tutti i piloti della squadra.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _PreferredTeamSection(stats: stats),
              const SizedBox(height: 24),
              const _TrainingStatsSection(),
            ],
          );
        },
      ),
      ),
    );
  }
}

/// Step 47, Parte 2F — sezione dedicata all'allenamento: tentativi
/// effettuati e migliori tempi personali, separata dalle statistiche di
/// gara sopra (che non la includono).
class _TrainingStatsSection extends ConsumerWidget {
  const _TrainingStatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainingAsync = ref.watch(trainingStatsProvider);
    return trainingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.repeat, color: AppColors.accent, size: 18),
                SizedBox(width: 8),
                Text('Allenamento',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            for (final ev in events)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ev.eventNome,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${ev.tentativiCompletati} tentativ${ev.tentativiCompletati == 1 ? 'o' : 'i'} · '
                      '${ev.migliorTempoPersonalePerPs.length} PS con miglior tempo personale',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
                color: color, fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonBox(width: double.infinity, height: 80, radius: 12),
        ),
      ),
    );
  }
}

/// Sezione statistiche ristrette alla squadra preferita — o l'invito a
/// impostarne una, con collegamento diretto all'azione, se il pilota non
/// l'ha ancora fatto.
class _PreferredTeamSection extends ConsumerWidget {
  final PilotStatsModel stats;
  const _PreferredTeamSection({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferredTeamName =
        ref.watch(currentUserModelProvider).valueOrNull?.preferredTeamName;

    if (preferredTeamName == null || preferredTeamName.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.star_border, color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text('Squadra preferita',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Impostane una per vedere qui le statistiche calcolate solo '
              'sulle gare disputate insieme e i compagni con cui hai corso '
              'più spesso.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => showPreferredTeamPicker(context, ref),
                icon: const Icon(Icons.star, size: 18),
                label: const Text('Imposta squadra preferita'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!stats.hasPreferredTeamData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Nessuna gara disputata ancora con "$preferredTeamName".',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Con "$preferredTeamName"',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => showPreferredTeamPicker(context, ref),
                child: const Text('Cambia'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MiniStatRow(
              label: 'Gare disputate insieme',
              value: stats.preferredTeamGareDisputate),
          _MiniStatRow(
              label: 'Gare vinte', value: stats.preferredTeamGareVinte),
          _MiniStatRow(
              label: 'Gare a podio', value: stats.preferredTeamGarePodio),
          _MiniStatRow(
              label: 'Speciali vinte',
              value: stats.preferredTeamSpecialiVinte),
          _MiniStatRow(
              label: 'Speciali a podio',
              value: stats.preferredTeamSpecialiPodio),
          if (stats.preferredTeamCompagni.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Compagni più frequenti',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...stats.preferredTeamCompagni.map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    UserAvatarById(
                      userId: c.userId,
                      fallbackNome: c.nome,
                      fallbackCognome: c.cognome,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.nomeCompleto.isEmpty ? c.userId : c.nomeCompleto,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${c.gareInsieme} gar${c.gareInsieme == 1 ? 'a' : 'e'}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStatRow extends StatelessWidget {
  final String label;
  final int value;
  const _MiniStatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text('$value',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
