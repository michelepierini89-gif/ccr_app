import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../providers/pilot_stats_provider.dart';

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
      body: statsAsync.when(
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
            ],
          );
        },
      ),
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
