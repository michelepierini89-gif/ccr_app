/// Test di regressione (Fix 3, 09/08/2026) — quando una PS non ha un dato
/// REALE (porta o raggio) per inizio o fine, ma solo una stima a tempo
/// fisso di GpsService (timingMethod=='forfait'), ClassificaEngine non deve
/// più interpolare un tempo dalla differenza tra i due timestamp (che prima
/// del fix produceva tempi assurdi tipo "73:37"): deve applicare la stessa
/// penalità forfettaria del salto volontario esplicito (peggior tempo tra i
/// piloti sulla PS + 30 minuti), segnalata con [SpecialTempo.notDetected].
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/classifica_model.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/registration_model.dart';
import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/team_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/services/classifica_engine.dart';

WaypointModel _wp(String id, WaypointType type) =>
    WaypointModel(id: id, nome: id, lat: 0, lng: 0, type: type);

RegistrationModel _reg(String userId) => RegistrationModel(
      userId: userId,
      eventId: 'evt',
      nome: userId,
      cognome: 'Pilota',
      stato: RegistrationStatus.approvato,
      createdAt: DateTime(2026, 1, 1),
    );

WaypointPassageRecord _passage(
  String userId,
  String waypointId,
  DateTime ts, {
  String timingMethod = 'gate',
  String? timingError,
}) =>
    WaypointPassageRecord(
      id: '$userId-$waypointId-${ts.millisecondsSinceEpoch}',
      userId: userId,
      waypointId: waypointId,
      waypointNome: waypointId,
      timestamp: ts,
      timingMethod: timingMethod,
      timingError: timingError,
    );

