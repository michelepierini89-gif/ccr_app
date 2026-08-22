/// Controllo stabile sulle regole (Step 51, punto 5) — è la terza/quarta
/// volta che una struttura Firestore nuova arriva in produzione senza una
/// regola corrispondente, scoperta solo durante un test sul campo (vedi
/// `attempts`/`trainingResults` e la scoperta collaterale `officialTimes`,
/// tutte in questa stessa sessione). Un controllo interamente automatico
/// (dedurre ogni query dal codice sorgente) sarebbe fragile — i percorsi
/// sono costruiti da helper/costanti, non stringhe letterali nel punto di
/// lettura — quindi [kFirestorePathsUsedByApp] è una lista mantenuta a
/// mano: quando il codice inizia a leggere/scrivere una struttura NUOVA,
/// va aggiunta qui. Il test sotto la confronta con `firestore.rules`
/// REALE (letto dal file, non trascritto a mano una seconda volta): se una
/// struttura elencata qui non trova un `match` che la copra, la suite
/// fallisce invece di scoprirlo su un dispositivo in gara.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Percorsi Firestore realmente letti/scritti da `FirestoreService`/
/// `AuthService` (verificato: sono le uniche due classi che toccano
/// Firestore direttamente in questo progetto — vedi
/// `grep FirebaseFirestore.instance`). Ogni segmento variabile è scritto
/// come `{nome}` (il nome non conta per il confronto, solo la posizione);
/// il nome della collezione è sempre quello REALE su Firestore (vedi
/// `FirebaseConstants`), non il nome della costante Dart.
const List<String> kFirestorePathsUsedByApp = [
  'users/{userId}',
  'user_notifications/{userId}',
  'user_notifications/{userId}/items',
  'events/{eventId}',
  'events/{eventId}/iscritti/{userId}',
  'events/{eventId}/registrations/{userId}',
  'events/{eventId}/squadre/{teamId}',
  'events/{eventId}/penalty_settings/{docId}',
  'events/{eventId}/withdrawals/{userId}',
  'events/{eventId}/notifications/{notifId}',
  'tracking/{eventId}/pilots/{userId}',
  'tracking/{eventId}/pilots/{userId}/fullTrackChunks/{chunkId}',
  'tracking/{eventId}/pilots/{userId}/attempts/{attemptId}',
  'tracking/{eventId}/pilots/{userId}/attempts/{attemptId}/fullTrackChunks/{chunkId}',
  'tracking/{eventId}/pilots/{userId}/attempts/{attemptId}/passages/{passageId}',
  'tracking/{eventId}/pilots/{userId}/attempts/{attemptId}/speedZoneViolations/{violationId}',
  'tracking/{eventId}/trainingResults/{attemptId}',
  'tracking/{eventId}/routeVariantByUser/{userId}',
  'tracking/{eventId}/passages/{passageId}',
  'tracking/{eventId}/speedZoneViolations/{violationId}',
  'tracking/{eventId}/officialTimes/{userId}',
  'cp_disputes/{eventId}/disputes/{disputeId}',
  'championships/{champId}',
  'penalty_settings/{docId}',
];

/// Il bypass admin globale (`match /{document=**} { allow ...: if
/// isAdmin(); }`) copre letteralmente OGNI percorso — se lo si contasse
/// come "copertura", il test non scoprirebbe mai un buco reale per un
/// pilota non-admin (esattamente il bug di questa sessione: gli
/// `attempts` erano "coperti" solo da questo bypass). Escluso dal
/// confronto: conta solo una regola SPECIFICA per quel percorso.
const List<String> _ignoredRulePaths = ['{document=**}'];

