import 'package:cloud_firestore/cloud_firestore.dart';
import 'event_model.dart';

/// Tabella punti universale per posizione (1-based).
const kChampionshipPoints = [25, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

/// Restituisce i punti per la posizione [position] (1-based).
/// Restituisce 0 se [position] è fuori dalla tabella.
int pointsForPosition(int position) {
  if (position < 1 || position > kChampionshipPoints.length) return 0;
  return kChampionshipPoints[position - 1];
}

class WaypointPassageRecord {
  final String id;
  final String userId;
  final String waypointId;
  final String waypointNome;
  final DateTime timestamp;
  // Non-null se GpsService ha chiuso retroattivamente questo passaggio con
  // un'affidabilità ridotta (es. nessun punto trovato nel buffer di
  // recovery entro il raggio atteso): 'recovery_impreciso' o
  // 'chiusa_da_FINE_GARA'. Letto da ClassificaEngine per segnalarlo
  // all'admin nella stessa UI usata per 'rilevamento_non_valido'.
  final String? timingError;

  const WaypointPassageRecord({
    required this.id,
    required this.userId,
    required this.waypointId,
    required this.waypointNome,
    required this.timestamp,
    this.timingError,
  });

  factory WaypointPassageRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WaypointPassageRecord(
      id: doc.id,
      userId: d['userId'] ?? '',
      waypointId: d['waypointId'] ?? '',
      waypointNome: d['waypointNome'] ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timingError: d['timingError'] as String?,
    );
  }
}

/// Violazione di una zona a velocità controllata registrata su Firestore
/// (`tracking/{eventId}/speedZoneViolations`). Visibile solo all'admin —
/// il pilota non viene avvisato durante la guida.
class SpeedZoneViolation {
  final String id;
  final String userId;
  final String zoneId;
  final double avgSpeedKmh;
  final double limitKmh;
  final DateTime timestamp;

  const SpeedZoneViolation({
    required this.id,
    required this.userId,
    required this.zoneId,
    required this.avgSpeedKmh,
    required this.limitKmh,
    required this.timestamp,
  });

