/// Verifica che tutte le route principali si rendano senza eccezioni.
/// I provider Firebase/Firestore sono sostituiti con stub in memoria.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/gps_point_model.dart';
import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/providers/offline_provider.dart';
import 'package:ccr_app/features/admin/providers/admin_provider.dart';
import 'package:ccr_app/features/auth/providers/auth_provider.dart';
import 'package:ccr_app/features/auth/screens/login_screen.dart';
import 'package:ccr_app/features/auth/screens/register_screen.dart';
import 'package:ccr_app/features/admin/screens/admin_home_screen.dart';
import 'package:ccr_app/features/admin/screens/event_management_screen.dart';
import 'package:ccr_app/features/classifica/providers/classifica_provider.dart';
import 'package:ccr_app/features/pilot/providers/pilot_provider.dart';
import 'package:ccr_app/features/pilot/screens/event_detail_screen.dart';
import 'package:ccr_app/features/pilot/screens/event_list_screen.dart';
import 'package:ccr_app/features/pilot/screens/gps_recording_screen.dart';

const _evId = 'ev-001';

EventModel _sampleEvent() => EventModel(
      id: _evId,
      nome: 'Rally Test',
      luogo: 'Roma',
      data: DateTime(2026, 9, 1),
      descrizione: 'Descrizione test',
      speciali: const [],
      stato: EventStatus.aperto,
      createdBy: 'uid-admin',
      createdAt: DateTime(2026, 1, 1),
    );

List<Override> _commonOverrides(SharedPreferences prefs) => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authStateProvider.overrideWith((_) => Stream.value(null)),
      currentUserModelProvider.overrideWith((_) async => null),
      adminEventsProvider.overrideWith((_) => Stream.value([])),
      openEventsProvider.overrideWith((_) => Stream.value([])),
      myRegistrationsProvider.overrideWith((_) async* {}),
      teamsProvider.overrideWith((ref, _) => Stream.value(<TeamModel>[])),
      registrationsProvider
          .overrideWith((ref, _) => Stream.value(<RegistrationModel>[])),
      liveTrackingProvider
          .overrideWith((ref, _) => Stream.value(<GpsPointModel>[])),
      passagesStreamProvider
          .overrideWith((ref, _) => Stream.value(<WaypointPassageRecord>[])),
      withdrawalsStreamProvider
          .overrideWith((ref, _) => Stream.value(<String>{})),
      eventStreamProvider
          .overrideWith((ref, _) => Stream.value(_sampleEvent())),
      eventProvider.overrideWith((ref, _) async => _sampleEvent()),
      myRegistrationStreamProvider
          .overrideWith((ref, _) => Stream.value(null)),
    ];

Widget _wrap(Widget child, SharedPreferences prefs) => ProviderScope(
      overrides: _commonOverrides(prefs),
      child: MaterialApp(home: child),
    );

