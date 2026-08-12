/// Fix (10/08/2026) — Il fix del limite 1 MiB (sottocollezione a chunk,
/// `FirestoreService.saveFullPilotTrack`/`getFullPilotTrack`) era stato
/// scritto ma mai verificato end-to-end: ha già distrutto silenziosamente
/// la traccia grezza di un test reale da 100km (vedi PROGETTO_CCR.md,
/// evento "Carring Clo 2 HB" del 09/08/2026). Questo test verifica, con una
/// traccia delle stesse dimensioni di quel test (ordine di grandezza
/// 12.000-15.000 punti = 4-5 ore a 1 campione/secondo), che:
/// 1. il salvataggio vada effettivamente in chunk (non un unico documento)
/// 2. nessun chunk superi il limite Firestore di 1 MiB
/// 3. la rilettura restituisca esattamente tutti i punti, nello stesso
///    ordine e con i timestamp integri (nessuna perdita di precisione nel
///    round-trip millisecondi)
///
/// Usa `FakeFirebaseFirestore` (in-memory, nessun emulatore/rete) — non
/// applica di per sé il limite reale di 1 MiB sui documenti, per questo il
/// test lo verifica esplicitamente stimando la dimensione serializzata di
/// ogni chunk invece di fare affidamento su un errore del fake.
library;

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/constants/firebase_constants.dart';
import 'package:ccr_app/core/services/firestore_service.dart';
import 'package:ccr_app/core/services/track_smoother.dart';

const _oneMiB = 1024 * 1024;

List<RawTrackSample> _buildRealisticTrack(int count, DateTime start) {
  // Coordinate e accuracy con molti decimali (caso peggiore per la
  // dimensione serializzata) — non valori tondi che comprimerebbero meglio
  // di una traccia GPS reale.
  return List.generate(count, (i) {
    final t = i / 37.0;
    return RawTrackSample(
      lat: 43.812345678 + 0.0001 * (t % 50 - 25),
      lng: 12.712345678 - 0.0001 * ((t * 1.3) % 50 - 25),
      accuracy: 4.0 + (i % 23) * 0.417,
      timestamp: start.add(Duration(seconds: i)),
    );
  });
}

Future<int> _chunkEncodedSize(Map<String, dynamic> data) async =>
    utf8.encode(jsonEncode(data)).length;

