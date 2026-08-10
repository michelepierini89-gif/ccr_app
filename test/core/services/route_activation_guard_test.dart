/// Percorso alternativo (10/08/2026, Parte 3) — verifica il vincolo di
/// sicurezza che blocca il cambio di percorso attivo quando esiste già
/// tracking con registrazione avviata per l'evento.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/services/firestore_service.dart';

void main() {
  test('hasAnyTrackingData: false su un evento senza alcun pilota partito',
      () async {
    final fake = FakeFirebaseFirestore();
    final svc = FirestoreService(firestore: fake);
    expect(await svc.hasAnyTrackingData('evt-nuovo'), false);
  });

  test(
      'hasAnyTrackingData: true appena esiste un documento tracking/pilots '
      '(scritto da GpsService.startRecording via setRaceStatus prima di '
      'qualunque fix GPS) — il cambio percorso deve essere bloccato da qui',
      () async {
    final fake = FakeFirebaseFirestore();
    final svc = FirestoreService(firestore: fake);

    await svc.setRaceStatus('evt-1', 'pilot-1', 'racing',
        routeVariantId: 'A');

    expect(await svc.hasAnyTrackingData('evt-1'), true);
  });

  test('hasAnyTrackingData resta false per un evento diverso da quello '
      'dove un pilota ha effettivamente iniziato', () async {
    final fake = FakeFirebaseFirestore();
    final svc = FirestoreService(firestore: fake);

    await svc.setRaceStatus('evt-1', 'pilot-1', 'racing',
        routeVariantId: 'A');

    expect(await svc.hasAnyTrackingData('evt-2'), false);
  });
}
