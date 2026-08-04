import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Qualità sintetica del fix GNSS, calcolata da satelliti usati + C/N0
/// medio (vedi [GnssStatusSnapshot.quality]) — molto più affidabile del
/// solo campo `accuracy` di FusedLocationProvider, ottimistico sui chip
/// economici (es. MediaTek).
enum GnssQuality { eccellente, buona, scarsa, critica }

extension GnssQualityLabel on GnssQuality {
  String get label => switch (this) {
        GnssQuality.eccellente => 'ECCELLENTE',
        GnssQuality.buona => 'BUONA',
        GnssQuality.scarsa => 'SCARSA',
        GnssQuality.critica => 'CRITICA',
      };
}

/// Istantanea dei dati GNSS reali ricevuti dal `GnssStatus.Callback`
/// Android (MainActivity.kt, canale `ccr/gnss_status`).
class GnssStatusSnapshot {
  final int satellitesVisible;
  final int satellitesUsed;
  final double avgCn0;
  final List<String> constellations;
  final bool hasDualFrequency;

  const GnssStatusSnapshot({
    required this.satellitesVisible,
    required this.satellitesUsed,
    required this.avgCn0,
    required this.constellations,
    required this.hasDualFrequency,
  });

  /// Soglie concordate (Blocco C2):
  /// ECCELLENTE: >=12 usati e C/N0 medio >=35
  /// BUONA:      >=8 usati e C/N0 medio >=28
  /// SCARSA:     >=5 usati
  /// CRITICA:    <5 usati
  GnssQuality get quality {
    if (satellitesUsed >= 12 && avgCn0 >= 35) return GnssQuality.eccellente;
    if (satellitesUsed >= 8 && avgCn0 >= 28) return GnssQuality.buona;
    if (satellitesUsed >= 5) return GnssQuality.scarsa;
    return GnssQuality.critica;
  }

  /// Es. "8/14" (usati/visibili), per il debug overlay in navigazione.
  String get satCountLabel => '$satellitesUsed/$satellitesVisible';
}

/// Espone i dati GNSS reali (satelliti usati/visibili, costellazioni,
/// C/N0 medio, dual-frequency) come stream — solo su Android, dove
/// `GnssStatus` è disponibile. Su altre piattaforme (iOS/web) lo stream
/// resta vuoto e [lastSnapshot] resta null: nessun overlay/qualità
/// mostrata, nessun errore.
class GnssStatusService {
  static const EventChannel _channel = EventChannel('ccr/gnss_status');

  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  final StreamController<GnssStatusSnapshot> _controller =
      StreamController<GnssStatusSnapshot>.broadcast();

  GnssStatusSnapshot? _lastSnapshot;
  GnssStatusSnapshot? get lastSnapshot => _lastSnapshot;

  Stream<GnssStatusSnapshot> get stream => _controller.stream;

  /// Avvia l'ascolto del canale nativo. No-op su piattaforme diverse da
  /// Android. Va richiamato quando parte la registrazione GPS e fermato
  /// con [stop] quando finisce, per non tenere il callback nativo attivo
  /// a schermo spento senza motivo.
  void start() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_sub != null) return;
    _sub = _channel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {}, // canale non disponibile (build non aggiornata): ignora
      cancelOnError: false,
    );
  }

  void _onEvent(dynamic event) {
    if (_disposed) return;
    final map = Map<String, dynamic>.from(event as Map);
    final snapshot = GnssStatusSnapshot(
      satellitesVisible: (map['satellitesVisible'] as num?)?.toInt() ?? 0,
      satellitesUsed: (map['satellitesUsed'] as num?)?.toInt() ?? 0,
      avgCn0: (map['avgCn0'] as num?)?.toDouble() ?? 0.0,
      constellations:
          List<String>.from(map['constellations'] as List? ?? const []),
      hasDualFrequency: map['hasDualFrequency'] as bool? ?? false,
    );
    _lastSnapshot = snapshot;
    _controller.add(snapshot);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _lastSnapshot = null;
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _controller.close();
  }
}
