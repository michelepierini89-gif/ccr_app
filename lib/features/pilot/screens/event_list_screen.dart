import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/pilot_provider.dart';
import '../widgets/event_card_pilot.dart';

class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(openEventsProvider);
    final userAsync = ref.watch(currentUserModelProvider);
    final myRegsAsync = ref.watch(myRegistrationsProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () async {
        ref.invalidate(openEventsProvider);
      },
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
                  .isNotEmpty
                  ? myRegs.firstWhere((r) => r.eventId == event.id)
                  : null;

              return EventCardPilot(
                event: event,
                registration: reg,
                onTap: () => context.push('/pilot/event/${event.id}'),
                onRegister: reg == null
                    ? () async {
                        final user = userAsync.valueOrNull;
                        if (user == null) return;
                        try {
                          await ref
                              .read(firestoreServiceProvider)
                              .registerForEvent(
                                eventId: event.id,
                                userId: user.id,
                                nome: user.nome,
                                cognome: user.cognome,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Iscrizione inviata! In attesa di approvazione.'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Errore: $e'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
