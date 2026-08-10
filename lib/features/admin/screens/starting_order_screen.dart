import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import '../../../core/models/event_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

enum _OrderMode { random, manuale, campionato }

extension on _OrderMode {
  String get label => switch (this) {
        _OrderMode.random => 'RANDOM',
        _OrderMode.manuale => 'MANUALE',
        _OrderMode.campionato => 'CAMPIONATO',
      };

  String get description => switch (this) {
        _OrderMode.random => 'Ordine casuale tra le squadre approvate',
        _OrderMode.manuale => 'Riordina le squadre trascinandole',
        _OrderMode.campionato =>
          'Ordine inverso della classifica dell\'evento precedente del campionato',
      };

  IconData get icon => switch (this) {
        _OrderMode.random => Icons.shuffle,
        _OrderMode.manuale => Icons.drag_indicator,
        _OrderMode.campionato => Icons.emoji_events,
      };
}

class StartingOrderScreen extends ConsumerStatefulWidget {
  final EventModel event;
  const StartingOrderScreen({super.key, required this.event});

  @override
  ConsumerState<StartingOrderScreen> createState() =>
      _StartingOrderScreenState();
}

class _StartingOrderScreenState extends ConsumerState<StartingOrderScreen> {
  TimeOfDay _firstStart = const TimeOfDay(hour: 9, minute: 0);
  int _intervalMinutes = 2;
  _OrderMode _mode = _OrderMode.random;

  bool _loading = true;
  bool _generating = false;
  bool _saving = false;
  String? _loadError;
  String? _infoMessage;

  List<TeamModel> _approvedTeams = [];
  List<String> _orderedNames = [];
  bool _generated = false;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final svc = ref.read(firestoreServiceProvider);
      final teams = await svc.getTeamsOnce(widget.event.id);
      final regs = await svc.getRegistrationsOnce(widget.event.id);
      final approvedIds = regs
          .where((r) => r.stato == RegistrationStatus.approvato)
          .map((r) => r.squadraId)
          .whereType<String>()
          .toSet();
      final approved =
          teams.where((t) => approvedIds.contains(t.id)).toList()
            ..sort((a, b) => a.nome.compareTo(b.nome));
      if (!mounted) return;
      setState(() {
        _approvedTeams = approved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickFirstStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _firstStart,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.cardBackground,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _firstStart = picked);
  }

  void _changeInterval(int delta) {
    setState(() {
      _intervalMinutes = (_intervalMinutes + delta).clamp(1, 30);
    });
  }

  DateTime _startTimeFor(int index) {
    final base = DateTime(
      widget.event.data.year,
      widget.event.data.month,
      widget.event.data.day,
      _firstStart.hour,
      _firstStart.minute,
    );
    return base.add(Duration(minutes: _intervalMinutes * index));
  }

  Future<void> _generate() async {
    if (_approvedTeams.isEmpty) return;
    setState(() {
      _generating = true;
      _infoMessage = null;
    });

    List<String> names = _approvedTeams.map((t) => t.nome).toList();

    switch (_mode) {
      case _OrderMode.random:
        names.shuffle(Random());
        break;
      case _OrderMode.manuale:
        // Mantiene l'ordine corrente; l'utente riordina con drag and drop
        break;
      case _OrderMode.campionato:
        names = await _campionatoOrder(names);
        break;
    }

    if (!mounted) return;
    setState(() {
      _orderedNames = names;
      _generated = true;
      _generating = false;
    });
  }

