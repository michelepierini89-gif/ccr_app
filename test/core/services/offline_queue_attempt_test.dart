/// Rifiniture Step 47 — la coda offline (`OfflineQueueService`) ora copre
/// anche i passaggi di un tentativo di allenamento, non solo quelli di
/// gara: prima, un `recordAttemptWaypointPassage` fallito (tipicamente per
/// mancanza di copertura, lo scenario più probabile in allenamento) veniva
/// scartato senza alcun fallback (vedi `GpsService._persistPassage`), a
/// differenza del ramo gara che già rimetteva in coda. Verifica che un
/// passaggio di tentativo in coda venga riprodotto sulla sottocollezione
/// annidata dell'attempt (non su quella piatta di gara) e che il
/// comportamento esistente per la gara resti invariato.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/offline_queue_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late FirestoreService firestore;
  late OfflineQueueService queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeDb = FakeFirebaseFirestore();
    firestore = FirestoreService(firestore: fakeDb);
    queue = OfflineQueueService(prefs);
  });

  test(
      'passaggio di TENTATIVO in coda viene riprodotto sulla sottocollezione '
      'attempts/{attemptId}/passages, non sulla collezione piatta di gara',
      () async {
    await queue.queuePassage(
      eventId: 'ev1',
      userId: 'u1',
      waypointId: 'wp-ps1-start',
      waypointNome: 'PS1 Start',
      timestamp: DateTime(2026, 8, 19, 10, 0),
      attemptId: 'att1',
    );
    expect(queue.pendingPassagesCount, 1);

    final synced = await queue.syncPending(firestore);
    expect(synced, 1);
    expect(queue.pendingPassagesCount, 0);

    final attemptPassages = await fakeDb
        .collection('tracking')
        .doc('ev1')
        .collection('pilots')
        .doc('u1')
        .collection('attempts')
        .doc('att1')
        .collection('passages')
        .get();
    expect(attemptPassages.docs, hasLength(1));
    expect(attemptPassages.docs.first.data()['waypointId'], 'wp-ps1-start');

    final racePassages =
        await fakeDb.collection('tracking').doc('ev1').collection('passages').get();
    expect(racePassages.docs, isEmpty);
  });

  test(
      'passaggio di GARA (nessun attemptId) resta sulla collezione piatta di '
      'gara, comportamento invariato', () async {
    await queue.queuePassage(
      eventId: 'ev2',
      userId: 'u2',
      waypointId: 'wp-ps1-start',
      waypointNome: 'PS1 Start',
      timestamp: DateTime(2026, 8, 19, 10, 0),
    );

    final synced = await queue.syncPending(firestore);
    expect(synced, 1);

    final racePassages =
        await fakeDb.collection('tracking').doc('ev2').collection('passages').get();
    expect(racePassages.docs, hasLength(1));
  });
}
