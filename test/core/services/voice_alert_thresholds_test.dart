/// Test di regressione (Fix 7, 09/08/2026):
/// A. le soglie di ATTIVAZIONE degli avvisi di avvicinamento (prove
///    speciali, pericoli, zone velocità) sono anticipate (200/650/1200m
///    invece di 100/500/1000m), ma il TESTO parlato resta quello storico
///    ("cento metri"/"cinquecento metri"/"un chilometro").
/// B. esiste un annuncio di uscita dalla zona a velocità controllata,
///    simmetrico a quello di ingresso.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccr_app/core/services/voice_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le soglie di attivazione sono anticipate a 200/650/1200 metri', () {
    expect(VoiceAlertService.approachThresholds, [1200, 650, 200]);
  });

  test('il testo parlato resta quello storico per le nuove soglie', () {
    expect(VoiceAlertService.distanceLabelForThreshold(1200), 'un chilometro');
    expect(
        VoiceAlertService.distanceLabelForThreshold(650), 'cinquecento metri');
    expect(VoiceAlertService.distanceLabelForThreshold(200), 'cento metri');
  });

  test(
      'il testo parlato per le soglie storiche invariate (punto ristoro) '
      'resta corretto', () {
    expect(VoiceAlertService.fuelApproachThresholds, [1000, 500]);
    expect(VoiceAlertService.distanceLabelForThreshold(1000), 'un chilometro');
    expect(
        VoiceAlertService.distanceLabelForThreshold(500), 'cinquecento metri');
  });

  test(
      'announceSpeedZoneEntry/Exit non lanciano eccezioni anche senza '
      'motore TTS disponibile (ambiente di test headless, come start() mai '
      'chiamato con successo su un device reale)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = VoiceAlertService(prefs);
    // _ttsInitialized resta false senza un motore TTS reale: _enqueue fa
    // early-return, quindi queste chiamate non devono lanciare eccezioni.
    expect(() => service.announceSpeedZoneEntry('zona1', 50), returnsNormally);
    expect(() => service.announceSpeedZoneExit('zona1'), returnsNormally);
  });
}
