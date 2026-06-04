class AppConstants {
  AppConstants._();
  static const double waypointRadiusMeters = 10.0;
  static const int gpsIntervalNearWaypointMs = 250;
  static const int gpsIntervalInSpecialMs = 1000;
  static const int gpsIntervalTransferMs = 3000;
  static const double nearWaypointThresholdMeters = 50.0;
  static const String adminSecretCode = 'CCR2024';

  // FCM VAPID key per web push.
  // Generare da: Firebase Console → Project Settings → Cloud Messaging
  // → Web Push certificates → Generate key pair
  static const String fcmWebVapidKey = 'YOUR_VAPID_KEY_HERE';
}
