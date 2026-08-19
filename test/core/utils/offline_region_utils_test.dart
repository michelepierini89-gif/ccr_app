/// Step 49, Parte 3 — la copertura del download offline per ENTRAMBE le
/// varianti di percorso (non solo quella attiva) era già stata scritta il
/// 10/08 ("percorso alternativo, Parte 4"), ma con la cache che fino allo
/// Step 49 non veniva mai letta a runtime, questa logica non è mai stata
/// verificata sul campo. Verifica diretta, senza montare alcun widget:
/// estratta in `OfflineRegionUtils.eventBoundingBox` proprio per questo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/route_variant_model.dart';
import 'package:ccr_app/core/models/special_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/utils/offline_region_utils.dart';

SpecialModel _special(String id, double lat, double lng) => SpecialModel(
      id: id,
      nome: 'PS $id',
      colorIndex: 0,
      ordine: 1,
      waypointInizio:
          WaypointModel(id: '$id-start', nome: 'Start', lat: lat, lng: lng, type: WaypointType.inizio),
      waypointFine: WaypointModel(
          id: '$id-end', nome: 'End', lat: lat + 0.01, lng: lng + 0.01, type: WaypointType.fine),
    );

EventModel _eventWithRoutes({required bool withRouteB}) => EventModel(
      id: 'ev1',
      nome: 'Rally Test',
      luogo: 'Roma',
      data: DateTime(2026, 9, 1),
      descrizione: '',
      // Percorso A: area attorno a (44.0, 10.0) — Appennino tosco-emiliano.
      specialiRouteA: [_special('A1', 44.0, 10.0)],
      routeB: withRouteB
          ? RouteVariantModel(
              id: 'B',
              label: 'Alternativo',
              // Percorso B: area distante, attorno a (45.5, 11.5) — se il
              // bbox non unisse le due varianti, questo punto resterebbe
              // fuori.
              speciali: [_special('B1', 45.5, 11.5)],
            )
          : null,
      stato: EventStatus.aperto,
      createdBy: 'uid-admin',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  test('senza percorso B, il bbox copre solo la variante A', () {
    final event = _eventWithRoutes(withRouteB: false);
    final bbox = OfflineRegionUtils.eventBoundingBox(event);
    expect(bbox, isNotNull);
    final (sw, ne) = bbox!;
    // Il punto della variante B (mai creata) NON deve essere incluso.
    expect(sw.latitude <= 45.5 && ne.latitude >= 45.5, isFalse);
  });

  test(
      'con percorso B attivo, il bbox include ENTRAMBE le varianti anche se '
      'A è quella attualmente attiva', () {
    final event = _eventWithRoutes(withRouteB: true);
    final bbox = OfflineRegionUtils.eventBoundingBox(event);
    expect(bbox, isNotNull);
    final (sw, ne) = bbox!;

    // Waypoint di A (44.0, 10.0 .. 44.01, 10.01)
    expect(sw.latitude, lessThanOrEqualTo(44.0));
    expect(sw.longitude, lessThanOrEqualTo(10.0));
    // Waypoint di B (45.5, 11.5 .. 45.51, 11.51) — la parte che dimostra
    // l'unione, non solo la variante attiva.
    expect(ne.latitude, greaterThanOrEqualTo(45.51));
    expect(ne.longitude, greaterThanOrEqualTo(11.51));
  });

  test('evento senza speciali su nessuna variante ritorna null', () {
    final event = EventModel(
      id: 'ev2',
      nome: 'Vuoto',
      luogo: 'Roma',
      data: DateTime(2026, 9, 1),
      descrizione: '',
      specialiRouteA: const [],
      stato: EventStatus.aperto,
      createdBy: 'uid-admin',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(OfflineRegionUtils.eventBoundingBox(event), isNull);
  });
}
