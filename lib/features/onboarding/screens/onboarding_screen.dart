import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/battery_setup_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/widgets/ccr_button.dart';

/// Mostrata una sola volta, al primo accesso di un pilota dopo
/// l'installazione: spiega perché l'app ha bisogno del permesso posizione
/// "sempre" e dell'esenzione ottimizzazione batteria (il GPS in background
/// è la funzione più critica dell'app — senza questi permessi la traccia si
/// perde a schermo spento), poi li richiede in sequenza.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const completedKey = 'onboarding_completed_v1';

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _busy = false;

  Future<void> _requestLocation() async {
    setState(() => _busy = true);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always) {
      // Android 11+ non permette di chiedere "sempre" nello stesso dialog
      // del permesso in primo piano: l'utente deve confermarlo dalle
      // impostazioni dell'app.
      await Geolocator.openAppSettings();
    }
    if (mounted) setState(() { _busy = false; _step = 1; });
  }

  Future<void> _requestBattery() async {
    setState(() => _busy = true);
    await BatterySetupService.requestIgnoreBatteryOptimizations();
    if (mounted) setState(() { _busy = false; _step = 2; });
  }

  Future<void> _finish() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(OnboardingScreen.completedKey, true);
    if (mounted) context.go('/pilot');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.gps_fixed, color: AppColors.accent, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Configurazione GPS in background',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Il GPS in background è la funzione più critica di CCR: '
                'senza i permessi giusti la traccia e i tempi di gara si '
                'perdono quando spegni lo schermo o metti via il telefono. '
                'Configuriamoli subito, ci vuole un minuto.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 32),
              _StepTile(
                index: 1,
                title: 'Permesso posizione "Consenti sempre"',
                subtitle: 'Serve per registrare la traccia anche con l\'app '
                    'in background durante la gara.',
                done: _step > 0,
                active: _step == 0,
              ),
              const SizedBox(height: 16),
              _StepTile(
                index: 2,
                title: 'Disattiva ottimizzazione batteria',
                subtitle: 'Evita che Android chiuda il GPS a schermo spento '
                    'per risparmiare energia.',
                done: _step > 1,
                active: _step == 1,
              ),
              const Spacer(),
              if (_step == 0)
                CcrButton(
                  label: 'Concedi permesso posizione',
                  isLoading: _busy,
                  onPressed: _requestLocation,
                ),
              if (_step == 1)
                CcrButton(
                  label: 'Disattiva ottimizzazione batteria',
                  isLoading: _busy,
                  onPressed: _requestBattery,
                ),
              if (_step >= 2)
                CcrButton(
                  label: 'Continua',
                  onPressed: _finish,
                ),
              if (_step < 2) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _step++),
                  child: const Text('Salta per ora',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final bool done;
  final bool active;

  const _StepTile({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : (active ? AppColors.accent : AppColors.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.15),
          child: done
              ? Icon(Icons.check, color: color, size: 16)
              : Text('$index', style: TextStyle(color: color, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: active || done
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
