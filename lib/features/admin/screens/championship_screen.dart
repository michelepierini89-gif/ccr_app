import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/championship_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../../classifica/widgets/championship_standings_table.dart';
import '../providers/admin_provider.dart';

final _adminChampionshipsProvider =
    StreamProvider<List<ChampionshipModel>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(firestoreServiceProvider)
      .getChampionships(createdBy: user.uid);
});

final _championshipByIdProvider =
    StreamProvider.family<ChampionshipModel?, String>((ref, id) {
  return ref.watch(firestoreServiceProvider).getChampionshipById(id);
});

// ── Championship list (admin) ─────────────────────────────────────────────────

class ChampionshipScreen extends ConsumerWidget {
  const ChampionshipScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ChampionshipModel c) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Elimina campionato',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Sei sicuro di voler eliminare "${c.nome}"?',
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
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma eliminazione',
            style: TextStyle(color: AppColors.error)),
        content: const Text(
          'L\'operazione non è reversibile.\nI dati del campionato verranno cancellati.',
          style: TextStyle(color: AppColors.textSecondary),
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
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(firestoreServiceProvider).deleteChampionship(c.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_adminChampionshipsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Campionati'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo'),
      ),
      body: SafeArea(bottom: true, child: listAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              const Text('Errore nel caricamento',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(_adminChampionshipsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events_outlined,
                        color: AppColors.accent, size: 40),
                  ),
                  const SizedBox(height: 20),
                  const Text('Nessun campionato',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Crea il primo campionato con il pulsante +',
                      style: TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final c = items[i];
              final color = AppColors.specialColors[
                  c.colorIndex.clamp(0, AppColors.specialColors.length - 1)];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.emoji_events, color: color, size: 22),
                  ),
                  title: Text(c.nome,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${c.stagione} · ${c.eventIds.length} event${c.eventIds.length == 1 ? 'o' : 'i'}',
                    style:
                        const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error, size: 20),
                        tooltip: 'Elimina',
                        onPressed: () => _confirmDelete(context, ref, c),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    ],
                  ),
                  onTap: () =>
                      context.push('/admin/championships/${c.id}'),
                ),
              );
            },
          );
        },
      ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int stagione = DateTime.now().year;
    int colorIdx = 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Nuovo campionato',
              style: TextStyle(color: AppColors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildField(nameCtrl, 'Nome campionato *'),
                const SizedBox(height: 12),
                _buildField(descCtrl, 'Descrizione'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Stagione:',
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      color: AppColors.accent,
                      onPressed: () => setSt(() => stagione--),
                    ),
                    Text('$stagione',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      color: AppColors.accent,
                      onPressed: () => setSt(() => stagione++),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Colore:',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(AppColors.specialColors.length, (i) {
                    final c = AppColors.specialColors[i];
                    return GestureDetector(
                      onTap: () => setSt(() => colorIdx = i),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: colorIdx == i
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
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
                  backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      final c = ChampionshipModel(
        id: '',
        nome: nameCtrl.text.trim(),
        descrizione: descCtrl.text.trim(),
        stagione: stagione,
        eventIds: [],
        colorIndex: colorIdx,
        createdBy: user.uid,
        createdAt: DateTime.now(),
      );
      await ref.read(firestoreServiceProvider).createChampionship(c);
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  TextField _buildField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ── Championship management (admin) ──────────────────────────────────────────

class ChampionshipManagementScreen extends ConsumerStatefulWidget {
  final String championshipId;
  const ChampionshipManagementScreen({super.key, required this.championshipId});

  @override
  ConsumerState<ChampionshipManagementScreen> createState() =>
      _ChampionshipManagementScreenState();
}

class _ChampionshipManagementScreenState
    extends ConsumerState<ChampionshipManagementScreen> {
  bool _saving = false;

  Future<void> _toggleEvent(
      ChampionshipModel c, String eventId, bool add) async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(firestoreServiceProvider);
      if (add) {
        await svc.addEventToChampionship(c.id, eventId);
      } else {
        await svc.removeEventFromChampionship(c.id, eventId);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteChampionship(ChampionshipModel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Elimina campionato',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Sei sicuro di voler eliminare "${c.nome}"?\nL\'operazione non è reversibile.',
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
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref
          .read(firestoreServiceProvider)
          .deleteChampionship(c.id);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final champAsync =
        ref.watch(_championshipByIdProvider(widget.championshipId));
    final allEventsAsync = ref.watch(adminEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: champAsync.valueOrNull != null
            ? Text(champAsync.valueOrNull!.nome)
            : const Text('Campionato'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (champAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Elimina campionato',
              onPressed: () =>
                  _deleteChampionship(champAsync.valueOrNull!),
            ),
        ],
      ),
      body: SafeArea(bottom: true, child: champAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
            child: Text('Errore: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (c) {
          if (c == null) {
            return const Center(
                child: Text('Campionato non trovato',
                    style: TextStyle(color: AppColors.textSecondary)));
          }
          final color = AppColors.specialColors[
              c.colorIndex.clamp(0, AppColors.specialColors.length - 1)];

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.emoji_events,
                                color: color, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.nome,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text(
                                  'Stagione ${c.stagione} · ${c.eventIds.length} event${c.eventIds.length == 1 ? 'o' : 'i'}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                                if (c.descrizione.isNotEmpty)
                                  Text(c.descrizione,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Standings link
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                            '/admin/championships/${c.id}/standings'),
                        icon: const Icon(Icons.leaderboard, size: 18),
                        label: const Text('Visualizza classifica'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.6)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Gare nel campionato',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Aggiungi o rimuovi gare da questo campionato',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    allEventsAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent)),
                      error: (e, _) => Text('Errore: $e',
                          style:
                              const TextStyle(color: AppColors.error)),
                      data: (allEvents) {
                        // Step 47, Parte 2F — un evento di allenamento non
                        // può essere assegnato a un campionato (nessuna
                        // classifica di gara da sommare).
                        final events = allEvents
                            .where((e) => !e.isAllenamento)
                            .toList();
                        if (events.isEmpty) {
                          return const Text(
                            'Nessun evento disponibile',
                            style: TextStyle(
                                color: AppColors.textSecondary),
                          );
                        }
                        return Column(
                          children: events.map((event) {
                            final inChamp =
                                c.eventIds.contains(event.id);
                            return Container(
                              margin:
                                  const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: inChamp
                                    ? color.withValues(alpha: 0.08)
                                    : AppColors.cardBackground,
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                    color: inChamp
                                        ? color.withValues(alpha: 0.5)
                                        : AppColors.border),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  inChamp
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: inChamp
                                      ? color
                                      : AppColors.textSecondary,
                                ),
                                title: Text(
                                  event.nome,
                                  style: TextStyle(
                                    color: inChamp
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_formatDate(event.data)} · ${event.luogo}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                                trailing: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      )
                                    : Switch(
                                        value: inChamp,
                                        activeThumbColor: color,
                                        onChanged: (v) => _toggleEvent(
                                            c, event.id, v),
                                      ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              if (_saving)
                Container(
                  color: Colors.black26,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent)),
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ── Championship standings (admin) ───────────────────────────────────────────

class ChampionshipAdminStandingsScreen extends ConsumerStatefulWidget {
  final String championshipId;
  const ChampionshipAdminStandingsScreen({
    super.key,
    required this.championshipId,
  });

  @override
  ConsumerState<ChampionshipAdminStandingsScreen> createState() =>
      _ChampionshipAdminStandingsScreenState();
}

class _ChampionshipAdminStandingsScreenState
    extends ConsumerState<ChampionshipAdminStandingsScreen> {
  bool _publishing = false;

  Future<void> _publish(ChampionshipModel champ) async {
    setState(() => _publishing = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateChampionship(champ.copyWith(classPublished: true));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final champAsync =
        ref.watch(_championshipByIdProvider(widget.championshipId));
    final standingsAsync =
        ref.watch(championshipStandingsProvider(widget.championshipId));

    final champ = champAsync.valueOrNull;
    final color = champ != null
        ? AppColors.specialColors[
            champ.colorIndex.clamp(0, AppColors.specialColors.length - 1)]
        : AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(champ?.nome ?? 'Classifica campionato'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
            onPressed: () => ref.invalidate(
                championshipStandingsProvider(widget.championshipId)),
          ),
        ],
      ),
      body: SafeArea(bottom: true, child: champAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
            child: Text('Errore: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (champ) {
          if (champ == null) {
            return const Center(
                child: Text('Campionato non trovato',
                    style: TextStyle(color: AppColors.textSecondary)));
          }
          return standingsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
            error: (e, _) => Center(
                child: Text('Errore: $e',
                    style: const TextStyle(color: AppColors.error))),
            data: (standings) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: champ.classPublished
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: champ.classPublished
                                    ? AppColors.success
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  champ.classPublished
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: champ.classPublished
                                      ? AppColors.success
                                      : AppColors.textSecondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    champ.classPublished
                                        ? 'Classifica pubblicata ai piloti'
                                        : 'Classifica non pubblicata',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!champ.classPublished)
                          ElevatedButton.icon(
                            onPressed:
                                _publishing ? null : () => _publish(champ),
                            icon: _publishing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.publish, size: 18),
                            label: const Text('Pubblica classifica'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ChampionshipStandingsTable(
                      teams: standings.teams,
                      color: color,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      ),
    );
  }
}
