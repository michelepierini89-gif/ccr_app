/// Fix (bug test 18/08, "Carring CLO 3") — replica esatta del documento
/// reale di un pilota (Claudia La Rosa, evento "Carring CLO 3") che ha
/// abbattuto la schermata Live admin: `TypeError: null: type 'minified:GI'
/// is not a subtype of type 'num'`. Il documento tracking di quel pilota
/// contiene SOLO raceStatus/finishedAt/routeVariantId — nessun fix GPS è
/// mai stato accettato prima che la gara risultasse conclusa (vedi
/// race_session_guard.dart), quindi `lat`/`lng` sono del tutto assenti.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/models/gps_point_model.dart';

void main() {
  test(
      'fromFirestore su un documento senza lat/lng (nessun fix GPS mai '
      'accettato) non lancia e marca hasPosition=false', () async {
    final fake = FakeFirebaseFirestore();
    final ref = fake.collection('tracking').doc('evt').collection('pilots').doc('pilot-1');
    await ref.set({
      'raceStatus': 'finished',
      'routeVariantId': 'A',
    });
    final doc = await ref.get();

    final point = GpsPointModel.fromFirestore(doc, 'evt');

    expect(point.hasPosition, isFalse);
    expect(point.lat, 0.0);
    expect(point.lng, 0.0);
    expect(point.raceStatus, 'finished');
  });

  test('fromFirestore su un documento con lat/lng validi marca hasPosition=true',
      () async {
    final fake = FakeFirebaseFirestore();
    final ref = fake.collection('tracking').doc('evt').collection('pilots').doc('pilot-2');
    await ref.set({
      'lat': 43.9,
      'lng': 12.9,
      'accuracy': 5.0,
      'raceStatus': 'racing',
    });
    final doc = await ref.get();

    final point = GpsPointModel.fromFirestore(doc, 'evt');

    expect(point.hasPosition, isTrue);
    expect(point.lat, 43.9);
    expect(point.lng, 12.9);
  });
}
