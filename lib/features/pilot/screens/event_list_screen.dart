import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
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
            content: Text('Errore: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEventId = null);
    }
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
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Errore nel caricamento: $e',
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (events) {
          if (events.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_available,
                          color: AppColors.textSecondary, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Nessuna gara disponibile',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Le gare aperte appariranno qui',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final myRegs = myRegsAsync.valueOrNull ?? [];

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final event = events[i];
              final reg = myRegs
                  .where((r) => r.eventId == event.id)
                  .firstOrNull;

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
