import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
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
    final archivedAsync = ref.watch(archivedEventsProvider);
    final myRegsAsync = ref.watch(myRegistrationsProvider);
    final myArchivedRegsAsync = ref.watch(myArchivedRegistrationsProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () async {
        ref.invalidate(openEventsProvider);
        ref.invalidate(archivedEventsProvider);
      },
      child: eventsAsync.when(
        loading: _buildSkeleton,
        error: (e, _) => _buildError(e, ref),
        data: (events) {
          final myRegs = myRegsAsync.valueOrNull ?? [];
          final myArchivedRegs = myArchivedRegsAsync.valueOrNull ?? [];
          final archivedEventIds =
              myArchivedRegs.map((r) => r.eventId).toSet();
          final archived = (archivedAsync.valueOrNull ?? [])
              .where((e) => archivedEventIds.contains(e.id))
              .toList();

          if (events.isEmpty && archived.isEmpty) return _buildEmpty(ref);

          // Step 47, Parte 2E — sezione distinta per gli eventi di
          // allenamento: sempre disponibili (mai una "data di svolgimento"
          // passata a renderli meno rilevanti), separati dalle gare.
          final races = events.where((e) => !e.isAllenamento).toList();
          final trainings = events.where((e) => e.isAllenamento).toList();

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              // Active events
              for (final event in races)
                _buildEventCard(context, event, myRegs),

              if (trainings.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.repeat,
                          color: AppColors.accent, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Allenamenti',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final event in trainings)
                  _buildEventCard(context, event, myRegs),
              ],

              // Past events section
              if (archived.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.archive_outlined,
                          color: AppColors.textSecondary, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Gare passate',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final event in archived)
                  Opacity(
                    opacity: 0.65,
                    child: EventCardPilot(
                      event: event,
                      registration: myArchivedRegs
                          .where((r) => r.eventId == event.id)
                          .firstOrNull,
                      isLoading: false,
                      onTap: () =>
                          context.push('/pilot/event/${event.id}'),
                      onRegister: null, // no new registrations on archived
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventModel event,
      List<RegistrationModel> myRegs) {
    final reg = myRegs.where((r) => r.eventId == event.id).firstOrNull;
    return EventCardPilot(
      event: event,
      registration: reg,
      isLoading: false,
      onTap: () => context.push('/pilot/event/${event.id}'),
      onRegister:
          reg == null ? () => context.push('/pilot/event/${event.id}') : null,
    );
  }
}
