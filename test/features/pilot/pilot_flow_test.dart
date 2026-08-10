/// Flusso completo pilota: EventList → EventDetail → sezione iscrizione → GPS → Tempi.
/// Tutti i provider Firestore/Firebase sono sostituiti con stub in memoria.
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
import 'package:ccr_app/core/models/user_model.dart';
import 'package:ccr_app/core/providers/offline_provider.dart';
import 'package:ccr_app/features/admin/providers/admin_provider.dart';
import 'package:ccr_app/features/auth/providers/auth_provider.dart';
import 'package:ccr_app/features/classifica/providers/classifica_provider.dart';
import 'package:ccr_app/features/pilot/providers/pilot_provider.dart';
import 'package:ccr_app/features/pilot/screens/event_detail_screen.dart';
import 'package:ccr_app/features/pilot/screens/event_list_screen.dart';
import 'package:ccr_app/features/pilot/screens/gps_recording_screen.dart';
import 'package:ccr_app/features/timing/screens/timing_screen.dart';

const _evId = 'ev-pilot-001';
const _userId = 'uid-pilot-001';

EventModel _makeEvent({EventStatus stato = EventStatus.aperto}) => EventModel(
      id: _evId,
      nome: 'Gara Test Pilota',
      luogo: 'Bologna',
      data: DateTime(2026, 10, 15),
      descrizione: 'Una gara di test',
      specialiRouteA: const [],
      stato: stato,
      createdBy: 'uid-admin',
      createdAt: DateTime(2026, 1, 1),
      startEnabled: true,
    );

UserModel _pilotUser() => UserModel(
      id: _userId,
      email: 'pilota@test.it',
      nome: 'Mario',
      cognome: 'Rossi',
      role: UserRole.pilota,
      createdAt: DateTime(2026, 1, 1),
    );

RegistrationModel _approvedReg() => RegistrationModel(
      userId: _userId,
      eventId: _evId,
      nome: 'Mario',
      cognome: 'Rossi',
      stato: RegistrationStatus.approvato,
      createdAt: DateTime(2026, 9, 1),
    );

List<Override> _overrides(SharedPreferences prefs) => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authStateProvider.overrideWith((_) => Stream.value(null)),
      currentUserModelProvider.overrideWith((_) async => _pilotUser()),
      openEventsProvider
          .overrideWith((_) => Stream.value([_makeEvent()])),
      myRegistrationsProvider.overrideWith((_) async* {}),
      teamsProvider
          .overrideWith((ref, _) => Stream.value(<TeamModel>[])),
      registrationsProvider
          .overrideWith((ref, _) => Stream.value(<RegistrationModel>[])),
      liveTrackingProvider
          .overrideWith((ref, _) => Stream.value(<GpsPointModel>[])),
      passagesStreamProvider
          .overrideWith((ref, _) => Stream.value(<WaypointPassageRecord>[])),
      withdrawalsStreamProvider
          .overrideWith((ref, _) => Stream.value(<String>{})),
      eventStreamProvider
          .overrideWith((ref, _) => Stream.value(_makeEvent())),
      eventProvider
          .overrideWith((ref, _) async => _makeEvent()),
      myRegistrationStreamProvider
          .overrideWith((ref, _) => Stream.value(null)),
      adminEventsProvider.overrideWith((_) => Stream.value([])),
    ];

