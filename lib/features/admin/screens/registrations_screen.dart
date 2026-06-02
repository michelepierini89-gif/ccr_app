import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

class RegistrationsScreen extends ConsumerWidget {
  final String eventId;
  const RegistrationsScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regsAsync = ref.watch(registrationsProvider(eventId));
    final teamsAsync = ref.watch(teamsProvider(eventId));

    return regsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (regs) {
        final teams = teamsAsync.valueOrNull ?? [];
        final incompleteTeams =
            teams.where((t) => t.membriIds.length < 2).toList();

        return Column(
          children: [
            if (incompleteTeams.isNotEmpty)
              Container(
                width: double.infinity,
                color: AppColors.warning.withValues(alpha: 0.15),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${incompleteTeams.length} squadr${incompleteTeams.length == 1 ? "a incompleta" : "e incomplete"} (pilota senza copilota)',
                      style: const TextStyle(
                          color: AppColors.warning, fontSize: 13),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: DefaultTabController(
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
                              teams: teams,
                              eventId: eventId,
                              ref: ref),
                          _RegistrationList(
                              regs: regs
                                  .where((r) =>
                                      r.stato == RegistrationStatus.inAttesa)
                                  .toList(),
                              teams: teams,
                              eventId: eventId,
                              ref: ref),
                          _RegistrationList(
                              regs: regs
                                  .where((r) =>
                                      r.stato == RegistrationStatus.approvato)
                                  .toList(),
                              teams: teams,
                              eventId: eventId,
                              ref: ref),
                          _RegistrationList(
                              regs: regs
                                  .where((r) =>
                                      r.stato == RegistrationStatus.rifiutato)
                                  .toList(),
                              teams: teams,
                              eventId: eventId,
                              ref: ref),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RegistrationList extends StatelessWidget {
  final List<RegistrationModel> regs;
  final List<TeamModel> teams;
  final String eventId;
  final WidgetRef ref;

  const _RegistrationList({
    required this.regs,
    required this.teams,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Color _statusColor(RegistrationStatus s) => switch (s) {
        RegistrationStatus.inAttesa => AppColors.warning,
        RegistrationStatus.approvato => AppColors.success,
        RegistrationStatus.rifiutato => AppColors.error,
      };

  String _statusLabel(RegistrationStatus s) => switch (s) {
        RegistrationStatus.inAttesa => 'IN ATTESA',
        RegistrationStatus.approvato => 'APPROVATO',
        RegistrationStatus.rifiutato => 'RIFIUTATO',
      };

  TeamModel? _teamOf(String userId) {
    try {
      return teams.firstWhere((t) => t.membriIds.contains(userId));
    } catch (_) {
      return null;
    }
  }

  String? _partnerName(String userId, TeamModel team) {
    final partnerId =
        team.membriIds.where((id) => id != userId).firstOrNull;
    if (partnerId == null) return null;
    try {
      return regs.firstWhere((r) => r.userId == partnerId).nomeCompleto;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (regs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, color: AppColors.textSecondary, size: 48),
            SizedBox(height: 12),
            Text('Nessuna iscrizione',
                style: TextStyle(color: AppColors.textSecondary)),
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
        final team = _teamOf(reg.userId);
        final partner = team != null ? _partnerName(reg.userId, team) : null;
        final isTeamIncomplete = team != null && team.membriIds.length < 2;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isTeamIncomplete
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 6),
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
                  DateFormat('dd/MM/yyyy HH:mm').format(reg.createdAt),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                // Team info
                if (team != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isTeamIncomplete ? Icons.warning_amber_rounded : Icons.group,
                        size: 14,
                        color: isTeamIncomplete
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        team.nome,
                        style: TextStyle(
                          color: isTeamIncomplete
                              ? AppColors.warning
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (partner != null) ...[
                        const Text(' · ',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        Expanded(
                          child: Text(
                            partner,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Senza copilota',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.person_off,
                          size: 13, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text('Nessuna squadra',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
                if (reg.stato == RegistrationStatus.inAttesa) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _updateStatus(
                              context, reg.userId, RegistrationStatus.approvato),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Text('Approva'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _updateStatus(
                              context, reg.userId, RegistrationStatus.rifiutato),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Text('Rifiuta'),
                        ),
                      ),
                    ],
                  ),
                ] else if (reg.stato == RegistrationStatus.approvato) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _updateStatus(
                        context, reg.userId, RegistrationStatus.inAttesa),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Text('Revoca approvazione'),
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
