import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar_by_id.dart';
import '../providers/admin_provider.dart';

class RegistrationsScreen extends ConsumerWidget {
  final String eventId;
  final int minSquadra;
  final int maxSquadra;
  const RegistrationsScreen({
    super.key,
    required this.eventId,
    this.minSquadra = 2,
    this.maxSquadra = 3,
  });

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
        final incompleteTeams = teams
            .where((t) =>
                t.membriIds.length < minSquadra ||
                t.membriIds.length > maxSquadra)
            .toList();

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
                      '${incompleteTeams.length} squadr${incompleteTeams.length == 1 ? "a" : "e"} fuori dimensione (min $minSquadra–max $maxSquadra)',
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
                              regs: regs, teams: teams,
                              eventId: eventId,
                              minSquadra: minSquadra, maxSquadra: maxSquadra),
                          _RegistrationList(
                              regs: regs.where((r) => r.stato == RegistrationStatus.inAttesa).toList(),
                              teams: teams, eventId: eventId,
                              minSquadra: minSquadra, maxSquadra: maxSquadra),
                          _RegistrationList(
                              regs: regs.where((r) => r.stato == RegistrationStatus.approvato).toList(),
                              teams: teams, eventId: eventId,
                              minSquadra: minSquadra, maxSquadra: maxSquadra),
                          _RegistrationList(
                              regs: regs.where((r) => r.stato == RegistrationStatus.rifiutato).toList(),
                              teams: teams, eventId: eventId,
                              minSquadra: minSquadra, maxSquadra: maxSquadra),
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

class _RegistrationList extends ConsumerStatefulWidget {
  final List<RegistrationModel> regs;
  final List<TeamModel> teams;
  final String eventId;
  final int minSquadra;
  final int maxSquadra;

  const _RegistrationList({
    required this.regs,
    required this.teams,
    required this.eventId,
    required this.minSquadra,
    required this.maxSquadra,
  });

  @override
  ConsumerState<_RegistrationList> createState() => _RegistrationListState();
}

class _RegistrationListState extends ConsumerState<_RegistrationList> {
  String? _loadingUserId;

  Future<void> _updateStatus(String userId, RegistrationStatus status) async {
    setState(() => _loadingUserId = userId);
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateRegistrationStatus(widget.eventId, userId, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingUserId = null);
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
      return widget.teams.firstWhere((t) => t.membriIds.contains(userId));
    } catch (_) {
      return null;
    }
  }

  static const String _senzaSquadra = 'Senza squadra';

  @override
  Widget build(BuildContext context) {
    final regs = widget.regs;
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

    // Raggruppa le iscrizioni per nome squadra (teamName / nome squadra reale)
    final groups = <String, List<RegistrationModel>>{};
    final groupTeams = <String, TeamModel?>{};
    for (final reg in regs) {
      final team = _teamOf(reg.userId);
      final key = team?.nome ?? reg.teamName ?? _senzaSquadra;
      groups.putIfAbsent(key, () => []).add(reg);
      groupTeams[key] = team;
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == _senzaSquadra) return 1;
        if (b == _senzaSquadra) return -1;
        return a.compareTo(b);
      });

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      itemCount: sortedKeys.length,
      itemBuilder: (context, i) {
        final key = sortedKeys[i];
        final groupRegs = groups[key]!;
        final team = groupTeams[key];
        final hasTeam = key != _senzaSquadra;
        final memberCount = team?.membriIds.length ?? groupRegs.length;
        final isComplete = hasTeam &&
            memberCount >= widget.minSquadra &&
            memberCount <= widget.maxSquadra;
        final groupColor = !hasTeam
            ? AppColors.textSecondary
            : (isComplete ? AppColors.success : AppColors.warning);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasTeam && !isComplete
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Icon(
                      hasTeam ? Icons.group : Icons.person_off,
                      size: 18,
                      color: groupColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        key,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$memberCount membr${memberCount == 1 ? "o" : "i"}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (hasTeam) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: groupColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: groupColor),
                        ),
                        child: Text(
                          isComplete ? 'COMPLETA' : 'INCOMPLETA',
                          style: TextStyle(
                            color: groupColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              for (final reg in groupRegs) _buildPilotRow(reg),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPilotRow(RegistrationModel reg) {
    final statusColor = _statusColor(reg.stato);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatarById(
                userId: reg.userId,
                fallbackNome: reg.nome,
                fallbackCognome: reg.cognome,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reg.nomeCompleto,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          if (reg.stato == RegistrationStatus.inAttesa) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loadingUserId != null
                        ? null
                        : () => _updateStatus(
                            reg.userId, RegistrationStatus.approvato),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      minimumSize: const Size(0, 44),
                    ),
                    child: _loadingUserId == reg.userId
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.success,
                            ),
                          )
                        : const Text('Approva'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loadingUserId != null
                        ? null
                        : () => _updateStatus(
                            reg.userId, RegistrationStatus.rifiutato),
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
              onPressed: _loadingUserId != null
                  ? null
                  : () =>
                      _updateStatus(reg.userId, RegistrationStatus.inAttesa),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(0, 40),
              ),
              child: _loadingUserId == reg.userId
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const Text('Revoca approvazione'),
            ),
          ],
        ],
      ),
    );
  }
}