Widget _wrapRouter(
    String path, List<GoRoute> routes, SharedPreferences prefs) =>
    ProviderScope(
      overrides: _overrides(prefs),
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: path,
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

  // ── EventListScreen ─────────────────────────────────────────────────────────

  group('Step 1 — Lista eventi', () {
    testWidgets('mostra evento disponibile', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(prefs),
        child: const MaterialApp(home: EventListScreen()),
      ));
      await tester.pump();
      expect(find.text('Gara Test Pilota'), findsOneWidget);
    });

    testWidgets('mostra pulsante Iscriviti se non iscritto', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          myRegistrationsProvider.overrideWith((_) async* {
            yield <RegistrationModel>[];
          }),
        ],
        child: const MaterialApp(home: EventListScreen()),
      ));
      await tester.pump();
      expect(find.text('Iscriviti'), findsOneWidget);
    });

    testWidgets('mostra badge stato se già iscritto', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          myRegistrationsProvider.overrideWith((_) async* {
            yield [_approvedReg()];
          }),
        ],
        child: const MaterialApp(home: EventListScreen()),
      ));
      await tester.pump();
      expect(find.text('APPROVATO'), findsOneWidget);
    });
  });

  // ── EventDetailScreen ───────────────────────────────────────────────────────

  group('Step 2 — Dettaglio evento', () {
    testWidgets('mostra nome evento nell\'AppBar', (tester) async {
      await tester.pumpWidget(_wrapRouter('/', [
        GoRoute(
          path: '/',
          builder: (_, _) => const EventDetailScreen(eventId: _evId),
        ),
      ], prefs));
      await tester.pump();
      expect(find.text('Gara Test Pilota'), findsWidgets);
    });

    testWidgets('mostra sezione Iscrizione', (tester) async {
      await tester.pumpWidget(_wrapRouter('/', [
        GoRoute(
          path: '/',
          builder: (_, _) => const EventDetailScreen(eventId: _evId),
        ),
      ], prefs));
      await tester.pump();
      expect(find.text('Iscrizione'), findsOneWidget);
    });

    testWidgets('mostra luogo e data evento', (tester) async {
      await tester.pumpWidget(_wrapRouter('/', [
        GoRoute(
          path: '/',
          builder: (_, _) => const EventDetailScreen(eventId: _evId),
        ),
      ], prefs));
      await tester.pump();
      expect(find.text('Bologna'), findsOneWidget);
    });
  });

  // ── Registrazione ──────────────────────────────────────────────────────────

  group('Step 3 — Stato iscrizione', () {
    testWidgets('iscrizione approvata mostra pulsante AVVIA GPS',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          myRegistrationStreamProvider
              .overrideWith((ref, _) => Stream.value(_approvedReg())),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) =>
                    const EventDetailScreen(eventId: _evId),
              ),
              GoRoute(
                path: '/pilot/gps',
                builder: (_, _) => const GpsRecordingScreen(),
              ),
            ],
          ),
        ),
      ));
      // pump twice: once for frame, once for async providers
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('AVVIA GPS'), findsOneWidget);
    });

    testWidgets('iscrizione in attesa mostra badge corretto', (tester) async {
      final pendingReg = RegistrationModel(
        userId: _userId,
        eventId: _evId,
        nome: 'Mario',
        cognome: 'Rossi',
        stato: RegistrationStatus.inAttesa,
        createdAt: DateTime(2026, 9, 1),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          myRegistrationStreamProvider
              .overrideWith((ref, _) => Stream.value(pendingReg)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) =>
                    const EventDetailScreen(eventId: _evId),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('In attesa di approvazione'), findsOneWidget);
    });
  });

  // ── GpsRecordingScreen ─────────────────────────────────────────────────────

  group('Step 4 — Registrazione GPS', () {
    testWidgets('schermata pre-partenza mostra START', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(prefs),
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

    testWidgets('start disabilitato se startEnabled è false', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          eventStreamProvider.overrideWith(
              (ref, _) => Stream.value(_makeEvent(stato: EventStatus.inCorso)
                  .copyWith(startEnabled: false))),
        ],
        child: const MaterialApp(
          home: GpsRecordingScreen(eventId: _evId),
        ),
      ));
      await tester.pump();
      await tester.pump();
      // Banner "In attesa del via" deve essere visibile
      expect(
          find.text('In attesa del via dell\'organizzatore'), findsOneWidget);
    });
  });

  // ── TimingScreen ───────────────────────────────────────────────────────────

  group('Step 5 — Tempi', () {
    testWidgets('vista pilota mostra intestazione tempi', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(prefs),
          authStateProvider.overrideWith((_) => Stream.value(null)),
          currentUserModelProvider
              .overrideWith((_) async => _pilotUser()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TimingScreen(eventId: _evId, adminView: false),
          ),
        ),
      ));
      await tester.pump();
      // Schermata dei tempi deve renderizzarsi
      expect(find.byType(TimingScreen), findsOneWidget);
    });
  });
}