void main() {
  const eventId = 'evt-100km-test';
  const userId = 'pilot-test';

  test(
      'traccia da 13000 punti (~3h37 a 1 campione/s, ordine di grandezza del '
      'test 100km) si salva in più chunk, nessuno sopra 1 MiB', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 9, 9, 0, 0);
    final samples = _buildRealisticTrack(13000, start);

    await service.saveFullPilotTrack(eventId, userId, samples);

    final chunksSnap = await fake
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .collection(FirebaseConstants.fullTrackChunks)
        .get();

    // 13000 campioni / 2000 per chunk (_fullTrackChunkSize) = 7 chunk.
    expect(chunksSnap.docs.length, greaterThan(1),
        reason:
            'la traccia deve finire in più documenti, non in un unico campo');

    for (final doc in chunksSnap.docs) {
      final size = await _chunkEncodedSize(doc.data());
      expect(size, lessThan(_oneMiB),
          reason: 'chunk ${doc.id}: $size byte, supera 1 MiB');
    }

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, samples.length);
    for (var i = 0; i < samples.length; i++) {
      expect(reread[i].lat, samples[i].lat, reason: 'punto $i: lat');
      expect(reread[i].lng, samples[i].lng, reason: 'punto $i: lng');
      expect(reread[i].accuracy, samples[i].accuracy,
          reason: 'punto $i: accuracy');
      expect(reread[i].timestamp, samples[i].timestamp,
          reason: 'punto $i: timestamp');
    }
  });

  test(
      'traccia estrema (18000 punti, 5h piene a 1 campione/s): nessun chunk '
      'sopra 1 MiB', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 9, 9, 0, 0);
    final samples = _buildRealisticTrack(18000, start);

    await service.saveFullPilotTrack(eventId, userId, samples);

    final chunksSnap = await fake
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .collection(FirebaseConstants.fullTrackChunks)
        .get();

    for (final doc in chunksSnap.docs) {
      final size = await _chunkEncodedSize(doc.data());
      expect(size, lessThan(_oneMiB),
          reason: 'chunk ${doc.id}: $size byte, supera 1 MiB');
    }

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, samples.length);
  });

  test(
      'un secondo salvataggio con meno campioni non lascia chunk residui '
      'più vecchi (idempotenza)', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 9, 9, 0, 0);

    await service.saveFullPilotTrack(
        eventId, userId, _buildRealisticTrack(9000, start));
    await service.saveFullPilotTrack(
        eventId, userId, _buildRealisticTrack(500, start));

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, 500);
  });

  test(
      'interruzione a metà gara (bug test 18/08): i campioni scritti coi '
      'flush incrementali restano leggibili anche senza il salvataggio '
      'finale', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 18, 7, 0, 0);
    final allSamples = _buildRealisticTrack(5000, start);

    // Come GpsRecordingScreen._startRace(): reset esplicito prima del
    // primo flush della sessione.
    await service.resetFullPilotTrackForNewSession(eventId, userId);

    // 3 flush incrementali (come il tick periodico in
    // GpsRecordingScreen._flushFullTrackIncremental), poi l'"interruzione":
    // saveFullPilotTrack (il salvataggio finale autorevole di FINE
    // GARA/RITIRO/timeout) non viene mai chiamato.
    var flushed = 0;
    for (final end in [1500, 3000, 4500]) {
      final newSamples = allSamples.sublist(flushed, end);
      await service.appendFullPilotTrackChunks(eventId, userId, newSamples,
          startIndex: flushed);
      flushed = end;
    }

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, 4500,
        reason: 'i campioni fino all\'ultimo flush riuscito devono essere '
            'leggibili anche se la gara si interrompe prima del '
            'salvataggio finale');
    for (var i = 0; i < reread.length; i++) {
      expect(reread[i].lat, allSamples[i].lat, reason: 'punto $i: lat');
      expect(reread[i].lng, allSamples[i].lng, reason: 'punto $i: lng');
      expect(reread[i].timestamp, allSamples[i].timestamp,
          reason: 'punto $i: timestamp');
    }
  });

  test(
      'resetFullPilotTrackForNewSession cancella i chunk di una sessione '
      'precedente prima del primo flush incrementale', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 18, 7, 0, 0);

    // Sessione precedente, più lunga, salvata regolarmente a fine gara.
    await service.saveFullPilotTrack(
        eventId, userId, _buildRealisticTrack(9000, start));

    // Nuova sessione: reset esplicito, poi un solo flush incrementale
    // corto. Senza il reset, i chunk della sessione precedente (più
    // lunga) resterebbero mescolati a quelli nuovi.
    await service.resetFullPilotTrackForNewSession(eventId, userId);
    final newSamples = _buildRealisticTrack(300, start);
    await service.appendFullPilotTrackChunks(eventId, userId, newSamples,
        startIndex: 0);

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, 300);
  });

  test(
      'fallback: traccia salvata col vecchio campo singolo pilotTrackFull '
      '(pre-fix, sotto 1 MiB) resta leggibile', () async {
    final fake = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: fake);
    final start = DateTime(2026, 8, 9, 9, 0, 0);
    final samples = _buildRealisticTrack(100, start);

    await fake
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .set({
      'pilotTrackFull': samples
          .map((s) => {
                'lat': s.lat,
                'lng': s.lng,
                'accuracy': s.accuracy,
                'ts': s.timestamp.millisecondsSinceEpoch,
              })
          .toList(),
    });

    final reread = await service.getFullPilotTrack(eventId, userId);
    expect(reread.length, samples.length);
    expect(reread.first.timestamp, samples.first.timestamp);
    expect(reread.last.timestamp, samples.last.timestamp);
  });
}
