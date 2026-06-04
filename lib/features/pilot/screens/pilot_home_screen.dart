import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../../core/widgets/notification_listener_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pilot_provider.dart';
import 'event_list_screen.dart';
import 'gps_recording_screen.dart';

class PilotHomeScreen extends ConsumerStatefulWidget {
  const PilotHomeScreen({super.key});

  @override
  ConsumerState<PilotHomeScreen> createState() => _PilotHomeScreenState();
}

class _PilotHomeScreenState extends ConsumerState<PilotHomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final gps = ref.watch(gpsServiceProvider);
    final userAsync = ref.watch(currentUserModelProvider);

    final screens = [
      const EventListScreen(),
      GpsRecordingScreen(eventId: null),
      _ProfilePage(
        onLogout: () async {
          await ref.read(authServiceProvider).signOut();
          if (context.mounted) context.go('/login');
        },
      ),
    ];

    return NotificationListenerWidget(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Text('CCR ',
                style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900)),
            Text('Pilota'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Recording status banner
          if (gps.isRecording)
            Container(
              width: double.infinity,
              color: AppColors.accent.withValues(alpha: 0.15),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'GPS attivo  ',
                    style: TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    LocationUtils.formatDuration(gps.elapsed),
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  _ModeChip(mode: gps.mode),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 1),
                    child: const Text('Dettagli',
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 12)),
                  ),
                ],
              ),
            ),
          Expanded(child: screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: AppColors.cardBackground,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Gare',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.gps_fixed),
                if (gps.isRecording)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            label: 'GPS',
          ),
          BottomNavigationBarItem(
            icon: userAsync.when(
              data: (u) => const Icon(Icons.person),
              loading: () => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textSecondary)),
              error: (e, st) => const Icon(Icons.person),
            ),
            label: userAsync.valueOrNull?.nome ?? 'Profilo',
          ),
        ],
      ),
    ));
  }
}

class _ModeChip extends StatelessWidget {
  final GpsMode mode;
  const _ModeChip({required this.mode});

  Color get color {
    switch (mode) {
      case GpsMode.idle:
        return AppColors.textSecondary;
      case GpsMode.transfer:
        return AppColors.textSecondary;
      case GpsMode.inSpecial:
        return AppColors.accent;
      case GpsMode.nearWaypoint:
        return AppColors.warning;
    }
  }

  String get label {
    switch (mode) {
      case GpsMode.idle:
        return 'IDLE';
      case GpsMode.transfer:
        return 'TRASF.';
      case GpsMode.inSpecial:
        return 'SPEC.';
      case GpsMode.nearWaypoint:
        return 'NEAR WP';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ProfilePage extends ConsumerWidget {
  final VoidCallback onLogout;
  const _ProfilePage({required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserModelProvider);

    return userAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (user) {
        if (user == null) {
          return const Center(
            child: Text('Utente non trovato',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${user.nome.isNotEmpty ? user.nome[0] : ''}${user.cognome.isNotEmpty ? user.cognome[0] : ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user.nomeCompleto,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                user.email,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  user.role.name.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, color: AppColors.error),
                  label: const Text('Logout',
                      style: TextStyle(color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
