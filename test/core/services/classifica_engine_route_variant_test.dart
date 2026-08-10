/// Percorso alternativo (10/08/2026, Parte 5) — punto critico: il calcolo
/// tempi deve usare la variante con cui il pilota ha REALMENTE corso
/// (routeVariantByUserId, letto dal suo tracking), mai
/// `event.activeRouteId`. Verifica che un cambio di percorso attivo DOPO
/// la gara non alteri il risultato di chi ha già corso.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/route_variant_model.dart';
import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/services/classifica_engine.dart';

SpecialModel _special(String id) => SpecialModel(
      id: id,
      nome: 'PS $id',
      colorIndex: 0,
      ordine: 0,
      waypointInizio: WaypointModel(
          id: '${id}_start',
          nome: 'inizio',
          lat: 43.0,
          lng: 12.0,
          type: WaypointType.inizio),
      waypointFine: WaypointModel(
          id: '${id}_end',
          nome: 'fine',
          lat: 43.1,
          lng: 12.1,
          type: WaypointType.fine),
    );

void main() {
  final start = DateTime(2026, 8, 10, 9, 0, 0);

  // L'evento ha DUE speciali fisicamente diverse: 'ps-a' sul percorso
  // principale, 'ps-b' su quello alternativo — id diversi, come avviene
  // quando la variante B non è una copia di A ma un percorso realmente
  // diverso (es. accorciato per maltempo).
  final event = EventModel(
    id: 'evt',
    nome: 'Test',
    luogo: 'Test',
    data: start,
    descrizione: '',
    specialiRouteA: [_special('ps-a')],
    routeB: RouteVariantModel(
      id: 'B',
      label: 'Percorso maltempo',
      speciali: [_special('ps-b')],
    ),
    // L'evento ha B come variante ATTIVA in questo momento — il pilota,
    // però, ha corso PRIMA di questo cambio, su A: il suo risultato non
    // deve essere influenzato.
    activeRouteId: 'B',
    stato: EventStatus.inCorso,
    createdBy: 'admin',
    createdAt: start,
  );

  final registration = RegistrationModel(
    userId: 'pilot-1',
    eventId: 'evt',
    nome: 'Mario',
    cognome: 'Rossi',
    stato: RegistrationStatus.approvato,
    createdAt: start,
  );

  test(
      'un pilota che ha corso su A viene calcolato sulle speciali di A, '
      'anche se l\'evento ha B come variante attualmente attiva', () {
    final passages = [
      WaypointPassageRecord(
        id: '1',
        userId: 'pilot-1',
        waypointId: 'ps-a_start',
        waypointNome: 'inizio',
        timestamp: start,
      ),
      WaypointPassageRecord(
        id: '2',
        userId: 'pilot-1',
        waypointId: 'ps-a_end',
        waypointNome: 'fine',
        timestamp: start.add(const Duration(minutes: 5)),
      ),
    ];

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: [registration],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
      routeVariantByUserId: {'pilot-1': 'A'},
    );

    final entry = entries.single;
    expect(entry.routeIdUsed, 'A');
    expect(entry.mixedRouteVariants, false);
    expect(entry.totaleSpeciali, 1);
    expect(entry.specialiCompletati.single.specialeId, 'ps-a');
    expect(entry.specialiCompletati.single.tempo, const Duration(minutes: 5));
    expect(entry.hasFinished, true);
  });

  test(
      'lo stesso pilota, se registrato come "B" (ha corso dopo il cambio), '
      'viene calcolato sulle speciali di B — i passaggi su ps-a non '
      'contano per lui', () {
    final passages = [
      WaypointPassageRecord(
        id: '1',
        userId: 'pilot-1',
        waypointId: 'ps-a_start',
        waypointNome: 'inizio',
        timestamp: start,
      ),
      WaypointPassageRecord(
        id: '2',
        userId: 'pilot-1',
        waypointId: 'ps-a_end',
        waypointNome: 'fine',
        timestamp: start.add(const Duration(minutes: 5)),
      ),
    ];

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: [registration],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
      routeVariantByUserId: {'pilot-1': 'B'},
    );

    final entry = entries.single;
    expect(entry.routeIdUsed, 'B');
    expect(entry.totaleSpeciali, 1);
    // Nessun passaggio corrisponde a ps-b (i waypoint id sono ps-a_*): la
    // speciale non risulta completata, non un tempo calcolato per errore
    // dalla PS sbagliata.
    expect(entry.specialiCompletati, isEmpty);
    expect(entry.hasFinished, false);
  });

  test(
      'senza routeVariantByUserId (pilota pre-esistente al fix) ricade su '
      'A, comportamento identico a prima di questa feature', () {
    final passages = [
      WaypointPassageRecord(
        id: '1',
        userId: 'pilot-1',
        waypointId: 'ps-a_start',
        waypointNome: 'inizio',
        timestamp: start,
      ),
      WaypointPassageRecord(
        id: '2',
        userId: 'pilot-1',
        waypointId: 'ps-a_end',
        waypointNome: 'fine',
        timestamp: start.add(const Duration(minutes: 5)),
      ),
    ];

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: [registration],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
      // routeVariantByUserId omesso — default const {}.
    );

    final entry = entries.single;
    expect(entry.routeIdUsed, 'A');
    expect(entry.specialiCompletati.single.specialeId, 'ps-a');
  });
}
