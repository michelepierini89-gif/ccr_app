/// Test di regressione (Fix 6, 09/08/2026) — dato un heading noto e la
/// modalità mappa rotante (HEADING) attiva, l'angolo finale della freccia
/// deve essere zero e la rotazione mappa l'opposto dell'heading. Deve
/// fallire se in futuro qualcuno reintroduce una doppia rotazione (freccia
/// E mappa che ruotano entrambe in base allo stesso heading).
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ccr_app/core/utils/heading_display_utils.dart';

void main() {
  group('modalità HEADING (mappa rotante)', () {
    test('la freccia ha SEMPRE angolo zero, qualunque sia l\'heading', () {
      for (final heading in [0.0, 45.0, 90.0, 180.0, 270.0, 359.9]) {
        expect(HeadingDisplayUtils.arrowAngleRad(true, heading), 0.0,
            reason: 'heading=$heading');
      }
    });

    test('la rotazione mappa è sempre l\'opposto esatto dell\'heading', () {
      for (final heading in [0.0, 45.0, 90.0, 180.0, 270.0, 359.9]) {
        expect(HeadingDisplayUtils.mapRotationDeg(true, heading), -heading,
            reason: 'heading=$heading');
      }
    });
  });

  group('modalità NORD (mappa fissa)', () {
    test('la mappa non ruota mai, qualunque sia l\'heading', () {
      for (final heading in [0.0, 45.0, 90.0, 180.0, 270.0, 359.9]) {
        expect(HeadingDisplayUtils.mapRotationDeg(false, heading), 0.0,
            reason: 'heading=$heading');
      }
    });

    test('la freccia ruota esattamente dell\'heading, in radianti', () {
      for (final heading in [0.0, 45.0, 90.0, 180.0, 270.0, 359.9]) {
        expect(HeadingDisplayUtils.arrowAngleRad(false, heading),
            closeTo(heading * pi / 180, 1e-9),
            reason: 'heading=$heading');
      }
    });
  });

  test(
      'MAI ENTRAMBE: se la mappa ruota (HEADING), la freccia non ruota mai '
      'anche in aggiunta — nessuna doppia rotazione', () {
    for (final heading in [0.0, 10.0, 123.4, 359.0]) {
      final mapRot = HeadingDisplayUtils.mapRotationDeg(true, heading);
      final arrowRot = HeadingDisplayUtils.arrowAngleRad(true, heading);
      // La mappa ruota (a meno di heading==0), la freccia mai.
      expect(arrowRot, 0.0, reason: 'heading=$heading mapRot=$mapRot');
    }
  });
}