Widget _wrapRouter(
        String initialPath, List<GoRoute> routes, SharedPreferences prefs) =>
    ProviderScope(
      overrides: _commonOverrides(prefs),
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: initialPath,
          routes: routes,
        ),
      ),
    );

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    await initializeDateFormatting('it_IT');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('LoginScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), prefs));
      await tester.pump();
      expect(find.text('Accedi'), findsWidgets);
    });

    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), prefs));
      await tester.pump();
      expect(find.text('Email'), findsWidgets);
      expect(find.text('Password'), findsWidgets);
    });

    testWidgets('shows validation error when form submitted empty',
        (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), prefs));
      await tester.pump();
      await tester.tap(find.text('Accedi').last);
      await tester.pump();
      expect(find.text('Inserisci la tua email'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), prefs));
      await tester.pump();
      expect(find.text('Crea account'), findsWidgets);
    });

    testWidgets('shows PILOTA / ADMIN role chips', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), prefs));
      await tester.pump();
      expect(find.text('PILOTA'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('admin code field appears when ADMIN chip selected',
        (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), prefs));
      await tester.pump();
      await tester.tap(find.text('ADMIN'));
      await tester.pump();
      expect(find.text('Codice admin'), findsOneWidget);
    });
  });

  group('AdminHomeScreen', () {
    testWidgets('renders with empty events list', (tester) async {
      await tester.pumpWidget(_wrap(const AdminHomeScreen(), prefs));
      await tester.pump();
      expect(find.text('Nessun evento'), findsOneWidget);
    });

    testWidgets('shows FAB to create event', (tester) async {
      await tester.pumpWidget(_wrap(const AdminHomeScreen(), prefs));
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('EventListScreen', () {
    testWidgets('renders with empty list', (tester) async {
      await tester.pumpWidget(_wrap(const EventListScreen(), prefs));
      await tester.pump();
      expect(find.text('Nessuna gara disponibile'), findsOneWidget);
    });

    testWidgets('renders events when provider has data', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._commonOverrides(prefs),
          openEventsProvider
              .overrideWith((_) => Stream.value([_sampleEvent()])),
        ],
        child: const MaterialApp(home: EventListScreen()),
      ));
      await tester.pump();
      expect(find.text('Rally Test'), findsOneWidget);
    });
  });

  group('EventDetailScreen', () {
    testWidgets('renders event name in AppBar', (tester) async {
      await tester.pumpWidget(_wrapRouter(
        '/',
        [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const EventDetailScreen(eventId: _evId),
          ),
        ],
        prefs,
      ));
      await tester.pump();
      expect(find.text('Rally Test'), findsWidgets);
    });

    testWidgets('shows Iscrizione section', (tester) async {
      await tester.pumpWidget(_wrapRouter(
        '/',
        [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const EventDetailScreen(eventId: _evId),
          ),
        ],
        prefs,
      ));
      await tester.pump();
      expect(find.text('Iscrizione'), findsOneWidget);
    });

    testWidgets('shows Prove Speciali section when no specials',
        (tester) async {
      await tester.pumpWidget(_wrapRouter(
        '/',
        [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const EventDetailScreen(eventId: _evId),
          ),
        ],
        prefs,
      ));
      await tester.pump();
      // With no specials, the 'Prove Speciali' title is absent
      expect(find.text('Prove Speciali'), findsNothing);
    });
  });

  group('EventManagementScreen', () {
    testWidgets('shows 5 tab labels', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._commonOverrides(prefs),
          eventStreamProvider
              .overrideWith((ref, _) => Stream.value(_sampleEvent())),
          myRegistrationStreamProvider
              .overrideWith((ref, _) => Stream.value(null)),
        ],
        child: MaterialApp(
          home: const EventManagementScreen(eventId: _evId),
        ),
      ));
      await tester.pump();
      expect(find.text('Tracciato'), findsOneWidget);
      expect(find.text('Iscrizioni'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Classifica'), findsOneWidget);
      expect(find.text('Tempi'), findsOneWidget);
    });
  });

  group('GpsRecordingScreen', () {
    testWidgets('renders pre-start view without event', (tester) async {
      await tester.pumpWidget(_wrap(const GpsRecordingScreen(), prefs));
      await tester.pump();
      expect(find.text('START'), findsOneWidget);
    });

    testWidgets('renders pre-start view with eventId', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._commonOverrides(prefs),
          eventStreamProvider
              .overrideWith((ref, _) => Stream.value(_sampleEvent())),
          eventProvider.overrideWith((ref, _) async => _sampleEvent()),
        ],
        child: const MaterialApp(
          home: GpsRecordingScreen(eventId: _evId),
        ),
      ));
      // Un pump extra: myPilotStatusProvider dipende da authStateProvider
      // (2 hop async, doc inesistente → nessun raceStatus), il primo pump
      // risolve solo authStateProvider.
      await tester.pump();
      await tester.pump();
      expect(find.text('START'), findsOneWidget);
    });
  });
}
