import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_error_handler.dart';
import '../providers/admin_provider.dart';

/// Gestione penalità contestuale a un evento: mostra i valori predefiniti
/// globali e permette di sovrascriverli con un override valido solo per
/// l'evento aperto (events/{eventId}/penalty_settings/override).
class PenaltySettingsScreen extends ConsumerStatefulWidget {
  final String eventId;
  const PenaltySettingsScreen({super.key, required this.eventId});

  @override
  ConsumerState<PenaltySettingsScreen> createState() =>
      _PenaltySettingsScreenState();
}

class _PenaltySettingsScreenState
    extends ConsumerState<PenaltySettingsScreen> {
  PenaltySettingsModel? _defaults;
  PenaltySettingsModel? _settings;
  bool _hasOverride = false;
  bool _loading = true;
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(firestoreServiceProvider);
      final defaults = await svc.getPenaltySettings();
      final override = await svc.getEventPenaltySettings(widget.eventId);
      if (mounted) {
        setState(() {
          _defaults = defaults;
          _hasOverride = override != null;
          _settings = override ?? defaults;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = FirebaseErrorHandler.getMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .saveEventPenaltySettings(widget.eventId, _settings!);
      if (mounted) {
        setState(() => _hasOverride = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Penalità dell\'evento salvate con successo'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .resetEventPenaltySettings(widget.eventId);
      if (mounted) {
        setState(() {
          _hasOverride = false;
          _settings = _defaults;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ripristinati i valori predefiniti'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _adjust(String field, int delta) {
    if (_settings == null) return;
    setState(() {
      _settings = switch (field) {
        'cp1' => _settings!.copyWith(
            cp1Mancato: (_settings!.cp1Mancato + delta).clamp(0, 3600)),
        'cp2' => _settings!.copyWith(
            cp2Mancati: (_settings!.cp2Mancati + delta).clamp(0, 3600)),
        'cp3' => _settings!.copyWith(
            cp3oPiuMancati:
                (_settings!.cp3oPiuMancati + delta).clamp(0, 3600)),
        'ritiro' => _settings!.copyWith(
            ritiroCompagno:
                (_settings!.ritiroCompagno + delta).clamp(0, 7200)),
        'mancante' => _settings!.copyWith(
            pilotaMancante:
                (_settings!.pilotaMancante + delta).clamp(0, 7200)),
        'speedzone' => _settings!.copyWith(
            speedZonePenaltySeconds:
                (_settings!.speedZonePenaltySeconds + delta).clamp(0, 3600)),
        _ => _settings,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Penalità evento'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _errorMsg != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMsg!,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _errorMsg = null;
                          });
                          _load();
                        },
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: (_hasOverride
                                  ? AppColors.warning
                                  : AppColors.accent)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_hasOverride
                                    ? AppColors.warning
                                    : AppColors.accent)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _hasOverride
                                  ? Icons.tune
                                  : Icons.info_outline,
                              color: _hasOverride
                                  ? AppColors.warning
                                  : AppColors.accent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _hasOverride
                                    ? 'Questo evento usa valori di penalità personalizzati, validi solo qui.'
                                    : 'Questo evento usa i valori predefiniti globali. Modificali e salva per creare un override valido solo per questo evento.',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      const _SectionTitle('Punti di Controllo mancati'),
                      const SizedBox(height: 12),

                      _PenaltyRow(
                        label: '1 CP mancato',
                        icon: Icons.looks_one_outlined,
                        value: _settings!.cp1Mancato,
                        onDecrease: () => _adjust('cp1', -30),
                        onIncrease: () => _adjust('cp1', 30),
                      ),
                      const SizedBox(height: 10),
                      _PenaltyRow(
                        label: '2 CP mancati',
                        icon: Icons.looks_two_outlined,
                        value: _settings!.cp2Mancati,
                        onDecrease: () => _adjust('cp2', -30),
                        onIncrease: () => _adjust('cp2', 30),
                      ),
                      const SizedBox(height: 10),
                      _PenaltyRow(
                        label: '3+ CP mancati',
                        icon: Icons.looks_3_outlined,
                        value: _settings!.cp3oPiuMancati,
                        onDecrease: () => _adjust('cp3', -30),
                        onIncrease: () => _adjust('cp3', 30),
                      ),
                      const SizedBox(height: 24),

                      const _SectionTitle('Zone a velocità controllata'),
                      const SizedBox(height: 12),

                      _PenaltyRow(
                        label: 'Violazione zona velocità',
                        icon: Icons.speed,
                        value: _settings!.speedZonePenaltySeconds,
                        onDecrease: () => _adjust('speedzone', -30),
                        onIncrease: () => _adjust('speedzone', 30),
                        accentColor: Colors.orange,
                        subtitle:
                            'Aggiunta al tempo della PS per ogni zona attraversata sopra il limite di velocità',
                      ),
                      const SizedBox(height: 24),

                      const _SectionTitle('Squadra'),
                      const SizedBox(height: 12),

                      _PenaltyRow(
                        label: 'Ritiro compagno',
                        icon: Icons.person_off_outlined,
                        value: _settings!.ritiroCompagno,
                        onDecrease: () => _adjust('ritiro', -30),
                        onIncrease: () => _adjust('ritiro', 30),
                        accentColor: AppColors.warning,
                        subtitle:
                            'Aggiunta al team se un membro si ritira ma il compagno continua',
                      ),
                      const SizedBox(height: 10),
                      _PenaltyRow(
                        label: 'Pilota mancante alla partenza',
                        icon: Icons.person_remove_outlined,
                        value: _settings!.pilotaMancante,
                        onDecrease: () => _adjust('mancante', -30),
                        onIncrease: () => _adjust('mancante', 30),
                        accentColor: AppColors.warning,
                        subtitle:
                            'Aggiunta al tempo totale della squadra per ogni pilota sotto il minimo richiesto dall\'evento',
                      ),
                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_outlined),
                          label: Text(
                              _saving ? 'Salvataggio...' : 'Salva per questo evento'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reset button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving || !_hasOverride
                              ? null
                              : _resetToDefault,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text(
                              'Ripristina valori predefiniti globali'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _PenaltyRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final Color? accentColor;
  final String? subtitle;

  const _PenaltyRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.accentColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
              // Decrease
              _StepBtn(
                icon: Icons.remove,
                onTap: value > 0 ? onDecrease : null,
              ),
              const SizedBox(width: 6),
              // Value display
              SizedBox(
                width: 72,
                child: Text(
                  PenaltySettingsModel.formatSeconds(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: value > 0 ? color : AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Increase
              _StepBtn(
                icon: Icons.add,
                onTap: onIncrease,
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                subtitle!,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null
          ? AppColors.accent.withValues(alpha: 0.1)
          : AppColors.border.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: onTap != null
                ? AppColors.accent
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
