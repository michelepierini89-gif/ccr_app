import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'diagnostic_logger.dart';

/// Livello di priorità di un annuncio vocale (Blocco D2).
enum VoiceAlertPriority { alta, media, bassa }

/// Categoria di annuncio, per i toggle utente in [VoiceAlertSettings].
enum VoiceAlertCategory {
  pericoli,
  proveSpeciali,
  zoneVelocita,
  checkpoint,
  puntoRistoro,
}

/// Impostazioni utente per gli avvisi vocali, persistite in
/// SharedPreferences (Blocco D5) — stesso pattern di
/// `TrackAppearanceSettings`/`TrackAppearanceService`.
class VoiceAlertSettings {
  final bool enabled;
  final bool dangerEnabled;
  final bool specialsEnabled;
  final bool speedZonesEnabled;
  final bool checkpointsEnabled;
  final bool fuelPointEnabled;
  final double speechRate;

  const VoiceAlertSettings({
    this.enabled = true,
    this.dangerEnabled = true,
    this.specialsEnabled = true,
    this.speedZonesEnabled = true,
    this.checkpointsEnabled = true,
    this.fuelPointEnabled = true,
    this.speechRate = VoiceAlertService.defaultSpeechRate,
  });

  VoiceAlertSettings copyWith({
    bool? enabled,
    bool? dangerEnabled,
    bool? specialsEnabled,
    bool? speedZonesEnabled,
    bool? checkpointsEnabled,
    bool? fuelPointEnabled,
    double? speechRate,
  }) =>
      VoiceAlertSettings(
        enabled: enabled ?? this.enabled,
        dangerEnabled: dangerEnabled ?? this.dangerEnabled,
        specialsEnabled: specialsEnabled ?? this.specialsEnabled,
        speedZonesEnabled: speedZonesEnabled ?? this.speedZonesEnabled,
        checkpointsEnabled: checkpointsEnabled ?? this.checkpointsEnabled,
        fuelPointEnabled: fuelPointEnabled ?? this.fuelPointEnabled,
        speechRate: speechRate ?? this.speechRate,
      );
}

class _QueuedAlert {
  final String text;
  final VoiceAlertPriority priority;
  const _QueuedAlert(this.text, this.priority);
}

/// Sistema di annunci vocali per la navigazione in moto (Blocco D): il
/// pilota ha il casco, l'audio è l'unico canale davvero utilizzabile in
/// movimento. Gestisce coda con priorità, soglie di distanza fisse e
/// instradamento audio corretto sull'interfono Bluetooth via
/// `setAudioAttributesForNavigation()` (Android: usage
/// ASSISTANCE_NAVIGATION_GUIDANCE, content type SPEECH).
class VoiceAlertService {
  static const double defaultSpeechRate = 0.55;
  static const double minSpeechRate = 0.4;
  static const double maxSpeechRate = 1.0;

  /// Soglie di avvicinamento fisse (metri), in ordine decrescente —
  /// l'ordine è significativo per [_consumeClosestThreshold].
  static const List<int> approachThresholds = [1000, 500, 100];

  /// Il punto ristoro usa solo 1000m/500m (priorità BASSA, niente avviso
  /// imminente a 100m).
  static const List<int> fuelApproachThresholds = [1000, 500];

  static const _kEnabledKey = 'voice_alerts_enabled';
  static const _kDangerKey = 'voice_alerts_danger';
  static const _kSpecialsKey = 'voice_alerts_specials';
  static const _kSpeedZonesKey = 'voice_alerts_speed_zones';
  static const _kCheckpointsKey = 'voice_alerts_checkpoints';
  static const _kFuelPointKey = 'voice_alerts_fuel_point';
  static const _kSpeechRateKey = 'voice_alerts_speech_rate';

  final SharedPreferences _prefs;
  final FlutterTts _tts = FlutterTts();

  VoiceAlertSettings _settings;
  bool _ttsInitialized = false;
  bool _disposed = false;

  final List<_QueuedAlert> _queue = [];
  bool _speaking = false;
  VoiceAlertPriority? _currentPriority;

  /// Chiavi "{elementId}_{soglia}" (o "{tipo}_{elementId}" per gli eventi
  /// "attraversato") già annunciate in questa sessione — azzerato SOLO in
  /// [start] (D3/D6).
  final Set<String> _announcedKeys = {};

  final DiagnosticLogger? _diagLogger;

  VoiceAlertService(this._prefs, [this._diagLogger])
      : _settings = _loadSettings(_prefs);

  VoiceAlertSettings get settings => _settings;

  static VoiceAlertSettings _loadSettings(SharedPreferences prefs) =>
      VoiceAlertSettings(
        enabled: prefs.getBool(_kEnabledKey) ?? true,
        dangerEnabled: prefs.getBool(_kDangerKey) ?? true,
        specialsEnabled: prefs.getBool(_kSpecialsKey) ?? true,
        speedZonesEnabled: prefs.getBool(_kSpeedZonesKey) ?? true,
        checkpointsEnabled: prefs.getBool(_kCheckpointsKey) ?? true,
        fuelPointEnabled: prefs.getBool(_kFuelPointKey) ?? true,
        speechRate: (prefs.getDouble(_kSpeechRateKey) ?? defaultSpeechRate)
            .clamp(minSpeechRate, maxSpeechRate),
      );

