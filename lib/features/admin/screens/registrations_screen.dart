import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

class RegistrationsScreen extends ConsumerWidget {
  final String eventId;
  const RegistrationsScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAsync = ref.watch(registrationsProvider(eventId));

    return regsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (regs) {
        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Tutti'),
                  Tab(text: 'Attesa'),
                  Tab(text: 'Approvati'),
                  Tab(text: 'Rifiutati'),
                ],
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.accent,
                dividerColor: AppColors.border,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _RegistrationList(
                      regs: regs,
                      eventId: eventId,
                      ref: ref,
                    ),
                    _RegistrationList(
                      regs: regs
                          .where((r) =>
                              r.stato == RegistrationStatus.inAttesa)
                          .toList(),
                      eventId: eventId,
                      ref: ref,
                    ),
                    _RegistrationList(
                      regs: regs
                          .where((r) =>
                              r.stato == RegistrationStatus.approvato)
                          .toList(),
                      eventId: eventId,
                      ref: ref,
                    ),
                    _RegistrationList(
                      regs: regs
                          .where((r) =>
                              r.stato == RegistrationStatus.rifiutato)
                          .toList(),
                      eventId: eventId,
                      ref: ref,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RegistrationList extends StatelessWidget {
  final List<RegistrationModel> regs;
  final String eventId;
  final WidgetRef ref;

  const _RegistrationList({
    required this.regs,
    required this.eventId,
    required this.ref,
  });

  Future<void> _updateStatus(
      BuildContext context, String userId, RegistrationStatus status) async {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateRegistrationStatus(eventId, userId, status);
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

  Color _statusColor(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return AppColors.warning;
      case RegistrationStatus.approvato:
        return AppColors.success;
      case RegistrationStatus.rifiutato:
        return AppColors.error;
    }
  }

  String _statusLabel(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return 'IN ATTESA';
      case RegistrationStatus.approvato:
        return 'APPROVATO';
      case RegistrationStatus.rifiutato:
        return 'RIFIUTATO';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (regs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                color: AppColors.textSecondary, size: 48),
            SizedBox(height: 12),
            Text(
              'Nessuna iscrizione',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: regs.length,
      itemBuilder: (context, i) {
        final reg = regs[i];
        final statusColor = _statusColor(reg.stato);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reg.nomeCompleto,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        _statusLabel(reg.stato),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Iscritto il ${DateFormat('dd/MM/yyyy HH:mm').format(reg.createdAt)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                if (reg.stato == RegistrationStatus.inAttesa) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _updateStatus(context, reg.userId,
                              RegistrationStatus.approvato),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('Approva',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _updateStatus(context, reg.userId,
                              RegistrationStatus.rifiutato),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('Rifiuta',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