void main() {
  final ps1Inizio = _wp('ps1_inizio', WaypointType.inizio);
  final ps1Fine = _wp('ps1_fine', WaypointType.fine);
  final ps2Inizio = _wp('ps2_inizio', WaypointType.inizio);
  final ps2Fine = _wp('ps2_fine', WaypointType.fine);

  final ps1 = SpecialModel(
      id: 'ps1',
      nome: 'PS1',
      colorIndex: 0,
      waypointInizio: ps1Inizio,
      waypointFine: ps1Fine,
      ordine: 0);
  final ps2 = SpecialModel(
      id: 'ps2',
      nome: 'PS2',
      colorIndex: 1,
      waypointInizio: ps2Inizio,
      waypointFine: ps2Fine,
      ordine: 1);

  final baseStart = DateTime(2026, 8, 9, 9, 0, 0);

  EventModel buildEvent({int maxRaceTimeMinutes = 270}) => EventModel(
        id: 'evt',
        nome: 'Test',
        luogo: 'Test',
        data: baseStart,
        descrizione: '',
        speciali: [ps1, ps2],
        stato: EventStatus.inCorso,
        createdBy: 'admin',
        createdAt: baseStart,
        maxRaceTimeMinutes: maxRaceTimeMinutes,
      );

  ClassificaEntry entryFor(List<ClassificaEntry> entries, String userId) =>
      entries.firstWhere((e) => e.entryId == userId);

  test(
      'PS con fine timingMethod=forfait: nessun tempo interpolato, applicato '
      'il forfait (peggior tempo reale + 30 min), notDetected=true', () {
    // Pilota A: PS1 regolare (10 minuti), PS2 completata regolarmente da
    // nessun altro — quindi PS2 di A deve ricadere sul default (nessun
    // tempo reale per PS2 tra i piloti).
    // Pilota B: PS1 completata in 12 minuti (sarà il "peggior tempo reale"
    // per PS1), PS2 con fine a timingMethod='forfait' (nessun dato GPS):
    // il tempo PS2 di B non deve essere la differenza dei timestamp
    // (che sarebbe assurda, ore), ma il forfait.
    final passages = [
      _passage('A', 'ps1_inizio', baseStart),
      _passage('A', 'ps1_fine', baseStart.add(const Duration(minutes: 10))),
      _passage('B', 'ps1_inizio', baseStart),
      _passage('B', 'ps1_fine', baseStart.add(const Duration(minutes: 12))),
      _passage('B', 'ps2_inizio',
          baseStart.add(const Duration(minutes: 20))),
      // Fine "forfait": nessun dato GPS reale, GpsService ha comunque
      // scritto un passaggio con una stima a ore di distanza.
      _passage('B', 'ps2_fine',
          baseStart.add(const Duration(hours: 4, minutes: 13, seconds: 37)),
          timingMethod: 'forfait', timingError: 'chiusa_da_FINE_GARA'),
    ];

    final entries = ClassificaEngine.compute(
      event: buildEvent(),
      passages: passages,
      registrations: [_reg('A'), _reg('B')],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
    );

    final b = entryFor(entries, 'B');
    final ps2B = b.specialiCompletati.firstWhere((s) => s.specialeId == 'ps2');

    expect(ps2B.notDetected, isTrue);
    expect(ps2B.skipped, isFalse);
    // MAI la differenza letterale dei timestamp (~4h13m37s tra ps2_inizio
    // e la fine forfait): il forfait qui è il default (nessun pilota ha un
    // tempo REALE per PS2) = maxRaceTimeMinutes/2 specialità + 30 min =
    // 135min + 30min = 165 min — un valore diverso e non casuale, non la
    // differenza dei timestamp forfait/reali che sarebbe stata ~4h13m37s.
    expect(ps2B.tempo, isNot(const Duration(hours: 4, minutes: 13, seconds: 37)));
    expect(ps2B.tempo, const Duration(minutes: 165));
  });

  test(
      'quando un altro pilota completa la PS con un tempo reale, il '
      'forfait usa quel tempo (peggiore) + 30 min, non più il default', () {
    final passages = [
      _passage('A', 'ps1_inizio', baseStart),
      _passage('A', 'ps1_fine', baseStart.add(const Duration(minutes: 10))),
      // Pilota A completa anche PS2 regolarmente in 15 minuti: diventa la
      // base per il forfait di chiunque altro non abbia un dato reale.
      _passage('A', 'ps2_inizio',
          baseStart.add(const Duration(minutes: 20))),
      _passage('A', 'ps2_fine',
          baseStart.add(const Duration(minutes: 35))),
      _passage('B', 'ps1_inizio', baseStart),
      _passage('B', 'ps1_fine', baseStart.add(const Duration(minutes: 12))),
      _passage('B', 'ps2_inizio',
          baseStart.add(const Duration(minutes: 20))),
      _passage('B', 'ps2_fine',
          baseStart.add(const Duration(hours: 4)),
          timingMethod: 'forfait', timingError: 'chiusa_da_FINE_GARA'),
    ];

    final entries = ClassificaEngine.compute(
      event: buildEvent(),
      passages: passages,
      registrations: [_reg('A'), _reg('B')],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
    );

    final b = entryFor(entries, 'B');
    final ps2B = b.specialiCompletati.firstWhere((s) => s.specialeId == 'ps2');
    expect(ps2B.notDetected, isTrue);
    // peggior tempo reale (15 min, A) + 30 min = 45 min.
    expect(ps2B.tempo, const Duration(minutes: 45));
  });

  test('salto volontario e speciale non rilevata NON si influenzano a '
      'vicenda nel calcolo del "peggior tempo"', () {
    final passages = [
      _passage('A', 'ps1_inizio', baseStart),
      _passage('A', 'ps1_fine', baseStart.add(const Duration(minutes: 10)),
          timingError: 'speciale_saltata'),
      _passage('B', 'ps1_inizio', baseStart),
      _passage('B', 'ps1_fine', baseStart.add(const Duration(hours: 2)),
          timingMethod: 'forfait', timingError: 'chiusa_da_FINE_GARA'),
      _passage('A', 'ps2_inizio',
          baseStart.add(const Duration(minutes: 20))),
      _passage('A', 'ps2_fine',
          baseStart.add(const Duration(minutes: 30))),
      _passage('B', 'ps2_inizio',
          baseStart.add(const Duration(minutes: 20))),
      _passage('B', 'ps2_fine',
          baseStart.add(const Duration(minutes: 40))),
    ];

    final entries = ClassificaEngine.compute(
      event: buildEvent(),
      passages: passages,
      registrations: [_reg('A'), _reg('B')],
      teams: const <TeamModel>[],
      withdrawals: const {},
      liveTracking: const [],
    );

    final a = entryFor(entries, 'A');
    final b = entryFor(entries, 'B');
    final ps1A = a.specialiCompletati.firstWhere((s) => s.specialeId == 'ps1');
    final ps1B = b.specialiCompletati.firstWhere((s) => s.specialeId == 'ps1');

    expect(ps1A.skipped, isTrue);
    expect(ps1A.notDetected, isFalse);
    expect(ps1B.notDetected, isTrue);
    expect(ps1B.skipped, isFalse);
    // Nessun pilota ha un tempo reale per PS1 (A saltata, B non rilevata):
    // entrambi ricadono sul default (maxRaceTimeMinutes/2 + 30min = 165min).
    expect(ps1A.tempo, const Duration(minutes: 165));
    expect(ps1B.tempo, const Duration(minutes: 165));
  });
}
