class AppConstants {
  AppConstants._();
  static const double waypointRadiusMeters = 10.0;
  // Checkpoints (SpecialModel.controlPoints) use a wider radius: they are
  // boolean pass/fail only and do not affect special timing, so a larger
  // radius is safe. Fix 1 (09/08/2026) — bumped 20→35m and moved detection
  // from point-only+double-confirm to trajectory (segment) distance, see
  // WaypointDetector.detectCheckpointPassage. Overridable per-CP via
  // WaypointModel.checkpointRadiusMeters.
  static const double waypointCheckpointRadiusMeters = 35.0;
  // Zone a velocità controllata: inizio/fine sono solo indicativi (nessun
  // impatto su timing PS o validazione CP), ma un mancato rilevamento
  // dell'uscita blocca il banner live per il resto della sessione — raggio
  // più ampio dei checkpoint normali per privilegiare l'affidabilità
  // dell'uscita rispetto alla precisione del punto esatto.
  static const double speedZoneRadiusMeters = 35.0;
  // Radius within which a fuel point ("punto ristoro") is considered passed.
  static const double fuelPointRadiusMeters = 15.0;
  static const int gpsIntervalNearWaypointMs = 250;
  static const int gpsIntervalInSpecialMs = 250;
  static const int gpsIntervalTransferMs = 1000;
  static const double nearWaypointThresholdMeters = 50.0;

  // Punti pericolo: soglie di prossimità per i banner di avviso/allerta.
  static const double dangerWarningRadiusMeters = 150.0;
  static const double dangerAlertRadiusMeters = 50.0;
  static const double dangerAlertClearRadiusMeters = 60.0;
  static const double dangerRemoveRadiusMeters = 100.0;
  static const double dangerPassedRadiusMeters = 15.0;
  static const int gpsIntervalNearDangerMs = 500;

  // Distanza massima tra un tap sulla mappa e la traccia di riferimento
  // per accettare l'inserimento di un punto pericolo o ristoro.
  static const double trackSnapMaxDistanceMeters = 50.0;
  static const String adminSecretCode = 'CCR2024';

  // FCM VAPID key per web push.
  // Generare da: Firebase Console → Project Settings → Cloud Messaging
  // → Web Push certificates → Generate key pair
  static const String fcmWebVapidKey =
      'BARNRoOWDjXW2o0-pCTa_EH-9-h888qnSh9XTP-ZZB9jfQ5e1O1knkmx1naZjHknhvy02ANm4sjiC9VIRWXqHiU';
}
