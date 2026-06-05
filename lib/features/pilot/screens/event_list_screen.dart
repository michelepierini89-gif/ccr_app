import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/pilot_provider.dart';
import '../widgets/event_card_pilot.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  String? _loadingEventId;

  Future<void> _quickRegister(String eventId) async {
    final user = ref.read(currentUserModelProvider).valueOrNull;
    if (user == null) return;
    setState(() => _loadingEventId = eventId);
    try {
      await ref.read(firestoreServiceProvider).registerForEvent(
            eventId: eventId,
            userId: user.id,
            nome: user.nome,
            cognome: user.cognome,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Iscrizione inviata! In attesa di approvazione.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Impossibile inviare l\'iscrizione: controlla la connessione e riprova.'),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Riprova',
              textColor: Colors.white,
              onPressed: () => _quickRegister(eventId),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEventId = null);
    }
  }

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

  Widget _buildError(Object e) {
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

  Widget _buildEmpty() {
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
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(openEventsProvider);
    final myRegsAsync = ref.watch(myRegistrationsProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () async => ref.invalidate(openEventsProvider),
      child: eventsAsync.when(
        loading: _buildSkeleton,
        error: (e, _) => _buildError(e),
        data: (events) {
          if (events.isEmpty) return _buildEmpty();

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
                isLoading: _loadingEventId == event.id,
                onTap: () => context.push('/pilot/event/${event.id}'),
                onRegister: reg == null
                    ? () => _quickRegister(event.id)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
