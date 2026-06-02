import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../map/screens/track_map_screen.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  Color _regStatusColor(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return AppColors.warning;
      case RegistrationStatus.approvato:
        return AppColors.success;
      case RegistrationStatus.rifiutato:
        return AppColors.error;
    }
  }

  String _regStatusLabel(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return 'Iscrizione in attesa di approvazione';
      case RegistrationStatus.approvato:
        return 'Iscrizione approvata';
      case RegistrationStatus.rifiutato:
        return 'Iscrizione rifiutata';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserModelProvider);

    return StreamBuilder<EventModel?>(
      stream: ref.watch(firestoreServiceProvider).getEvents().map(
            (list) => list.where((e) => e.id == eventId).isNotEmpty
                ? list.firstWhere((e) => e.id == eventId)
                : null,
          ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        final event = snap.data;
        if (event == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Text('Evento non trovato',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event header
                Container(
                  color: AppColors.cardBackground,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.nome,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE d MMMM yyyy', 'it')
                                .format(event.data),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            event.luogo,
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      if (event.descrizione.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          event.descrizione,
                          style: const TextStyle(
                              color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),

                // Track map
                if (event.speciali.isNotEmpty || event.trackUrl != null) ...[
                  SizedBox(
                    height: 220,
                    child: TrackMapScreen(
                      trackPoints: const [],
                      specials: event.speciali,
                      waypoints: event.speciali
                          .expand((s) => [s.waypointInizio, s.waypointFine])
                          .toList(),
                      interactive: false,
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Specials
                if (event.speciali.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: const Text(
                      'Prove Speciali',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: event.speciali
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: s.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: s.color),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: s.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.nome,
                                      style: TextStyle(
                                        color: s.color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Registration section
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: userAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent)),
                    error: (e, _) => const SizedBox(),
                    data: (user) {
                      if (user == null) return const SizedBox();
                      return FutureBuilder(
                        future: ref
                            .read(firestoreServiceProvider)
                            .getMyRegistration(eventId, user.id),
                        builder: (context, regSnap) {
                          final reg = regSnap.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Iscrizione',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (reg != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _regStatusColor(reg.stato)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            _regStatusColor(reg.stato)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        reg.stato ==
                                                RegistrationStatus.approvato
                                            ? Icons.check_circle
                                            : reg.stato ==
                                                    RegistrationStatus
                                                        .rifiutato
                                                ? Icons.cancel
                                                : Icons.hourglass_empty,
                                        color: _regStatusColor(reg.stato),
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _regStatusLabel(reg.stato),
                                          style: TextStyle(
                                            color:
                                                _regStatusColor(reg.stato),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (regSnap.connectionState ==
                                  ConnectionState.done) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(firestoreServiceProvider)
                                            .registerForEvent(
                                              eventId: eventId,
                                              userId: user.id,
                                              nome: user.nome,
                                              cognome: user.cognome,
                                            );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Iscrizione inviata!'),
                                              backgroundColor:
                                                  AppColors.success,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text('Errore: $e'),
                                              backgroundColor:
                                                  AppColors.error,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Iscriviti'),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                // Team section
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 12),
                      const Text(
                        'Squadra',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => context
                              .push('/pilot/event/$eventId/team'),
                          icon: const Icon(Icons.group),
                          label: const Text('Gestisci squadra'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