  Future<List<String>> _campionatoOrder(List<String> currentNames) async {
    final svc = ref.read(firestoreServiceProvider);
    final championship =
        await svc.getChampionshipForEvent(widget.event.id);

    if (championship == null) {
      setState(() => _infoMessage =
          'L\'evento non appartiene a un campionato: ordine generato in modalità RANDOM.');
      return (List<String>.from(currentNames)..shuffle(Random()));
    }

    final idx = championship.eventIds.indexOf(widget.event.id);
    if (idx <= 0) {
      setState(() => _infoMessage =
          'Nessun evento precedente nel campionato: ordine generato in modalità RANDOM.');
      return (List<String>.from(currentNames)..shuffle(Random()));
    }

    final prevEventId = championship.eventIds[idx - 1];
    final prevEvent = await svc.getEvent(prevEventId);
    if (prevEvent == null) {
      setState(() => _infoMessage =
          'Evento precedente non trovato: ordine generato in modalità RANDOM.');
      return (List<String>.from(currentNames)..shuffle(Random()));
    }

    final passages = await svc.getPassagesOnce(prevEventId);
    final registrations = await svc.getRegistrationsOnce(prevEventId);
    final teams = await svc.getTeamsOnce(prevEventId);
    final withdrawals = await svc.getWithdrawalsOnce(prevEventId);
    final penalties = await svc.getEffectivePenaltySettings(prevEventId);
    final routeVariantByUserId =
        await svc.getRouteVariantByUserOnce(prevEventId);

    final entries = ClassificaEngine.compute(
      event: prevEvent,
      passages: passages,
      registrations: registrations,
      teams: teams,
      withdrawals: withdrawals,
      liveTracking: const <GpsPointModel>[],
      penalties: penalties,
      routeVariantByUserId: routeVariantByUserId,
    );

    // Classifica inversa: ultimo classificato parte per primo.
    final classified = entries.where((e) => e.posizione > 0).toList()
      ..sort((a, b) => b.posizione.compareTo(a.posizione));

    final ordered = <String>[];
    final remaining = Set<String>.from(currentNames);
    for (final e in classified) {
      final match = remaining.firstWhere(
        (n) => n.toLowerCase().trim() == e.teamNome.toLowerCase().trim(),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        ordered.add(match);
        remaining.remove(match);
      }
    }
    // Squadre senza storico nell'evento precedente: aggiunte in coda (random)
    final extra = remaining.toList()..shuffle(Random());
    ordered.addAll(extra);

    if (ordered.isEmpty) {
      setState(() => _infoMessage =
          'Nessuna corrispondenza con la classifica precedente: ordine generato in modalità RANDOM.');
      return (List<String>.from(currentNames)..shuffle(Random()));
    }
    return ordered;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _orderedNames.removeAt(oldIndex);
      _orderedNames.insert(newIndex, item);
    });
  }

  Future<void> _saveAndNotify() async {
    if (_orderedNames.isEmpty) return;
    setState(() => _saving = true);
    try {
      final slots = <StartingSlot>[
        for (var i = 0; i < _orderedNames.length; i++)
          StartingSlot(
            teamName: _orderedNames[i],
            startTime: _startTimeFor(i),
            orderNumber: i + 1,
          ),
      ];
      final updated = widget.event.copyWith(startingOrder: slots);
      await ref.read(firestoreServiceProvider).updateEvent(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ordine di partenza salvato! Notifica inviata ai piloti.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore salvataggio: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ordine di partenza'),
        backgroundColor: AppColors.cardBackground,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _loadError != null
              ? Center(
                  child: Text('Errore: $_loadError',
                      style: const TextStyle(color: AppColors.error)))
              : _approvedTeams.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nessuna squadra approvata per questo evento.',
                          style: TextStyle(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildSettingsCard(),
                        const SizedBox(height: 16),
                        _buildModeCard(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _generating ? null : _generate,
                            icon: _generating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.auto_awesome),
                            label: Text(_generated
                                ? 'Rigenera ordine'
                                : 'Genera ordine'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        if (_infoMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: AppColors.warning, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_infoMessage!,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_generated) ...[
                          const SizedBox(height: 20),
                          _buildResultList(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _saveAndNotify,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.send),
                              label:
                                  const Text('Salva e notifica piloti'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impostazioni',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              const Text('Prima partenza',
                  style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              OutlinedButton(
                onPressed: _pickFirstStart,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Text(
                  _firstStart.format(context),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              const Text('Intervallo tra squadre',
                  style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: AppColors.textSecondary),
                onPressed: _intervalMinutes > 1
                    ? () => _changeInterval(-1)
                    : null,
              ),
              Text('$_intervalMinutes min',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.textSecondary),
                onPressed: _intervalMinutes < 30
                    ? () => _changeInterval(1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Modalità ordine',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          RadioGroup<_OrderMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() {
              _mode = v!;
              _generated = false;
              _infoMessage = null;
            }),
            child: Column(
              children: _OrderMode.values.map((m) {
            final selected = _mode == m;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _mode = m;
                _generated = false;
                _infoMessage = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.accent : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(m.icon,
                        color: selected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.label,
                              style: TextStyle(
                                  color: selected
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          Text(m.description,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    Radio<_OrderMode>(
                      value: m,
                      activeColor: AppColors.accent,
                    ),
                  ],
                ),
              ),
            );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList() {
    final timeFmt = DateFormat('HH:mm');
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          const Text('Ordine generato',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_mode == _OrderMode.manuale)
            const Text('Trascina per riordinare',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );

    Widget tile(int index) {
      final name = _orderedNames[index];
      return Container(
        key: ValueKey('slot_$index$name'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.accent,
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text(name,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule,
                  color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 4),
              Text(timeFmt.format(_startTimeFor(index)),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold)),
              if (_mode == _OrderMode.manuale) ...[
                const SizedBox(width: 8),
                const Icon(Icons.drag_handle,
                    color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      );
    }

    if (_mode == _OrderMode.manuale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: _onReorder,
            children: [
              for (var i = 0; i < _orderedNames.length; i++) tile(i),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        for (var i = 0; i < _orderedNames.length; i++) tile(i),
      ],
    );
  }
}
