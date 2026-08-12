/// Fix (bug test 18/08, "Carring CLO 3") — riproduce il bug reale: una
/// pilota ha "avviato la registrazione" e dopo pochi secondi il sistema ha
/// dichiarato la gara conclusa (0/4 PS, nessuna traccia). La causa reale
/// era `gps.isRecording` rimasto `true` in memoria (GpsService è un
/// provider globale mai disposato) senza riscontro nel documento di
/// tracking Firestore. Questo test verifica che la fonte di verità sia
/// Firestore: entrando su un evento il cui tracking NON risulta avviato,
/// uno stato locale residuo non deve produrre la vista di tracciamento
/// attivo (né quindi il pulsante FINE GARA raggiungibile).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/gps_point_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/providers/offline_provider.dart';
import 'package:ccr_app/core/services/gps_service.dart';
import 'package:ccr_app/features/admin/providers/admin_provider.dart';
import 'package:ccr_app/features/auth/providers/auth_provider.dart';
import 'package:ccr_app/features/classifica/providers/classifica_provider.dart';
import 'package:ccr_app/features/pilot/providers/pilot_provider.dart';
import 'package:ccr_app/features/pilot/screens/gps_recording_screen.dart';

const _evId = 'ev-orphan-001';

EventModel _sampleEvent() => EventModel(
      id: _evId,
      nome: 'Rally Test',
      luogo: 'Roma',
      data: DateTime(2026, 9, 1),
      descrizione: 'Descrizione test',
      specialiRouteA: const [],
      stato: EventStatus.aperto,
      createdBy: 'uid-admin',
      createdAt: DateTime(2026, 1, 1),
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

  testWidgets(
      'sessione locale orfana (isRecording=true, tracking non avviato su '
      'Firestore) non mostra la vista di tracciamento attivo', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
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
        // Fonte di verità: Firestore dice "nessun documento di tracking"
        // per questo evento, cioè gara mai avviata dal punto di vista del
        // backend — deve prevalere su qualunque stato locale.
        myPilotStatusProvider.overrideWith((ref, _) => Stream.value(null)),
        gpsServiceProvider.overrideWith((ref) {
          final gps = GpsService(
            ref.read(firestoreServiceProvider),
            ref.read(offlineQueueProvider),
            ref.read(imuFusionServiceProvider),
            ref.read(gnssStatusServiceProvider),
            ref.read(voiceAlertServiceProvider),
            ref.read(diagnosticLoggerProvider),
            ref.read(sharedPreferencesProvider),
          );
          // Simula una sessione precedente mai chiusa con
          // STOP/FINE GARA/RITIRO: isRecording==true per QUESTO evento
          // senza che Firestore ne sappia nulla — esattamente il bug
          // osservato in produzione.
          gps.debugMarkRecordingForTest(eventId: _evId, userId: 'stale-uid');
          return gps;
        }),
      ],
      child: const MaterialApp(
        home: GpsRecordingScreen(eventId: _evId),
      ),
    ));

    // Alcuni pump: risolvono myPilotStatusProvider (non-loading), eseguono
    // il postFrameCallback che chiama discardOrphanSession() e il
    // conseguente rebuild dopo notifyListeners().
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('FINE GARA'), findsNothing,
        reason: 'una sessione orfana non deve mai rendere raggiungibile '
            'il pulsante di conclusione gara');
    expect(find.text('START'), findsOneWidget,
        reason: 'dopo lo scarto della sessione orfana deve tornare la '
            'vista pre-partenza');
  });
}
