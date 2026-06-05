import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/models/user_model.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/notification_listener_widget.dart';
import 'features/admin/providers/admin_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
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
import 'features/admin/screens/penalty_settings_screen.dart';
import 'features/classifica/screens/classifica_screen.dart';

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
            path: 'penalty-settings',
            builder: (context, state) => const PenaltySettingsScreen(),
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
                      return ChampionshipStandingsScreen(
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
                    body: RegistrationsScreen(eventId: eventId),
                  );
                },
              ),
              GoRoute(
                path: 'live',
                builder: (context, state) {
                  final eventId = state.pathParameters['id']!;
                  return Scaffold(
                    appBar: AppBar(title: const Text('Live Tracking')),
                    body: LiveTrackingScreen(eventId: eventId),
                  );
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
