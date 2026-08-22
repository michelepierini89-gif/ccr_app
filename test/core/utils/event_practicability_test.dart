/// Test per [isEventPracticable] (Step 51) — bug "evento risulta chiuso al
/// pilota ma aperto all'admin": per un allenamento `data` è solo il giorno
/// di apertura, non di svolgimento, quindi una data passata NON deve mai
/// chiuderlo — solo `EventStatus.archiviata` (decisione esplicita
/// dell'admin) lo fa. Per una gara vale l'opposto: `data` è il giorno di
/// svolgimento, oltre il quale è conclusa indipendentemente dallo stato.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/utils/event_practicability.dart';

void main() {
  EventModel baseEvent({
    required EventType tipoEvento,
    required DateTime data,
    EventStatus stato = EventStatus.aperto,
  }) =>
      EventModel(
        id: 'ev1',
        nome: 'Evento test',
        luogo: 'Test',
        data: data,
        descrizione: '',
        stato: stato,
        tipoEvento: tipoEvento,
        createdBy: 'admin',
        createdAt: DateTime(2026, 1, 1),
        specialiRouteA: const [],
      );

  final yesterday = DateTime.now().subtract(const Duration(days: 5));
  final tomorrow = DateTime.now().add(const Duration(days: 5));

  test('allenamento con data passata resta praticabile finché non viene chiuso', () {
    final event = baseEvent(tipoEvento: EventType.allenamento, data: yesterday);
    expect(isEventPracticable(event), isTrue);
  });

  test('allenamento chiuso dall\'admin (archiviata) NON è più praticabile, '
      'anche con data futura', () {
    final event = baseEvent(
      tipoEvento: EventType.allenamento,
      data: tomorrow,
      stato: EventStatus.archiviata,
    );
    expect(isEventPracticable(event), isFalse);
  });

  test('gara con data passata NON è più praticabile', () {
    final event = baseEvent(tipoEvento: EventType.gara, data: yesterday);
    expect(isEventPracticable(event), isFalse);
  });

  test('gara con data futura resta praticabile', () {
    final event = baseEvent(tipoEvento: EventType.gara, data: tomorrow);
    expect(isEventPracticable(event), isTrue);
  });
}
