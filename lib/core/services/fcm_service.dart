import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'firestore_service.dart';

class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Chiede i permessi, recupera il token FCM e lo salva in Firestore.
  /// Da chiamare dopo il login dell'utente.
  static Future<void> initialize(
      String userId, FirestoreService firestoreService) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? AppConstants.fcmWebVapidKey : null,
    );
    if (token != null) {
      await firestoreService.saveUserFcmToken(userId, token);
    }

    // Aggiorna il token quando viene rinnovato da FCM
    _messaging.onTokenRefresh.listen((newToken) {
      firestoreService.saveUserFcmToken(userId, newToken);
    });
  }

  /// Configura il canale Android per notifiche foreground ad alta priorità.
  static Future<void> setForegroundNotificationOptions() async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
}

/// Handler eseguito in background/app terminata (top-level, fuori da qualsiasi classe).
/// Firebase lo esegue in un isolato separato.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase è già inizializzato dal sistema quando questo handler viene invocato.
  // Non serve Firebase.initializeApp() qui: lo gestisce il plugin automaticamente.
}
