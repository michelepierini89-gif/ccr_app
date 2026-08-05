import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Guida il pilota nella configurazione di tutto ciò che serve al GPS in
/// background — la funzione più critica dell'app: se l'ottimizzazione
/// batteria è attiva, la traccia si perde a schermo spento. Espone lo stato
/// via [BatterySetupService.battery] su Android; restituisce sempre valori
/// "ok" su web/altre piattaforme, dove il vincolo non si applica.
class BatterySetupService {
  BatterySetupService._();

  static const _channel = MethodChannel('ccr/battery');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True se l'app è già esclusa dall'ottimizzazione batteria (GPS ok).
  /// True su web e piattaforme non-Android (il vincolo non si applica).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return true;
    }
  }

  /// Apre il dialog di sistema per disattivare l'ottimizzazione batteria
  /// con un tap (ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (_) {}
  }

  /// Fallback: apre la lista di sistema delle app non ottimizzate, per i
  /// casi in cui il dialog diretto non sia disponibile sul device.
  static Future<void> openBatterySettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  /// Produttore del dispositivo (Build.MANUFACTURER). Stringa vuota su
  /// piattaforme non-Android.
  static Future<String> manufacturer() async {
    if (!_isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('getManufacturer') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Modello del dispositivo (Build.MODEL). Stringa vuota su piattaforme
  /// non-Android.
  static Future<String> deviceModel() async {
    if (!_isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('getDeviceModel') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// True se il foreground service (registrazione GPS) è attualmente attivo.
  static Future<bool> isForegroundServiceActive() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isForegroundServiceActive') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Tenta di aprire la schermata di risparmio energetico/autostart
  /// proprietaria del produttore (Xiaomi/Oppo/Vivo/Huawei/Realme/OnePlus/
  /// Samsung); se l'intent non esiste su questo device ricade
  /// automaticamente sulle impostazioni app generiche. Gestisce sempre
  /// l'eccezione lato nativo — questi intent non sono standard Android.
  static Future<void> openManufacturerBatterySettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openManufacturerBatterySettings');
    } catch (_) {}
  }

  /// Produttori noti per avere un risparmio energetico proprietario oltre
  /// all'esenzione standard Android — l'esenzione da sola non basta,
  /// serve anche disattivare il loro risparmio batteria/autostart.
  static const List<String> aggressiveManufacturers = [
    'xiaomi',
    'oppo',
    'vivo',
    'huawei',
    'oukitel',
    'realme',
    'oneplus',
    'samsung',
  ];

  static bool isAggressiveManufacturer(String manufacturer) {
    final m = manufacturer.toLowerCase();
    return aggressiveManufacturers.any((k) => m.contains(k));
  }

  /// Istruzioni testuali con il percorso esatto nelle impostazioni per il
  /// produttore rilevato, o null se non è tra quelli noti per richiedere
  /// passaggi extra.
  static String? instructionsFor(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi')) {
      return 'Impostazioni → App → Gestisci app → CCR → Risparmio '
          'batteria → Nessuna restrizione, più Avvio automatico attivo.';
    }
    if (m.contains('oppo') || m.contains('realme')) {
      return 'Impostazioni → Batteria → Gestione batteria app → CCR → '
          'Consenti attività in background, più Avvio automatico attivo '
          '(Impostazioni → App → Avvio automatico).';
    }
    if (m.contains('vivo')) {
      return 'Impostazioni → Batteria → Consumo energetico elevato in '
          'background → CCR → Consenti, più Impostazioni → App → '
          'Gestione autorizzazioni → Avvio automatico → CCR attivo.';
    }
    if (m.contains('huawei')) {
      return 'Impostazioni → Batteria → Avvio app → CCR → Gestisci '
          'manualmente → attiva Avvio automatico, Avvio associato e '
          'Esecuzione in background.';
    }
    if (m.contains('oneplus')) {
      return 'Impostazioni → Batteria → Ottimizzazione batteria → CCR → '
          'Non ottimizzare, più Impostazioni → App → CCR → Avvio '
          'automatico attivo.';
    }
    if (m.contains('samsung')) {
      return 'Impostazioni → Cura batteria e dispositivo → Batteria → '
          'Limiti utilizzo in background → assicurati che CCR NON sia in '
          '"App in sospensione" o "App sospese profonde".';
    }
    if (m.contains('oukitel')) {
      return 'Impostazioni → Batteria → Ottimizzazione batteria → CCR → '
          'Non ottimizzare. Su alcuni modelli Oukitel controlla anche '
          'Impostazioni → App → CCR → Consumo energetico → Nessuna '
          'restrizione.';
    }
    return null;
  }
}
