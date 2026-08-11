import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/models/user_model.dart';
import 'core/providers/offline_provider.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/notification_listener_widget.dart';
import 'features/admin/providers/admin_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/admin/screens/admin_home_screen.dart';
import 'features/admin/screens/championship_screen.dart';
import 'features/admin/screens/create_event_screen.dart';
import 'features/admin/screens/event_management_screen.dart';
import 'features/admin/screens/registrations_screen.dart';
import 'features/admin/screens/live_tracking_screen.dart';
import 'features/pilot/screens/championship_standings_screen.dart';
import 'features/pilot/screens/pilot_home_screen.dart';
import 'features/pilot/screens/event_detail_screen.dart';
import 'features/pilot/screens/team_screen.dart';
import 'features/pilot/screens/gps_recording_screen.dart';
import 'features/pilot/screens/starting_order_pilot_screen.dart';
import 'features/pilot/screens/race_result_screen.dart';
import 'features/pilot/screens/pilot_stats_screen.dart';
import 'features/admin/screens/penalty_settings_screen.dart';
import 'features/admin/screens/track_replay_screen.dart';
import 'features/admin/screens/diagnostic_log_analyzer_screen.dart';
import 'features/classifica/screens/classifica_screen.dart';
import 'features/map/screens/offline_maps_screen.dart';
import 'features/pilot/screens/regolamento_screen.dart';
import 'features/pilot/screens/guida_screen.dart';
import 'features/admin/screens/users_list_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final user = await ref.read(authStateProvider.future);
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) {
        final userModel = await ref.read(currentUserModelProvider.future);
        if (userModel?.role == UserRole.admin) return '/admin';
        // Promemoria permessi GPS background (Parte 2E): mostrato una sola
        // volta al primo accesso di un pilota, mai agli admin (non
        // registrano GPS).
        final prefs = ref.read(sharedPreferencesProvider);
        final onboarded =
            prefs.getBool(OnboardingScreen.completedKey) ?? false;
        if (!onboarded) return '/onboarding';
        return '/pilot';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Admin routes
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
        routes: [
          GoRoute(
            path: 'create-event',
            builder: (context, state) => const CreateEventScreen(),
          ),
          GoRoute(
            path: 'track-replay',
            builder: (context, state) => const TrackReplayScreen(),
          ),
          GoRoute(
            path: 'diagnostic-log-analyzer',
            builder: (context, state) => const DiagnosticLogAnalyzerScreen(),
          ),
          GoRoute(
            path: 'users',
            builder: (context, state) => const UsersListScreen(),
          ),
          GoRoute(
            path: 'championships',
            builder: (context, state) => const ChampionshipScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return ChampionshipManagementScreen(championshipId: id);
                },
                routes: [
                  GoRoute(
                    path: 'standings',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return ChampionshipAdminStandingsScreen(
                          championshipId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'event/:id',
            builder: (context, state) {
              final eventId = state.pathParameters['id']!;
              return EventManagementScreen(eventId: eventId);
            },
            routes: [
              GoRoute(
                path: 'registrations',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return Scaffold(
                    appBar: AppBar(title: const Text('Iscrizioni')),
                    body: SafeArea(
                        bottom: true,
                        child: RegistrationsScreen(eventId: eventId)),
                  );
                },
              ),
              GoRoute(
                path: 'live',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return Scaffold(
                    appBar: AppBar(title: const Text('Live Tracking')),
                    body: SafeArea(
                        bottom: true,
                        child: LiveTrackingScreen(eventId: eventId)),
                  );
                },
              ),
              GoRoute(
                path: 'penalty-settings',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return PenaltySettingsScreen(eventId: eventId);
                },
              ),
            ],
          ),
        ],
      ),
      // Pilot routes
      GoRoute(
        path: '/pilot',
        builder: (context, state) => const PilotHomeScreen(),
        routes: [
          GoRoute(
            path: 'event/:id',
            builder: (context, state) {
              final eventId = state.pathParameters['id']!;
              return EventDetailScreen(eventId: eventId);
            },
            routes: [
              GoRoute(
                path: 'team',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return TeamScreen(eventId: eventId);
                },
              ),
              GoRoute(
                path: 'classifica',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return ClassificaScreen(eventId: eventId);
                },
              ),
              GoRoute(
                path: 'starting-order',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return StartingOrderPilotScreen(eventId: eventId);
                },
              ),
              GoRoute(
                path: 'race-result',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return RaceResultScreen(eventId: eventId);
                },
              ),
              GoRoute(
                path: 'regolamento',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return RegolamentoScreen(eventId: eventId);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'gps',
            builder: (context, state) {
              final eventId = state.uri.queryParameters['eventId'];
              return GpsRecordingScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: 'championships/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ChampionshipStandingsScreen(championshipId: id);
            },
          ),
          GoRoute(
            path: 'stats',
            builder: (context, state) => const PilotStatsScreen(),
          ),
          GoRoute(
            path: 'offline-maps',
            builder: (context, state) => const OfflineMapsScreen(),
          ),
          GoRoute(
            path: 'regolamento',
            builder: (context, state) => const RegolamentoScreen(),
          ),
          GoRoute(
            path: 'guida',
            builder: (context, state) => const GuidaScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF0a0c12),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Pagina non trovata',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Torna al login'),
            ),
          ],
        ),
      ),
    ),
  );
});

class CcrApp extends ConsumerStatefulWidget {
  const CcrApp({super.key});

  @override
  ConsumerState<CcrApp> createState() => _CcrAppState();
}

class _CcrAppState extends ConsumerState<CcrApp> {
  @override
  void initState() {
    super.initState();
    // Inizializza FCM quando l'utente è loggato
    ref.listenManual(authStateProvider, (_, next) {
      final user = next.valueOrNull;
      if (user != null) {
        FcmService.initialize(
          user.uid,
          ref.read(firestoreServiceProvider),
        );
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_routerProvider);

    return NotificationListenerWidget(
      child: MaterialApp.router(
        title: 'CCR - Coppa Canta Rally',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    );
  }
}