  factory SpeedZoneViolation.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SpeedZoneViolation(
      id: doc.id,
      userId: d['userId'] ?? '',
      zoneId: d['zoneId'] ?? '',
      avgSpeedKmh: (d['avgSpeedKmh'] as num?)?.toDouble() ?? 0.0,
      limitKmh: (d['limitKmh'] as num?)?.toDouble() ?? 0.0,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Dettaglio di una violazione zona velocità per il badge in classifica
/// (nome zona + velocità media rilevata vs limite), usato solo lato admin.
class SpeedZoneViolationInfo {
  final String zoneNome;
  final double avgSpeedKmh;
  final double limitKmh;

  const SpeedZoneViolationInfo({
    required this.zoneNome,
    required this.avgSpeedKmh,
    required this.limitKmh,
  });
}

class SpecialTempo {
  final String specialeId;
  final String specialeNome;
  final int ordine;
  final Duration tempo;       // include già la penalità CP
  final bool controlPointsOk;
  final List<int> missedCpPositions; // 1-based positions of missed control points
  final int penaltySeconds;          // secondi di penalità totali aggiunti (CP + zone velocità)
  final String? timingError;  // non-null se il rilevamento PS non è plausibile
  final DateTime? rawStartTime; // timestamp grezzo di inizio (debug admin)
  final DateTime? rawEndTime;   // timestamp grezzo di fine (debug admin)
  final List<SpeedZoneViolationInfo> speedZoneViolations; // violazioni zona velocità, solo admin
  final int speedZonePenaltySeconds; // quota di penaltySeconds dovuta alle zone velocità

  const SpecialTempo({
    required this.specialeId,
    required this.specialeNome,
    required this.ordine,
    required this.tempo,
    required this.controlPointsOk,
    this.missedCpPositions = const [],
    this.penaltySeconds = 0,
    this.timingError,
    this.rawStartTime,
    this.rawEndTime,
    this.speedZoneViolations = const [],
    this.speedZonePenaltySeconds = 0,
  });

  String get tempoFormatted {
    final m = tempo.inMinutes;
    final s = tempo.inSeconds % 60;
    final cs = (tempo.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  /// Tempo PS calcolato da timestamp implausibili (es. recovery corrotto):
  /// non viene mostrato, sostituito dalla penalità massima.
  bool get isInvalidTiming => timingError == 'rilevamento_non_valido';

  /// Tempo PS calcolato ma con affidabilità ridotta (fine speciale non
  /// rilevata, chiusa con stima di recovery o forzata da FINE GARA): il
  /// tempo resta visibile, ma va segnalato all'admin per un'eventuale
  /// penalità manuale.
  bool get hasTimingWarning => timingError != null && !isInvalidTiming;
}

class ClassificaEntry {
  final String entryId; // teamId or userId for solo pilots
  final String teamNome;
  final List<String> membriNomi;
  final List<SpecialTempo> specialiCompletati;
  final int totaleSpeciali;
  final Duration tempoTotale;     // include penalità CP e ritiro compagno
  final int punteggioTotale;
  final int posizione; // 0 = ritirato / non classificato
  final bool ritirato;
  final bool ritiroCompagno;       // compagno di squadra ritirato (penalità applicata)
  final int ritiroCompagnoPenaltySeconds; // secondi aggiunti per ritiro compagno
  final int pilotiMancanti; // piloti sotto il minimo squadra stabilito nell'evento
  final int pilotiMancantiPenaltySeconds; // secondi aggiunti per piloti mancanti
  final bool isLive; // has recent GPS ping
  final String? retiredReason; // 'timeout' | 'manual' | null

  const ClassificaEntry({
    required this.entryId,
    required this.teamNome,
    required this.membriNomi,
    required this.specialiCompletati,
    required this.totaleSpeciali,
    required this.tempoTotale,
    required this.punteggioTotale,
    required this.posizione,
    required this.ritirato,
    this.ritiroCompagno = false,
    this.ritiroCompagnoPenaltySeconds = 0,
    this.pilotiMancanti = 0,
    this.pilotiMancantiPenaltySeconds = 0,
    required this.isLive,
    this.retiredReason,
  });

  bool get hasFinished => specialiCompletati.length == totaleSpeciali;
  bool get hasStarted => specialiCompletati.isNotEmpty || isLive;

  String get tempoTotaleFormatted {
    if (tempoTotale == Duration.zero) return '--:--.--.--';
    final m = tempoTotale.inMinutes;
    final s = tempoTotale.inSeconds % 60;
    final cs = (tempoTotale.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }
}

/// Risultati di classifica già calcolati per una gara, usati come input per
/// il calcolo della classifica di campionato.
class EventResults {
  final String eventId;
  final List<ClassificaEntry> entries;

  const EventResults({required this.eventId, required this.entries});
}

/// Punteggio di un team in una singola gara del campionato.
class ChampionshipRaceScore {
  final String eventId;
  final String eventNome;
  final TipologiaClassifica tipologia;
  final int points;
  final bool dropped;

  const ChampionshipRaceScore({
    required this.eventId,
    required this.eventNome,
    required this.tipologia,
    required this.points,
    required this.dropped,
  });
}

/// Posizione di un team nella classifica di campionato, con il dettaglio
/// dei punteggi per ogni gara.
class ChampionshipTeamStanding {
  final String teamId;
  final String teamNome;
  final List<ChampionshipRaceScore> races;
  final int totalPoints;
  final int posizione;

  const ChampionshipTeamStanding({
    required this.teamId,
    required this.teamNome,
    required this.races,
    required this.totalPoints,
    required this.posizione,
  });
}

/// Classifica completa di campionato.
class ChampionshipStandings {
  final List<ChampionshipTeamStanding> teams;

  const ChampionshipStandings({required this.teams});
}
