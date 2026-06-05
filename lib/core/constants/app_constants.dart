class AppConstants {
  AppConstants._();
  static const double waypointRadiusMeters = 10.0;
  static const int gpsIntervalNearWaypointMs = 250;
  static const int gpsIntervalInSpecialMs = 500;
  static const int gpsIntervalTransferMs = 3000;
  static const double nearWaypointThresholdMeters = 50.0;
  static const String adminSecretCode = 'CCR2024';

  // FCM VAPID key per web push.
  // Generare da: Firebase Console → Project Settings → Cloud Messaging
  // → Web Push certificates → Generate key pair
  static const String fcmWebVapidKey =
      'BARNRoOWDjXW2o0-pCTa_EH-9-h888qnSh9XTP-ZZB9jfQ5e1O1knkmx1naZjHknhvy02ANm4sjiC9VIRWXqHiU';
}
