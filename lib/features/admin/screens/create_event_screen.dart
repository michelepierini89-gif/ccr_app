import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/ccr_button.dart';
import '../../auth/widgets/ccr_text_field.dart';
import '../providers/admin_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() =>
      _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _luogoCtrl = TextEditingController();
  final _descrizioneCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  int _minSquadra = 2;
  int _maxSquadra = 3;
  TipologiaClassifica _tipologia = TipologiaClassifica.sommaTempi;
  int _maxRaceTimeH = 4;
  int _maxRaceTimeM = 30;
  bool _isLoading = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _luogoCtrl.dispose();
    _descrizioneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
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
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_minSquadra > _maxSquadra) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La dimensione minima non può superare la massima'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    final totalMinutes = _maxRaceTimeH * 60 + _maxRaceTimeM;
    if (totalMinutes < 30 || totalMinutes > 720) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tempo massimo: tra 30 minuti e 12 ore'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final uid = ref.read(authStateProvider).valueOrNull?.uid ?? '';
      final event = EventModel(
        id: '',
        nome: _nomeCtrl.text.trim(),
        luogo: _luogoCtrl.text.trim(),
        data: _selectedDate,
        descrizione: _descrizioneCtrl.text.trim(),
        specialiRouteA: const [],
        stato: EventStatus.bozza,
        createdBy: uid,
        createdAt: DateTime.now(),
        minSquadra: _minSquadra,
        maxSquadra: _maxSquadra,
        tipologiaClassifica: _tipologia,
        maxRaceTimeMinutes: totalMinutes,
      );
      final id = await ref.read(firestoreServiceProvider).createEvent(event);
      if (!mounted) return;
      context.go('/admin/event/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore: ${e.toString()}'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Nuovo Evento'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.paddingOf(context).bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CcrTextField(
                label: 'Nome evento *',
                controller: _nomeCtrl,
                textInputAction: TextInputAction.next,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Inserisci il nome'
                    : null,
              ),
              const SizedBox(height: 16),
              CcrTextField(
                label: 'Luogo *',
                controller: _luogoCtrl,
                textInputAction: TextInputAction.next,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Inserisci il luogo'
                    : null,
              ),
              const SizedBox(height: 16),
              // Date picker
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Data evento',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          Text(
                            DateFormat('dd MMMM yyyy', 'it')
                                .format(_selectedDate),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 16),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descrizioneCtrl,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Descrizione',
                  labelStyle:
                      const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.cardBackground,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 2)),
                ),
              ),
              const SizedBox(height: 24),
              // ── Dimensione squadra ──
              _SectionLabel('Dimensione squadra'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StepperField(
                      label: 'Minimo',
                      value: _minSquadra,
                      min: 1,
                      max: _maxSquadra,
                      onChanged: (v) => setState(() => _minSquadra = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StepperField(
                      label: 'Massimo',
                      value: _maxSquadra,
                      min: _minSquadra,
                      max: 4,
                      onChanged: (v) => setState(() => _maxSquadra = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // ── Tipologia classifica ──
              _SectionLabel('Tipologia classifica'),
              const SizedBox(height: 12),
              _TipologiaSelector(
                value: _tipologia,
                onChanged: (v) => setState(() => _tipologia = v),
              ),
              const SizedBox(height: 24),
              // ── Tempo massimo gara ──
              _SectionLabel('Tempo massimo gara'),
              const SizedBox(height: 4),
              Text(
                'Min 30 min — Max 12 ore  (default: 4h 30min)',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StepperField(
                      label: 'Ore',
                      value: _maxRaceTimeH,
                      min: 0,
                      max: 12,
                      onChanged: (v) => setState(() => _maxRaceTimeH = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StepperField(
                      label: 'Minuti',
                      value: _maxRaceTimeM,
                      min: 0,
                      max: 55,
                      step: 5,
                      onChanged: (v) => setState(() => _maxRaceTimeM = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Totale: ${_maxRaceTimeH}h ${_maxRaceTimeM.toString().padLeft(2, '0')}min'
                ' (${_maxRaceTimeH * 60 + _maxRaceTimeM} min)',
                style: const TextStyle(color: AppColors.accent, fontSize: 12),
              ),
              const SizedBox(height: 32),
              CcrButton(
                label: 'Salva evento',
                onPressed: _save,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5),
    );
  }
}

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final void Function(int) onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: value > min ? () => onChanged(value - step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value > min
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(
                    Icons.remove,
                    size: 18,
                    color: value > min
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              InkWell(
                onTap: value < max ? () => onChanged(value + step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value < max
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: value < max
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipologiaSelector extends StatelessWidget {
  final TipologiaClassifica value;
  final void Function(TipologiaClassifica) onChanged;

  const _TipologiaSelector(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: TipologiaClassifica.values.map((t) {
        final selected = value == t;
        return GestureDetector(
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                        width: 2),
                    color: selected ? AppColors.accent : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 12)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
