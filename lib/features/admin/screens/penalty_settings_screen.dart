import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

class PenaltySettingsScreen extends ConsumerStatefulWidget {
  const PenaltySettingsScreen({super.key});

  @override
  ConsumerState<PenaltySettingsScreen> createState() =>
      _PenaltySettingsScreenState();
}

class _PenaltySettingsScreenState
    extends ConsumerState<PenaltySettingsScreen> {
  PenaltySettingsModel? _settings;
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
      final s =
          await ref.read(firestoreServiceProvider).getPenaltySettings();
      if (mounted) setState(() { _settings = s; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _errorMsg = '$e'; _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(firestoreServiceProvider).savePenaltySettings(_settings!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Penalità salvate con successo'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
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
        _ => _settings,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Penalità'),
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
                          setState(() { _loading = true; _errorMsg = null; });
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
                          color: AppColors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: AppColors.accent, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Le penalità vengono aggiunte al tempo di ogni prova speciale. '
                                'Applicabili a tutti gli eventi.',
                                style: TextStyle(
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
                          label: Text(_saving ? 'Salvataggio...' : 'Salva penalità'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reset button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _settings = const PenaltySettingsModel()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Ripristina valori predefiniti'),
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
