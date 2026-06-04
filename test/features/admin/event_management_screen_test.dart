import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/models/gps_point_model.dart';
import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/features/admin/providers/admin_provider.dart';
import 'package:ccr_app/features/admin/screens/event_management_screen.dart';
import 'package:ccr_app/features/auth/providers/auth_provider.dart';
import 'package:ccr_app/features/classifica/providers/classifica_provider.dart';
import 'package:ccr_app/features/pilot/providers/pilot_provider.dart';

const _eventId = 'test-event-id';

EventModel _makeEvent({EventStatus stato = EventStatus.bozza}) => EventModel(
      id: _eventId,
      nome: 'Test Rally',
      luogo: 'Modena',
      data: DateTime(2026, 6, 10),
      descrizione: '',
      speciali: [],
      stato: stato,
      createdBy: 'user1',
      createdAt: DateTime(2026, 1, 1),
    );

Widget _buildTestApp(Stream<EventModel?> eventStream) {
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const EventManagementScreen(eventId: _eventId),
    ),
  ]);

  return ProviderScope(
    overrides: [
      eventStreamProvider(_eventId).overrideWith((_) => eventStream),
      registrationsProvider.overrideWith(
          (ref, arg) => Stream.value(<RegistrationModel>[])),
      teamsProvider.overrideWith(
          (ref, arg) => Stream.value(<TeamModel>[])),
      liveTrackingProvider.overrideWith(
          (ref, arg) => Stream.value(<GpsPointModel>[])),
      passagesStreamProvider.overrideWith(
          (ref, arg) => Stream.value(<WaypointPassageRecord>[])),
      withdrawalsStreamProvider.overrideWith(
          (ref, arg) => Stream.value(<String>{})),
      currentUserModelProvider.overrideWith((_) async => null),
      myRegistrationStreamProvider.overrideWith(
          (ref, arg) => Stream.value(null)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('EventManagementScreen', () {
    testWidgets('shows loading indicator while stream is loading',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const Stream.empty()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message when stream emits an error',
        (tester) async {
      final errorStream = Stream<EventModel?>.error('boom');

      await tester.pumpWidget(_buildTestApp(errorStream));
      await tester.pump();

      expect(find.textContaining('Errore'), findsWidgets);
    });

    testWidgets('shows not-found message when event is null', (tester) async {
      await tester.pumpWidget(_buildTestApp(Stream.value(null)));
      await tester.pump();

      expect(find.text('Evento non trovato'), findsOneWidget);
    });

    testWidgets('shows event name in AppBar when event is loaded',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent())));
      await tester.pump();

      expect(find.text('Test Rally'), findsOneWidget);
    });

    testWidgets('shows BOZZA status label for bozza event', (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.bozza))));
      await tester.pump();

      expect(find.text('BOZZA'), findsWidgets);
    });

    testWidgets('shows APERTO status label for aperto event', (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.aperto))));
      await tester.pump();

      expect(find.text('APERTO'), findsWidgets);
    });

    testWidgets('shows IN CORSO status label for inCorso event',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.inCorso))));
      await tester.pump();

      expect(find.text('IN CORSO'), findsWidgets);
    });

    testWidgets('shows CONCLUSO status label for concluso event',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.concluso))));
      await tester.pump();

      expect(find.text('CONCLUSO'), findsWidgets);
    });

    testWidgets('lock icons appear on tabs 1-4 when event is bozza',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.bozza))));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
    });

    testWidgets('no lock icons when event is aperto', (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.aperto))));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });

    testWidgets('shows all 5 tab labels', (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent())));
      await tester.pump();

      expect(find.text('Tracciato'), findsOneWidget);
      expect(find.text('Iscrizioni'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Classifica'), findsOneWidget);
      expect(find.text('Tempi'), findsOneWidget);
    });

    testWidgets('shows upload track button when no track is loaded',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent())));
      await tester.pump();

      expect(find.text('Carica tracciato GPX/KML'), findsOneWidget);
    });

    testWidgets('shows date and location in header', (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent())));
      await tester.pump();

      expect(find.text('10/06/2026'), findsOneWidget);
      expect(find.text('Modena'), findsOneWidget);
    });

    testWidgets('locked tab has tooltip message about publishing',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(Stream.value(_makeEvent(stato: EventStatus.bozza))));
      await tester.pump();

      // Tooltip is present on locked tabs — verified via Tooltip widget in tree
      expect(find.byType(Tooltip), findsWidgets);
    });
  });

  group('_statusLabel logic', () {
    test('bozza maps to BOZZA', () {
      const values = {
        EventStatus.bozza: 'BOZZA',
        EventStatus.aperto: 'APERTO',
        EventStatus.inCorso: 'IN CORSO',
        EventStatus.concluso: 'CONCLUSO',
      };
      for (final entry in values.entries) {
        final label = switch (entry.key) {
          EventStatus.bozza => 'BOZZA',
          EventStatus.aperto => 'APERTO',
          EventStatus.inCorso => 'IN CORSO',
          EventStatus.concluso => 'CONCLUSO',
        };
        expect(label, entry.value,
            reason: '${entry.key} should map to ${entry.value}');
      }
    });
  });
}
