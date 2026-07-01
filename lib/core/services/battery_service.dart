import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gestisce il controllo e la richiesta di disattivazione ottimizzazione
/// batteria Android. Necessario per il GPS background a schermo spento.
class BatteryOptimizationService {
  static const _channel = MethodChannel('ccr/battery');

  /// True se l'app è già esclusa dall'ottimizzazione batteria (GPS ok).
  /// Restituisce true su web e piattaforme non-Android.
  static Future<bool> isIgnoring() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Apre il dialog di sistema per disattivare l'ottimizzazione batteria.
  static Future<void> requestIgnore() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (_) {}
  }
}
