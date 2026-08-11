import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ccr_avatar.dart';
import '../providers/admin_provider.dart';

enum _StatoFiltro { tutti, attivi, disabilitati }

enum _Ordinamento { dataRecente, nome }

/// Elenco di tutti gli utenti registrati all'app (Step 42) — distinto
/// dalle iscrizioni ai singoli eventi (quelle restano in
/// [RegistrationsScreen], per evento). Ricerca, filtro per stato,
/// ordinamento; l'admin può attivare/disabilitare un account da qui.
class UsersListScreen extends ConsumerStatefulWidget {
  const UsersListScreen({super.key});

  @override
  ConsumerState<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends ConsumerState<UsersListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _StatoFiltro _filtro = _StatoFiltro.tutti;
  _Ordinamento _ordinamento = _Ordinamento.dataRecente;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserModel> _applyFiltersAndSort(List<UserModel> users) {
    var list = users.where((u) {
      if (_filtro == _StatoFiltro.attivi && !u.attivo) return false;
      if (_filtro == _StatoFiltro.disabilitati && u.attivo) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return u.nomeCompleto.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) => _ordinamento == _Ordinamento.nome
        ? a.nomeCompleto.toLowerCase().compareTo(b.nomeCompleto.toLowerCase())
        : b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _toggleAttivo(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(
            user.attivo ? 'Disabilitare l\'account?' : 'Riattivare l\'account?',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          user.attivo
              ? '${user.nomeCompleto} non potrà più accedere all\'app.'
              : '${user.nomeCompleto} potrà tornare ad accedere all\'app.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    user.attivo ? AppColors.error : AppColors.success),
            child: Text(user.attivo ? 'Disabilita' : 'Riattiva'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .setUserAttivo(user.id, !user.attivo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Utenti registrati')),
      body: SafeArea(
        bottom: true,
        child: usersAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent)),
          error: (e, _) => Center(
              child: Text('Errore: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (users) {
            final filtered = _applyFiltersAndSort(users);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Cerca per nome o email',
                      hintStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.cardBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'Tutti',
                                selected: _filtro == _StatoFiltro.tutti,
                                onTap: () =>
                                    setState(() => _filtro = _StatoFiltro.tutti),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: 'Attivi',
                                selected: _filtro == _StatoFiltro.attivi,
                                onTap: () => setState(
                                    () => _filtro = _StatoFiltro.attivi),
                              ),
                              const SizedBox(width: 6),
                              _FilterChip(
                                label: 'Disabilitati',
                                selected:
                                    _filtro == _StatoFiltro.disabilitati,
                                onTap: () => setState(() =>
                                    _filtro = _StatoFiltro.disabilitati),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_Ordinamento>(
                        initialValue: _ordinamento,
                        color: AppColors.cardBackground,
                        icon: const Icon(Icons.sort,
                            color: AppColors.textSecondary),
                        onSelected: (v) => setState(() => _ordinamento = v),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: _Ordinamento.dataRecente,
                            child: Text('Data registrazione',
                                style:
                                    TextStyle(color: AppColors.textPrimary)),
                          ),
                          PopupMenuItem(
                            value: _Ordinamento.nome,
                            child: Text('Nome',
                                style:
                                    TextStyle(color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('${filtered.length} utenti',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('Nessun utente trovato',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(16, 4, 16,
                              16 + MediaQuery.paddingOf(context).bottom),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _UserRow(
                            user: filtered[i],
                            onToggleAttivo: () => _toggleAttivo(filtered[i]),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  final UserModel user;
  final VoidCallback onToggleAttivo;
  const _UserRow({required this.user, required this.onToggleAttivo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(userEventsCountProvider(user.id));
    final fmt = DateFormat('dd/MM/yyyy', 'it');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: user.attivo
                ? AppColors.border
                : AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CcrAvatar(
              photoUrl: user.photoUrl,
              nome: user.nome,
              cognome: user.cognome,
              size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(user.nomeCompleto,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.accent),
                      ),
                      child: Text(user.role.name.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(user.email,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text('Iscritto il ${fmt.format(user.createdAt)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    Text(
                      countAsync.when(
                        data: (n) => '$n eventi',
                        loading: () => '… eventi',
                        error: (_, _) => '— eventi',
                      ),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onToggleAttivo,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (user.attivo ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: user.attivo ? AppColors.success : AppColors.error),
              ),
              child: Text(user.attivo ? 'ATTIVO' : 'DISABILITATO',
                  style: TextStyle(
                      color: user.attivo
                          ? AppColors.success
                          : AppColors.error,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
