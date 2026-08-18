/// Test per [TrainingClassificaEngine] (Step 47, Parte 2C) — regole
/// diverse dalla gara: nessun tempo forfettario per le PS non completate
/// (semplicemente non concorrono), nessuna penalità per squadra
/// incompleta, il tempo di squadra per PS è il MIGLIOR tempo fra tutti i
/// tentativi completati di tutti i membri.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/attempt_model.dart';
import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
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

  WaypointPassageRecord passage(String userId, String wpId, DateTime ts) =>
      WaypointPassageRecord(
          id: '$userId-$wpId-${ts.millisecondsSinceEpoch}',
          userId: userId,
          waypointId: wpId,
          waypointNome: wpId,
          timestamp: ts);

  test('il tempo di squadra è il MIGLIORE fra tutti i tentativi di tutti i membri', () {
    final base = DateTime(2026, 1, 1, 9, 0, 0);
    // Tentativo 1 (pilotaA): PS1 in 60s.
    final attempt1 = AttemptModel(
        id: 'att1',
        eventId: 'ev1',
        userId: 'pilotaA',
        attemptNumber: 1,
        status: AttemptStatus.completed,
        startedAt: base);
    // Tentativo 1 (pilotaB): PS1 in 45s — migliore.
    final attempt2 = AttemptModel(
        id: 'att2',
        eventId: 'ev1',
        userId: 'pilotaB',
        attemptNumber: 1,
        status: AttemptStatus.completed,
        startedAt: base);

    final passagesByAttemptId = {
      'att1': [
        passage('pilotaA', 'ps1-in', base),
        passage('pilotaA', 'ps1-fine', base.add(const Duration(seconds: 60))),
      ],
      'att2': [
        passage('pilotaB', 'ps1-in', base),
        passage('pilotaB', 'ps1-fine', base.add(const Duration(seconds: 45))),
      ],
    };

    final result = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      completedAttempts: [attempt1, attempt2],
      passagesByAttemptId: passagesByAttemptId,
      speedViolationsByAttemptId: const {},
      userNames: userNames,
    );

    expect(result, hasLength(1));
    final entry = result.first;
    expect(entry.specialiCompletati, 1);
    final best = entry.bestBySpecialId['ps1']!;
    expect(best.tempo.tempo, const Duration(seconds: 45));
    expect(best.userId, 'pilotaB');
    expect(best.attemptNumber, 1);
  });

  test('un pilota da solo può migliorare il record della squadra su una PS', () {
    final base = DateTime(2026, 1, 1, 9, 0, 0);
    // Solo pilotaA registra un tentativo — nessun compagno necessario.
    final attempt = AttemptModel(
        id: 'att1',
        eventId: 'ev1',
        userId: 'pilotaA',
        attemptNumber: 1,
        status: AttemptStatus.completed,
        startedAt: base);

    final result = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      completedAttempts: [attempt],
      passagesByAttemptId: {
        'att1': [
          passage('pilotaA', 'ps1-in', base),
          passage('pilotaA', 'ps1-fine', base.add(const Duration(seconds: 50))),
        ],
      },
      speedViolationsByAttemptId: const {},
      userNames: userNames,
    );

    expect(result, hasLength(1));
    // Nessuna penalità per squadra incompleta: il tempo è netto.
    expect(result.first.tempoTotale, const Duration(seconds: 50));
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

    final base = DateTime(2026, 1, 1, 9, 0, 0);
    final attempt = AttemptModel(
        id: 'att1',
        eventId: 'ev1',
        userId: 'pilotaA',
        attemptNumber: 1,
        status: AttemptStatus.completed,
        startedAt: base);

    final result = TrainingClassificaEngine.compute(
      event: eventWithPs2,
      registrations: registrations,
      teams: teams,
      completedAttempts: [attempt],
      // Solo PS1 completata in questo tentativo — PS2 mai tentata.
      passagesByAttemptId: {
        'att1': [
          passage('pilotaA', 'ps1-in', base),
          passage('pilotaA', 'ps1-fine', base.add(const Duration(seconds: 50))),
        ],
      },
      speedViolationsByAttemptId: const {},
      userNames: userNames,
    );

    final entry = result.first;
    expect(entry.specialiCompletati, 1);
    expect(entry.totaleSpeciali, 2);
    expect(entry.bestBySpecialId.containsKey('ps2'), isFalse);
    // Nessun tempo forfettario aggiunto: tempoTotale è solo la PS1.
    expect(entry.tempoTotale, const Duration(seconds: 50));
  });

  test('una PS saltata volontariamente non concorre (non conta come tempo pessimo)', () {
    final base = DateTime(2026, 1, 1, 9, 0, 0);
    final attempt = AttemptModel(
        id: 'att1',
        eventId: 'ev1',
        userId: 'pilotaA',
        attemptNumber: 1,
        status: AttemptStatus.completed,
        startedAt: base);

    final result = TrainingClassificaEngine.compute(
      event: event,
      registrations: registrations,
      teams: teams,
      completedAttempts: [attempt],
      passagesByAttemptId: {
        'att1': [
          WaypointPassageRecord(
              id: 'p1',
              userId: 'pilotaA',
              waypointId: 'ps1-in',
              waypointNome: 'Inizio PS1',
              timestamp: base,
              timingError: 'speciale_saltata',
              timingMethod: 'forfait'),
          WaypointPassageRecord(
              id: 'p2',
              userId: 'pilotaA',
              waypointId: 'ps1-fine',
              waypointNome: 'Fine PS1',
              timestamp: base.add(const Duration(seconds: 5)),
              timingError: 'speciale_saltata',
              timingMethod: 'forfait'),
        ],
      },
      speedViolationsByAttemptId: const {},
      userNames: userNames,
    );

    expect(result.first.specialiCompletati, 0);
    expect(result.first.bestBySpecialId, isEmpty);
  });
}