/// Estrae ogni blocco `match /a/{b}/c {` dal testo delle regole, con il
/// percorso COMPLETO (inclusa la nidificazione) risolto seguendo le
/// parentesi graffe — non un semplice elenco di righe: un `match` interno
/// (es. `passages` sotto `attempts` sotto `pilots`) deve comparire con il
/// suo percorso intero, altrimenti il confronto con
/// [kFirestorePathsUsedByApp] non potrebbe mai avere successo.
List<List<String>> parseRulePaths(String rulesText) {
  final matchLineRe = RegExp(r'match\s+(/\S+)\s*\{');
  final stack = <({int closeAtDepth, List<String> segments})>[];
  final found = <List<String>>[];
  var depth = 0;

  for (final line in rulesText.split('\n')) {
    final m = matchLineRe.firstMatch(line);
    if (m != null) {
      final segs =
          m.group(1)!.split('/').where((s) => s.isNotEmpty).toList();
      final openDepth = depth;
      final full = [
        for (final e in stack) ...e.segments,
        ...segs,
      ];
      found.add(full);
      stack.add((closeAtDepth: openDepth, segments: segs));
    }
    final opens = '{'.allMatches(line).length;
    final closes = '}'.allMatches(line).length;
    depth += opens - closes;
    while (stack.isNotEmpty && depth <= stack.last.closeAtDepth) {
      stack.removeLast();
    }
  }

  // Ogni match reale vive sotto l'involucro fisso
  // `databases/{database}/documents` — rimosso perché nessun percorso
  // applicativo lo include.
  const wrapperLength = 3;
  return found
      .map((full) => full.length >= wrapperLength
          ? full.sublist(wrapperLength)
          : full)
      .where((full) => full.isNotEmpty)
      .where((full) => !_ignoredRulePaths.contains(full.join('/')))
      .toList();
}

bool _isWildcardSegment(String seg) => seg.startsWith('{') && seg.endsWith('}');

bool _matches(List<String> codeSegs, List<String> ruleSegs) {
  var ci = 0;
  for (final rseg in ruleSegs) {
    if (rseg.contains('=**}')) {
      // Wildcard ricorsivo: copre qualunque profondità restante (incluso
      // zero elementi aggiuntivi).
      return ci <= codeSegs.length;
    }
    if (ci >= codeSegs.length) return false;
    final cseg = codeSegs[ci];
    if (!_isWildcardSegment(rseg) && rseg != cseg) return false;
    ci++;
  }
  return ci == codeSegs.length;
}

void main() {
  late String rulesText;

  setUpAll(() {
    // Percorso relativo alla working directory di `flutter test` (root
    // del progetto) — stesso file che viene deployato con
    // `firebase deploy --only firestore:rules`, non una copia.
    rulesText = File('firestore.rules').readAsStringSync();
  });

  test('ogni percorso Firestore usato dall\'app è coperto da una regola '
      'specifica (non solo dal bypass admin)', () {
    final rulePaths = parseRulePaths(rulesText);
    final uncovered = <String>[];

    for (final codePath in kFirestorePathsUsedByApp) {
      final codeSegs = codePath.split('/');
      final covered = rulePaths.any((rule) => _matches(codeSegs, rule));
      if (!covered) uncovered.add(codePath);
    }

    expect(uncovered, isEmpty,
        reason: 'Percorsi usati dall\'app senza una regola Firestore '
            'specifica (coperti solo dal bypass admin, se non elencati '
            'anche lì): $uncovered. Aggiungi la regola in firestore.rules '
            '— vedi PROGETTO_CCR.md, Step 51, punto 1/5.');
  });

  test('il parser delle regole trova almeno i match noti (sanity check '
      'sul parser stesso)', () {
    final rulePaths = parseRulePaths(rulesText);
    final joined = rulePaths.map((s) => s.join('/')).toSet();
    expect(joined, contains('users/{userId}'));
    expect(
        joined,
        contains(
            'tracking/{eventId}/pilots/{userId}/attempts/{attemptId}/passages/{passageId}'));
    expect(joined, contains('tracking/{eventId}/trainingResults/{attemptId}'));
  });
}
