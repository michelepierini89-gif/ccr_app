import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../providers/pilot_provider.dart';
import '../widgets/event_card_pilot.dart';

class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: 4,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 200, height: 18),
              const SizedBox(height: 10),
              SkeletonBox(width: 150, height: 12),
              const SizedBox(height: 8),
              SkeletonBox(width: 120, height: 12),
              const SizedBox(height: 16),
              SkeletonBox(width: double.infinity, height: 40, radius: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object e, WidgetRef ref) {
    return ListView(
      children: [
        const SizedBox(height: 60),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off,
                    color: AppColors.error, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Impossibile caricare le gare',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Controlla la connessione a internet e riprova.',
                  style: TextStyle(
                      color: AppColors.textSecondary, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(openEventsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(WidgetRef ref) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.flag_outlined,
                      color: AppColors.accent, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nessuna gara disponibile',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Non ci sono gare aperte al momento.\nContatta l\'organizzatore per informazioni.',
                  style: TextStyle(
                      color: AppColors.textSecondary, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(openEventsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Aggiorna'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(openEventsProvider);
    final myRegsAsync = ref.watch(myRegistrationsProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () async => ref.invalidate(openEventsProvider),
      child: eventsAsync.when(
        loading: _buildSkeleton,
        error: (e, _) => _buildError(e, ref),
        data: (events) {
          if (events.isEmpty) return _buildEmpty(ref);

          final myRegs = myRegsAsync.valueOrNull ?? [];

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final event = events[i];
              final reg =
                  myRegs.where((r) => r.eventId == event.id).firstOrNull;

              return EventCardPilot(
                event: event,
                registration: reg,
                isLoading: false,
                onTap: () => context.push('/pilot/event/${event.id}'),
                // Navigate to event detail where the 2-step dialog is shown
                onRegister: reg == null
                    ? () => context.push('/pilot/event/${event.id}')
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
