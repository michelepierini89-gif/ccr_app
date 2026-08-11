import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/profile_image_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../../core/widgets/ccr_avatar.dart';
import '../../../core/widgets/notification_listener_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/pilot_provider.dart';
import '../../../core/models/championship_model.dart';
import 'event_list_screen.dart';
import 'gps_recording_screen.dart';

class PilotHomeScreen extends ConsumerStatefulWidget {
  const PilotHomeScreen({super.key});

  @override
  ConsumerState<PilotHomeScreen> createState() => _PilotHomeScreenState();
}

class _PilotHomeScreenState extends ConsumerState<PilotHomeScreen> {
  int _selectedIndex = 0;

  static const _tabTitles = ['Le mie gare', 'GPS', 'Campionati', 'Profilo'];

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Uscire dall\'app?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Sei sicuro di voler uscire?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final gps = ref.watch(gpsServiceProvider);
    final userAsync = ref.watch(currentUserModelProvider);
    final offlineQueue = ref.watch(offlineQueueProvider);
    final pendingCount = offlineQueue.totalPendingCount;

    final screens = [
      const EventListScreen(),
      GpsRecordingScreen(eventId: null),
      const _ChampionshipsPage(),
      _ProfilePage(
        onLogout: () async {
          await ref.read(authServiceProvider).signOut();
          if (context.mounted) context.go('/login');
        },
      ),
    ];

    final profileLabel = userAsync.valueOrNull?.nome ?? 'Profilo';
    // GPS tab is index 1, championships tab is index 2, profile tab is index 3

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _onWillPop();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: NotificationListenerWidget(
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                const Text('CCR ',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900)),
                Text(_tabTitles[_selectedIndex]),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Offline pending banner
              if (pendingCount > 0)
                Container(
                  width: double.infinity,
                  color: AppColors.warning.withValues(alpha: 0.12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$pendingCount element${pendingCount == 1 ? "o" : "i"} in attesa di sincronizzazione',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(offlineQueueProvider)
                            .syncPending(
                                ref.read(firestoreServiceProvider))
                            .ignore(),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Sincronizza',
                            style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

              // Recording status banner
              if (gps.isRecording)
                Container(
                  width: double.infinity,
                  color: AppColors.accent.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'GPS attivo  ',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold),
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
                        onTap: () =>
                            setState(() => _selectedIndex = 1),
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
            selectedFontSize: 12,
            unselectedFontSize: 11,
            elevation: 8,
            items: [
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.flag_outlined),
                    if (pendingCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                activeIcon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.flag),
                    if (pendingCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                label: 'Gare',
              ),
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.gps_not_fixed),
                    if (gps.isRecording)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                activeIcon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.gps_fixed),
                    if (gps.isRecording)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                label: 'GPS',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.emoji_events_outlined),
                activeIcon: Icon(Icons.emoji_events),
                label: 'Campionati',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person_outline),
                activeIcon: const Icon(Icons.person),
                label: profileLabel.length > 10
                    ? profileLabel.substring(0, 10)
                    : profileLabel,
              ),
            ],
          ),
        ),
      ),
    );
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

// ── Championships page (embedded in bottom nav) ───────────────────────────────

class _ChampionshipsPage extends ConsumerWidget {
  const _ChampionshipsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final champsAsync = ref.watch(_allChampionshipsProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () async => ref.invalidate(_allChampionshipsProvider),
      child: champsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 60),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.cloud_off, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  const Text('Impossibile caricare i campionati',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(_allChampionshipsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Riprova'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          color: AppColors.textSecondary, size: 64),
                      SizedBox(height: 16),
                      Text('Nessun campionato',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        'I campionati creati dall\'organizzatore\nappariranno qui',
                        style: TextStyle(
                            color: AppColors.textSecondary, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                    'Stagione ${c.stagione} · ${c.eventIds.length} gare',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                  onTap: () =>
                      context.push('/pilot/championships/${c.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final _allChampionshipsProvider = StreamProvider<List<ChampionshipModel>>((ref) {
  return ref.watch(firestoreServiceProvider).getChampionships();
});

class _ProfilePage extends ConsumerStatefulWidget {
  final VoidCallback onLogout;
  const _ProfilePage({required this.onLogout});

  @override
  ConsumerState<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<_ProfilePage> {
  final _imageService = ProfileImageService();
  bool _uploading = false;

  Future<void> _changePhoto(UserModel user) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.accent),
              title: const Text('Scegli dalla galleria',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.accent),
              title: const Text('Scatta una foto',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            if (user.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: const Text('Rimuovi immagine',
                    style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.of(ctx).pop(),
              ),
          ],
        ),
      ),
    );
    if (source == null) {
      // "Rimuovi immagine" selezionato (pop senza valore) — o dialog chiuso.
      if (user.photoUrl == null || !mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Rimuovere l\'immagine profilo?',
              style: TextStyle(color: AppColors.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Rimuovi'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      setState(() => _uploading = true);
      try {
        await ref
            .read(firestoreServiceProvider)
            .saveUserPhotoUrl(user.id, null);
        await _imageService.deleteIfExists(user.photoUrl);
        ref.invalidate(currentUserModelProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Errore rimozione immagine: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await _imageService.pickAndProcess(source);
      if (bytes == null) return;
      final newUrl = await _imageService.upload(user.id, bytes);
      await ref
          .read(firestoreServiceProvider)
          .saveUserPhotoUrl(user.id, newUrl);
      await _imageService.deleteIfExists(user.photoUrl);
      ref.invalidate(currentUserModelProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore aggiornamento immagine: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              GestureDetector(
                onTap: _uploading ? null : () => _changePhoto(user),
                child: Stack(
                  children: [
                    CcrAvatar(
                      photoUrl: user.photoUrl,
                      nome: user.nome,
                      cognome: user.cognome,
                      size: 80,
                    ),
                    if (_uploading)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.background, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 14, color: Colors.white),
                        ),
                      ),
                  ],
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/pilot/stats'),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Le mie statistiche'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/pilot/offline-maps'),
                  icon: const Icon(Icons.map_outlined,
                      color: AppColors.textSecondary),
                  label: const Text('Mappe offline',
                      style: TextStyle(color: AppColors.textSecondary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/pilot/regolamento'),
                  icon: const Icon(Icons.description_outlined,
                      color: AppColors.textSecondary),
                  label: const Text('Regolamento',
                      style: TextStyle(color: AppColors.textSecondary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/pilot/guida'),
                  icon: const Icon(Icons.help_outline,
                      color: AppColors.textSecondary),
                  label: const Text('Guida all\'uso',
                      style: TextStyle(color: AppColors.textSecondary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: widget.onLogout,
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
