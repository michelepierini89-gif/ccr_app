import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/providers/offline_provider.dart';
import 'core/services/fcm_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  final prefs = await SharedPreferences.getInstance();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    runApp(const _FirebaseNotConfiguredApp());
    return;
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FcmService.setForegroundNotificationOptions();
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const CcrApp(),
  ));
}

class _FirebaseNotConfiguredApp extends StatelessWidget {
  const _FirebaseNotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0a0c12),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'CCR',
                  style: TextStyle(
                      color: Color(0xFFe53e1e),
                      fontSize: 48,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Firebase non configurato',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 16),
                const Text(
                  '1. Crea progetto su console.firebase.google.com\n'
                  '2. Aggiungi app Android: com.ccr.ccr_app\n'
                  '3. Scarica google-services.json → android/app/\n'
                  '4. Aggiungi app iOS: com.ccr.ccrApp\n'
                  '5. Scarica GoogleService-Info.plist → ios/Runner/\n'
                  '6. Abilita Auth (email), Firestore, Storage',
                  style: TextStyle(
                      color: Color(0xFFa0a8b8),
                      fontSize: 14,
                      height: 1.6),
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
