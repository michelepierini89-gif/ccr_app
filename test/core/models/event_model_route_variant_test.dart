/// Percorso alternativo (10/08/2026) — test di retrocompatibilità e dei
/// getter `active*` di EventModel.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/event_model.dart';
import 'package:ccr_app/core/models/route_variant_model.dart';
import 'package:ccr_app/core/models/waypoint_model.dart';
import 'package:ccr_app/core/models/special_model.dart';

SpecialModel _special(String id, {int ordine = 0}) => SpecialModel(
      id: id,
      nome: 'PS $id',
      colorIndex: 0,
      ordine: ordine,
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
  group('Retrocompatibilità — evento senza variante B su Firestore', () {
    test(
        'fromFirestore su un documento nel VECCHIO formato (senza routeB, '
        'activeRouteId, routeALabel) si comporta esattamente come prima',
        () async {
      final fake = FakeFirebaseFirestore();
      // Documento con le sole chiavi che esistevano PRIMA di questo fix —
      // nessun campo relativo al percorso alternativo, come un evento
      // reale già su Firestore prima di questo deploy.
      await fake.collection('events').doc('evt-old').set({
        'nome': 'Gara Storica',
        'luogo': 'Rimini',
        'data': DateTime(2026, 5, 1),
        'descrizione': '',
        'trackUrl': 'https://example.com/track.gpx',
        'speciali': [_special('ps1').toMap()],
        'stato': 'aperto',
        'createdBy': 'uid1',
        'createdAt': DateTime(2026, 1, 1),
        'fuelPoint': null,
        'dangerPoints': <Map<String, dynamic>>[],
        'speedZones': <Map<String, dynamic>>[],
      });

      final doc = await fake.collection('events').doc('evt-old').get();
      final event = EventModel.fromFirestore(doc);

      expect(event.activeRouteId, 'A');
      expect(event.isRouteBActive, false);
      expect(event.routeB, isNull);
      expect(event.labelRouteA, 'Percorso principale');
      expect(event.routeChangeLog, isEmpty);
      expect(event.lastRouteChangeAt, isNull);

      // I getter active* restituiscono esattamente i dati RouteA, come si
      // comportavano i vecchi campi diretti prima del fix.
      expect(event.activeTrackUrl, event.trackUrlRouteA);
      expect(event.activeTrackUrl, 'https://example.com/track.gpx');
      expect(event.activeSpeciali, event.specialiRouteA);
      expect(event.activeSpeciali.length, 1);
      expect(event.activeSpeciali.first.id, 'ps1');
      expect(event.activeDangerPoints, isEmpty);
      expect(event.activeSpeedZones, isEmpty);
      expect(event.activeFuelPoint, isNull);
    });

    test('toFirestore di un evento senza routeB scrive le chiavi RouteA '
        'esattamente come i vecchi campi diretti (nessuna migrazione dati)',
        () {
      final event = EventModel(
        id: 'evt',
        nome: 'Test',
        luogo: 'Test',
        data: DateTime(2026, 1, 1),
        descrizione: '',
        specialiRouteA: [_special('ps1')],
        stato: EventStatus.aperto,
        createdBy: 'uid',
        createdAt: DateTime(2026, 1, 1),
      );
      final map = event.toFirestore();
      expect(map['speciali'], isA<List>());
      expect(map['routeB'], isNull);
      expect(map['activeRouteId'], 'A');
      expect(map['routeALabel'], 'Percorso principale');
    });
  });

  group('Getter active* — risolvono sempre la variante ATTIVA', () {
    late EventModel eventA;
    late EventModel eventB;

    setUp(() {
      final routeB = RouteVariantModel(
        id: 'B',
        label: 'Percorso maltempo',
        trackUrl: 'https://example.com/route-b.gpx',
        speciali: [_special('ps-b')],
        dangerPoints: [
          DangerPointModel(
              id: 'dp1',
              latitude: 43.2,
              longitude: 12.2,
              createdAt: DateTime(2026, 1, 1),
              comment: 'attenzione')
        ],
      );
      final base = EventModel(
        id: 'evt',
        nome: 'Test',
        luogo: 'Test',
        data: DateTime(2026, 1, 1),
        descrizione: '',
        trackUrlRouteA: 'https://example.com/route-a.gpx',
        specialiRouteA: [_special('ps-a')],
        stato: EventStatus.aperto,
        createdBy: 'uid',
        createdAt: DateTime(2026, 1, 1),
        routeB: routeB,
      );
      eventA = base.copyWith(activeRouteId: 'A');
      eventB = base.copyWith(activeRouteId: 'B');
    });

    test('activeRouteId=A → i getter risolvono sulla variante A', () {
      expect(eventA.isRouteBActive, false);
      expect(eventA.activeSpeciali.single.id, 'ps-a');
      expect(eventA.activeTrackUrl, 'https://example.com/route-a.gpx');
      expect(eventA.activeDangerPoints, isEmpty);
    });

    test('activeRouteId=B → i getter risolvono sulla variante B', () {
      expect(eventB.isRouteBActive, true);
      expect(eventB.activeSpeciali.single.id, 'ps-b');
      expect(eventB.activeTrackUrl, 'https://example.com/route-b.gpx');
      expect(eventB.activeDangerPoints.length, 1);
      expect(eventB.activeLabel, 'Percorso maltempo');
    });

    test('activeRouteId=B ma routeB nullo (cancellato) ricade su A', () {
      final broken = eventB.copyWith(clearRouteB: true);
      expect(broken.isRouteBActive, false);
      expect(broken.activeSpeciali.single.id, 'ps-a');
    });
  });
}
