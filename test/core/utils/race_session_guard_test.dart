/// Fix (bug test 18/08, "Carring CLO 3") — copertura delle due protezioni
/// contro una gara conclusa nei primi minuti dall'avvio o per stato locale
/// corrotto. Vedi lib/core/utils/race_session_guard.dart per il contesto.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ccr_app/core/utils/race_session_guard.dart';

void main() {
  group('canAutoConcludeRace', () {
    test('rifiuta una conclusione nei primi 3 minuti dall\'avvio', () {
      final start = DateTime(2026, 8, 18, 7, 0, 0);
      expect(
        canAutoConcludeRace(
            recordingStart: start, now: start.add(const Duration(seconds: 30))),
        isFalse,
      );
      expect(
        canAutoConcludeRace(
            recordingStart: start,
            now: start.add(const Duration(minutes: 2, seconds: 59))),
        isFalse,
      );
    });

    test('accetta una conclusione dopo la soglia di protezione', () {
      final start = DateTime(2026, 8, 18, 7, 0, 0);
      expect(
        canAutoConcludeRace(
            recordingStart: start, now: start.add(minRaceProtection)),
        isTrue,
      );
      expect(
        canAutoConcludeRace(
            recordingStart: start,
            now: start.add(const Duration(hours: 1))),
        isTrue,
      );
    });
  });

  group('isOrphanLocalSession', () {
    test('stato locale non in registrazione non è mai orfano', () {
      expect(
        isOrphanLocalSession(
            localIsRecording: false, firestoreRaceStatus: null),
        isFalse,
      );
      expect(
        isOrphanLocalSession(
            localIsRecording: false, firestoreRaceStatus: 'finished'),
        isFalse,
      );
    });

    test(
        'stato locale in registrazione senza riscontro Firestore è orfano '
        '(tracking mai avviato)', () {
      expect(
        isOrphanLocalSession(
            localIsRecording: true, firestoreRaceStatus: null),
        isTrue,
      );
    });

    test(
        'stato locale in registrazione con Firestore su un esito passato '
        '(finished/retired) è orfano', () {
      expect(
        isOrphanLocalSession(
            localIsRecording: true, firestoreRaceStatus: 'finished'),
        isTrue,
      );
      expect(
        isOrphanLocalSession(
            localIsRecording: true, firestoreRaceStatus: 'retired'),
        isTrue,
      );
    });

    test(
        'stato locale in registrazione confermato da Firestore non è '
        'orfano', () {
      expect(
        isOrphanLocalSession(
            localIsRecording: true, firestoreRaceStatus: 'racing'),
        isFalse,
      );
    });
  });
}
