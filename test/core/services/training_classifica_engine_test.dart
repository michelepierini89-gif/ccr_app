/// Test per [TrainingClassificaEngine] (Step 47, Parte 2C; sorgente dati
/// riscritta Step 51) — regole diverse dalla gara: nessun tempo forfettario
/// per le PS non completate (semplicemente non concorrono), nessuna
/// penalità per squadra incompleta, il tempo di squadra per PS è il
/// MIGLIOR tempo fra tutti i tentativi completati di tutti i membri.
/// Dallo Step 51 il motore legge [TrainingResultModel] (il riepilogo
/// pubblico già calcolato alla chiusura del tentativo), non più passaggi
/// grezzi — vedi `firestore_service_test.dart`/`FirestoreService.
/// publishTrainingResult` per il calcolo a monte.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/models/training_result_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/services/training_classifica_engine.dart';

void main() {
  final ps1 = SpecialModel(
    id: 'ps1',
    nome: 'PS1',
    colorIndex: 0,
    ordine: 0,
    waypointInizio: const WaypointModel(
        id: 'ps1-in', nome: 'Inizio PS1', lat: 43.9, lng: 12.9, type: WaypointType.inizio),
    waypointFine: const WaypointModel(
        id: 'ps1-fine', nome: 'Fine PS1', lat: 43.91, lng: 12.91, type: WaypointType.fine),
  );

  final event = EventModel(
    id: 'ev1',
    nome: 'Allenamento test',
    luogo: 'Test',
    data: DateTime(2026, 1, 1),
    descrizione: '',
    stato: EventStatus.aperto,
    tipoEvento: EventType.allenamento,
    createdBy: 'admin',
    createdAt: DateTime(2026, 1, 1),
    specialiRouteA: [ps1],
  );

  final registrations = [
    RegistrationModel(
      userId: 'pilotaA',
      eventId: 'ev1',
      nome: 'Mario',
      cognome: 'Rossi',
      stato: RegistrationStatus.approvato,
      squadraId: 'squadra1',
      createdAt: DateTime(2026, 1, 1),
    ),
    RegistrationModel(
      userId: 'pilotaB',
      eventId: 'ev1',
      nome: 'Luigi',
      cognome: 'Verdi',
      stato: RegistrationStatus.approvato,
      squadraId: 'squadra1',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  const teams = [
    TeamModel(
        id: 'squadra1',
        nome: 'Squadra Test',
        membriIds: ['pilotaA', 'pilotaB'],
        createdBy: 'pilotaA',
        eventId: 'ev1'),
  ];

  const userNames = {'pilotaA': 'Mario Rossi', 'pilotaB': 'Luigi Verdi'};

  TrainingSpecialSummary ps1Summary(Duration tempo,
          {bool skipped = false, bool notDetected = false, String? timingError}) =>
      TrainingSpecialSummary(
        specialeId: 'ps1',
        specialeNome: 'PS1',
        ordine: 0,
        tempo: tempo,
        controlPointsOk: true,
        skipped: skipped,
        notDetected: notDetected,
        timingError: timingError,
      );

  TrainingResultModel result(
    String userId,
    String attemptId,
    int attemptNumber,
    List<TrainingSpecialSummary> speciali,
  ) =>
      TrainingResultModel(
        attemptId: attemptId,
        userId: userId,
        attemptNumber: attemptNumber,
        routeVariantId: null,
        completedAt: DateTime(2026, 1, 1, 9, 5),
        speciali: speciali,
      );

  test('il tempo di squadra è il MIGLIORE fra tutti i tentativi di tutti i membri', () {
    // Tentativo 1 (pilotaA): PS1 in 60s. Tentativo 1 (pilotaB): PS1 in
    // 45s — migliore.
    final results = [
      result('pilotaA', 'att1', 1, [ps1Summary(const Duration(seconds: 60))]),
      result('pilotaB', 'att2', 1, [ps1Summary(const Duration(seconds: 45))]),
    ];

    final out = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      results: results,
      userNames: userNames,
    );

    expect(out, hasLength(1));
    final entry = out.first;
    expect(entry.specialiCompletati, 1);
    final best = entry.bestBySpecialId['ps1']!;
    expect(best.tempo.tempo, const Duration(seconds: 45));
    expect(best.userId, 'pilotaB');
    expect(best.attemptNumber, 1);
  });

  test('un pilota da solo può migliorare il record della squadra su una PS', () {
    final results = [
      result('pilotaA', 'att1', 1, [ps1Summary(const Duration(seconds: 50))]),
    ];

    final out = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      results: results,
      userNames: userNames,
    );

    expect(out, hasLength(1));
    // Nessuna penalità per squadra incompleta: il tempo è netto.
    expect(out.first.tempoTotale, const Duration(seconds: 50));
  });

  test('una PS non completata (nessun tentativo valido) semplicemente non concorre — '
      'nessun tempo forfettario', () {
    final ps2 = SpecialModel(
      id: 'ps2',
      nome: 'PS2',
      colorIndex: 1,
      ordine: 1,
      waypointInizio: const WaypointModel(
          id: 'ps2-in', nome: 'Inizio PS2', lat: 43.9, lng: 12.9, type: WaypointType.inizio),
      waypointFine: const WaypointModel(
          id: 'ps2-fine', nome: 'Fine PS2', lat: 43.91, lng: 12.91, type: WaypointType.fine),
    );
    final eventWithPs2 = event.copyWith(specialiRouteA: [ps1, ps2]);

    final results = [
      // Solo PS1 completata in questo tentativo — PS2 mai tentata.
      result('pilotaA', 'att1', 1, [ps1Summary(const Duration(seconds: 50))]),
    ];

    final out = TrainingClassificaEngine.compute(
      event: eventWithPs2,
      registrations: registrations,
      teams: teams,
      results: results,
      userNames: userNames,
    );

    final entry = out.first;
    expect(entry.specialiCompletati, 1);
    expect(entry.totaleSpeciali, 2);
    expect(entry.bestBySpecialId.containsKey('ps2'), isFalse);
    // Nessun tempo forfettario aggiunto: tempoTotale è solo la PS1.
    expect(entry.tempoTotale, const Duration(seconds: 50));
  });

  test('una PS saltata volontariamente non concorre (non conta come tempo pessimo)', () {
    final results = [
      result('pilotaA', 'att1', 1, [
        ps1Summary(const Duration(seconds: 5),
            skipped: true, timingError: 'speciale_saltata'),
      ]),
    ];

    final out = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      results: results,
      userNames: userNames,
    );

    expect(out.first.specialiCompletati, 0);
    expect(out.first.bestBySpecialId, isEmpty);
  });
}
