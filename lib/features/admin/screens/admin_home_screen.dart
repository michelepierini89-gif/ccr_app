import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/notification_listener_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../widgets/event_card_admin.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(adminEventsProvider);

    return NotificationListenerWidget(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Text(
              'CCR ',
              style: TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w900),
            ),
            Text('Admin'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: 'Campionati',
            onPressed: () => context.push('/admin/championships'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/create-event'),
        tooltip: 'Nuovo evento',
        child: const Icon(Icons.add),
      ),
      body: eventsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
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
          final active = events
              .where((e) => e.stato != EventStatus.archiviata)
              .toList();
          final archived = events
              .where((e) => e.stato == EventStatus.archiviata)
              .toList();

          if (active.isEmpty && archived.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.event_note,
                      color: AppColors.textSecondary, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Nessun evento',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crea il primo evento.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/admin/create-event'),
                    icon: const Icon(Icons.add),
                    label: const Text('Crea evento'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.cardBackground,
            onRefresh: () async {
              ref.invalidate(adminEventsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              children: [
                // Active / ongoing events
                for (final e in active)
                  _EventCardWithBadge(
                    event: e,
                    onTap: () => context.push('/admin/event/${e.id}'),
                  ),

                // Archived events section
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
                  for (final e in archived)
                    Opacity(
                      opacity: 0.65,
                      child: _EventCardWithBadge(
                        event: e,
                        onTap: () => context.push('/admin/event/${e.id}'),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    ));
  }
}

class _EventCardWithBadge extends ConsumerWidget {
  final EventModel event;
  final VoidCallback? onTap;

  const _EventCardWithBadge({required this.event, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAv = ref.watch(registrationsProvider(event.id));
    final regs = regsAv.valueOrNull ?? [];
    final pendingCount =
        regs.where((r) => r.stato == RegistrationStatus.inAttesa).length;

    return Stack(
      children: [
        EventCardAdmin(
          event: event,
          pilotCount: regs.isEmpty ? null : regs.length,
          onTap: onTap,
        ),
        if (pendingCount > 0)
          Positioned(
            top: 12,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$pendingCount',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