  /// Aggiorna e persiste le impostazioni; se la velocità di lettura è
  /// cambiata e il TTS è già inizializzato, la applica subito.
  Future<void> updateSettings(VoiceAlertSettings newSettings) async {
    final rateChanged = newSettings.speechRate != _settings.speechRate;
    _settings = newSettings;
    await Future.wait([
      _prefs.setBool(_kEnabledKey, newSettings.enabled),
      _prefs.setBool(_kDangerKey, newSettings.dangerEnabled),
      _prefs.setBool(_kSpecialsKey, newSettings.specialsEnabled),
      _prefs.setBool(_kSpeedZonesKey, newSettings.speedZonesEnabled),
      _prefs.setBool(_kCheckpointsKey, newSettings.checkpointsEnabled),
      _prefs.setBool(_kFuelPointKey, newSettings.fuelPointEnabled),
      _prefs.setDouble(_kSpeechRateKey, newSettings.speechRate),
    ]);
    if (rateChanged && _ttsInitialized) {
      await _tts.setSpeechRate(newSettings.speechRate);
    }
  }

  // ── Ciclo di vita (D6) ──────────────────────────────────────────────────

  /// Inizializza il TTS — richiamato in `GpsService.startRecording()`.
  /// Azzera coda e soglie già annunciate: nuova sessione, nuovi avvisi.
  Future<void> start() async {
    if (_disposed) return;
    _announcedKeys.clear();
    _queue.clear();
    _speaking = false;
    _currentPriority = null;
    if (_ttsInitialized) return;
    try {
      await _tts.setLanguage('it-IT');
      await _tts.setSpeechRate(_settings.speechRate);
      await _tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setAudioAttributesForNavigation();
      }
      _ttsInitialized = true;
    } catch (_) {
      // Motore TTS non disponibile (es. nessuna lingua it-IT installata):
      // nessun annuncio verrà riprodotto, ma la registrazione GPS non deve
      // fallire per questo.
    }
  }

  /// Ferma il TTS e svuota la coda — richiamato in `stopRecording()`/RITIRO.
  /// Nessun annuncio quando la registrazione non è attiva.
  Future<void> stop() async {
    _queue.clear();
    _speaking = false;
    _currentPriority = null;
    if (_ttsInitialized) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _tts.stop().ignore();
  }

  // ── Coda con priorità (D2) ──────────────────────────────────────────────

  void _enqueue(String text, VoiceAlertPriority priority) {
    if (_disposed || !_ttsInitialized) return;

    // Un annuncio ALTA interrompe uno in corso di priorità inferiore (ma
    // non un altro ALTA già in corso, che resta fino alla fine).
    if (priority == VoiceAlertPriority.alta &&
        _speaking &&
        _currentPriority != VoiceAlertPriority.alta) {
      _queue.clear();
      unawaited(_tts.stop());
    }

    _queue.add(_QueuedAlert(text, priority));

    // Se la coda supera 3 elementi, scarta i BASSA più vecchi.
    while (_queue.length > 3) {
      final idx =
          _queue.indexWhere((a) => a.priority == VoiceAlertPriority.bassa);
      if (idx == -1) break;
      _queue.removeAt(idx);
    }

    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_speaking || _disposed) return;
    _speaking = true;
    while (_queue.isNotEmpty && !_disposed) {
      final next = _queue.removeAt(0);
      _currentPriority = next.priority;
      _diagLogger?.logVoiceAnnouncement(next.priority.name, next.text);
      try {
        await _tts.speak(next.text);
      } catch (_) {}
    }
    _speaking = false;
    _currentPriority = null;
  }

  bool _categoryEnabled(VoiceAlertCategory c) {
    if (!_settings.enabled) return false;
    return switch (c) {
      VoiceAlertCategory.pericoli => _settings.dangerEnabled,
      VoiceAlertCategory.proveSpeciali => _settings.specialsEnabled,
      VoiceAlertCategory.zoneVelocita => _settings.speedZonesEnabled,
      VoiceAlertCategory.checkpoint => _settings.checkpointsEnabled,
      VoiceAlertCategory.puntoRistoro => _settings.fuelPointEnabled,
    };
  }

  void _announce(
      String text, VoiceAlertPriority priority, VoiceAlertCategory category) {
    if (!_categoryEnabled(category)) return;
    _enqueue(text, priority);
  }

  // ── Soglie di distanza (D3) ──────────────────────────────────────────────

  static String _distanceLabel(int thresholdM) => switch (thresholdM) {
        1000 => 'un chilometro',
        500 => 'cinquecento metri',
        100 => 'cento metri',
        _ => '$thresholdM metri',
      };

  /// Controlla le soglie [thresholds] (decrescenti) per [elementKey] a
  /// [distanceM]. Ogni soglia scatta una sola volta; se il pilota ne
  /// supera più di una tra due fix GPS, ritorna solo la più vicina
  /// raggiunta e marca come già annunciate anche quelle saltate. Le
  /// soglie superate non si riattivano tornando indietro.
  int? _consumeClosestThreshold(
      String elementKey, double distanceM, List<int> thresholds) {
    int? closest;
    for (final t in thresholds) {
      final key = '${elementKey}_$t';
      if (_announcedKeys.contains(key)) continue;
      if (distanceM <= t) {
        _announcedKeys.add(key);
        closest = t;
      }
    }
    return closest;
  }

  /// Marca [key] come già annunciata una tantum (per gli eventi
  /// "attraversato", non a soglia di distanza). Ritorna true se non era
  /// già stata annunciata (cioè se va effettivamente annunciata ora).
  bool _consumeOnce(String key) {
    if (_announcedKeys.contains(key)) return false;
    _announcedKeys.add(key);
    return true;
  }

  // ── D4: annunci ──────────────────────────────────────────────────────────

  void checkDangerApproach(String dangerId, String description, double distanceM) {
    final t = _consumeClosestThreshold('danger_$dangerId', distanceM, approachThresholds);
    if (t == null) return;
    _announce('Attenzione, $description tra ${_distanceLabel(t)}',
        VoiceAlertPriority.alta, VoiceAlertCategory.pericoli);
  }

  void checkSpecialStartApproach(String specialId, int numero, double distanceM) {
    final t = _consumeClosestThreshold('specialStart_$specialId', distanceM, approachThresholds);
    if (t == null) return;
    _announce('Inizio prova speciale $numero tra ${_distanceLabel(t)}',
        VoiceAlertPriority.media, VoiceAlertCategory.proveSpeciali);
  }

  void announceSpecialStartCrossed(String specialId, int numero) {
    if (!_consumeOnce('specialStartCrossed_$specialId')) return;
    _announce('Prova speciale $numero iniziata', VoiceAlertPriority.media,
        VoiceAlertCategory.proveSpeciali);
  }

  void checkSpecialEndApproach(String specialId, int numero, double distanceM) {
    final t = _consumeClosestThreshold('specialEnd_$specialId', distanceM, approachThresholds);
    if (t == null) return;
    _announce('Fine prova speciale $numero tra ${_distanceLabel(t)}',
        VoiceAlertPriority.alta, VoiceAlertCategory.proveSpeciali);
  }

  void announceSpecialEndCrossed(String specialId, int numero, Duration elapsed) {
    if (!_consumeOnce('specialEndCrossed_$specialId')) return;
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    _announce(
        'Prova speciale $numero completata. Tempo $m minuti e $s secondi',
        VoiceAlertPriority.media,
        VoiceAlertCategory.proveSpeciali);
  }

  void checkSpeedZoneApproach(String zoneId, double distanceM, double limitKmh) {
    final t = _consumeClosestThreshold('speedZone_$zoneId', distanceM, approachThresholds);
    if (t == null) return;
    _announce(
        'Zona a velocità controllata tra ${_distanceLabel(t)}, '
        'limite ${limitKmh.round()} chilometri orari',
        VoiceAlertPriority.media,
        VoiceAlertCategory.zoneVelocita);
  }

  void announceSpeedZoneEntry(String zoneId, double limitKmh) {
    if (!_consumeOnce('speedZoneEntry_$zoneId')) return;
    _announce(
        'Inizio zona a velocità controllata, limite ${limitKmh.round()} chilometri orari',
        VoiceAlertPriority.media,
        VoiceAlertCategory.zoneVelocita);
  }

  void announceCheckpointPassed(String checkpointId) {
    if (!_consumeOnce('checkpoint_$checkpointId')) return;
    _announce('Punto di controllo registrato', VoiceAlertPriority.media,
        VoiceAlertCategory.checkpoint);
  }

  void checkFuelPointApproach(String fuelId, double distanceM) {
    final t = _consumeClosestThreshold('fuel_$fuelId', distanceM, fuelApproachThresholds);
    if (t == null) return;
    _announce('Punto ristoro tra ${_distanceLabel(t)}', VoiceAlertPriority.bassa,
        VoiceAlertCategory.puntoRistoro);
  }

  void announceRaceEndAvailable() {
    if (!_consumeOnce('raceEndAvailable')) return;
    _announce('Tutte le prove completate, puoi terminare la gara',
        VoiceAlertPriority.media, VoiceAlertCategory.proveSpeciali);
  }

  /// Annuncio di esempio per il pulsante "Prova audio" nelle impostazioni:
  /// bypassa i toggle di categoria e il Set di dedupe (serve poter
  /// ripetere il test). Inizializza il TTS al volo se non lo è già —
  /// il pulsante deve funzionare anche prima di avviare la registrazione
  /// GPS, per verificare l'instradamento sull'interfono prima di partire.
  Future<void> playTestAnnouncement() async {
    if (!_ttsInitialized) await start();
    _enqueue(
        'Prova audio. Inizio prova speciale uno tra un chilometro',
        VoiceAlertPriority.media);
  }
}
