import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/team_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';

class TeamScreen extends ConsumerStatefulWidget {
  final String eventId;
  const TeamScreen({super.key, required this.eventId});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  final _nomeTeamCtrl = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nomeTeamCtrl.dispose();
    super.dispose();
  }

  String? get _userId =>
      ref.read(authStateProvider).valueOrNull?.uid;

  TeamModel? _myTeam(List<TeamModel> teams) {
    final uid = _userId;
    if (uid == null) return null;
    for (final t in teams) {
      if (t.membriIds.contains(uid)) return t;
    }
    return null;
  }

  Future<void> _createTeam() async {
    if (_nomeTeamCtrl.text.trim().isEmpty) return;
    final uid = _userId;
    if (uid == null) return;
    setState(() => _isCreating = true);
    try {
      final team = TeamModel(
        id: '',
        nome: _nomeTeamCtrl.text.trim(),
        membriIds: [uid],
        createdBy: uid,
        eventId: widget.eventId,
      );
      await ref.read(firestoreServiceProvider).createTeam(team);
      _nomeTeamCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Squadra creata!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinTeam(String teamId) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .joinTeam(widget.eventId, teamId, uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrato nella squadra!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _setPreferredTeam(String teamName) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .savePreferredTeamName(uid, teamName);
      ref.invalidate(currentUserModelProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$teamName" impostata come squadra preferita'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _leaveTeam(String teamId) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .leaveTeam(widget.eventId, teamId, uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hai lasciato la squadra'),
          backgroundColor: AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsProvider(widget.eventId));
    final regs = ref.watch(registrationsProvider(widget.eventId)).valueOrNull ?? [];
    final preferredTeamName =
        ref.watch(currentUserModelProvider).valueOrNull?.preferredTeamName;

    String memberName(String memberId) {
      if (memberId == _userId) return 'Tu';
      try {
        final r = regs.firstWhere((r) => r.userId == memberId);
        return r.nomeCompleto;
      } catch (_) {
        return memberId.length > 8 ? '${memberId.substring(0, 8)}…' : memberId;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Squadra')),
      body: teamsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
            child: Text('Errore: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (teams) {
          final myTeam = _myTeam(teams);

          if (myTeam != null) {
            // Show my team
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.group,
                                color: AppColors.accent, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                myTeam.nome,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (preferredTeamName == myTeam.nome)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star,
                                  color: AppColors.warning, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Squadra preferita',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => _setPreferredTeam(myTeam.nome),
                            icon: const Icon(Icons.star_border, size: 16),
                            label: const Text('Imposta come squadra preferita'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              side: BorderSide(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.6)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          '${myTeam.membriIds.length} membri',
                          style: const TextStyle(
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        ...myTeam.membriIds.map(
                          (id) => Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  id == _userId
                                      ? Icons.person_pin
                                      : Icons.person,
                                  color: id == _userId
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  memberName(id),
                                  style: TextStyle(
                                    color: id == _userId
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: id == _userId
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => _leaveTeam(myTeam.id),
                      icon: const Icon(Icons.exit_to_app,
                          color: AppColors.error),
                      label: const Text('Lascia squadra',
                          style: TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // No team: show create + available teams
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crea una squadra',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nomeTeamCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Nome squadra',
                          labelStyle: const TextStyle(
                              color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.accent, width: 2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isCreating ? null : _createTeam,
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Crea'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                if (teams.isNotEmpty) ...[
                  const Text(
                    'Squadre disponibili',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...teams.map(
                    (team) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.group,
                            color: AppColors.textSecondary),
                        title: Text(team.nome,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${team.membriIds.length} membri',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _joinTeam(team.id),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Unisciti',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const Center(
                    child: Text(
                      'Nessuna squadra disponibile.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
