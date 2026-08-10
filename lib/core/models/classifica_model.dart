import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/time_format_utils.dart';
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
  // Precisione del rilevamento: 'gate' (porta virtuale + interpolazione),
  // 'radius' (raggio) o 'recovery' (recovery retroattivo/forfeit). Vedi
  // GpsService/WaypointDetector — usato solo per il badge discreto in
  // TimingScreen (admin).
  final String timingMethod;

  const WaypointPassageRecord({
    required this.id,
    required this.userId,
    required this.waypointId,
    required this.waypointNome,
    required this.timestamp,
    this.timingError,
    this.timingMethod = 'radius',
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
      timingMethod: d['timingMethod'] as String? ?? 'radius',
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

/// Tempo ufficiale di una PS per un pilota, ricalcolato post-gara
/// (Blocco B: TrackSmoother RTS + rilevamento porte virtuali sulla
/// traccia smussata) — vedi `tracking/{eventId}/officialTimes/{userId}`.
/// Separato dai tempi live: la classifica lo usa se presente, altrimenti
/// ricade sul tempo netto calcolato dai passaggi live.
class OfficialSpecialTime {
  final int durationMs;
  final String timingMethod; // peggiore tra inizio/fine ('gate'/'radius')

  const OfficialSpecialTime({
    required this.durationMs,
    required this.timingMethod,
  });

  Map<String, dynamic> toMap() => {
        'durationMs': durationMs,
        'timingMethod': timingMethod,
      };

  factory OfficialSpecialTime.fromMap(Map<String, dynamic> m) =>
      OfficialSpecialTime(
        durationMs: (m['durationMs'] as num).toInt(),
        timingMethod: m['timingMethod'] as String? ?? 'radius',
      );
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
  final bool skipped; // pilota ha saltato volontariamente questa PS
  // Fix 3 (09/08/2026) — true se questa PS non ha un dato REALE (porta o
  // raggio) né per l'inizio né per la fine: GpsService non ha trovato
  // alcun punto GPS di supporto (timingMethod=='forfait' su almeno un
  // estremo), quindi [tempo] è la stima forfettaria (peggior tempo tra i
  // piloti + 30 minuti, PASSO 2 di ClassificaEngine.compute), MAI un
  // tempo interpolato da un dato inesistente. Distinto da [skipped] (salto
  // volontario esplicito): stessa formula di penalità, dicitura UI diversa.
  final bool notDetected;
  // Precisione del rilevamento di inizio/fine ('gate'/'radius'/'recovery'),
  // vedi WaypointPassageRecord.timingMethod — mostrato come badge discreto
  // solo lato admin in TimingScreen.
  final String startTimingMethod;
  final String endTimingMethod;
  // true se il tempo netto proviene dal ricalcolo ufficiale post-gara
  // (Blocco B) invece che dai passaggi live.
  final bool isOfficialTime;

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
    this.skipped = false,
    this.notDetected = false,
    this.speedZoneViolations = const [],
    this.speedZonePenaltySeconds = 0,
    this.startTimingMethod = 'radius',
    this.endTimingMethod = 'radius',
    this.isOfficialTime = false,
  });

  SpecialTempo copyWith({Duration? tempo, int? penaltySeconds}) => SpecialTempo(
        specialeId: specialeId,
        specialeNome: specialeNome,
        ordine: ordine,
        tempo: tempo ?? this.tempo,
        controlPointsOk: controlPointsOk,
        missedCpPositions: missedCpPositions,
        penaltySeconds: penaltySeconds ?? this.penaltySeconds,
        timingError: timingError,
        rawStartTime: rawStartTime,
        rawEndTime: rawEndTime,
        speedZoneViolations: speedZoneViolations,
        speedZonePenaltySeconds: speedZonePenaltySeconds,
        skipped: skipped,
        notDetected: notDetected,
        startTimingMethod: startTimingMethod,
        endTimingMethod: endTimingMethod,
        isOfficialTime: isOfficialTime,
      );

  String get tempoFormatted => TimeFormatUtils.formatRaceTime(tempo);

  /// Tempo PS calcolato da timestamp implausibili (es. recovery corrotto):
  /// non viene mostrato, sostituito dalla penalità massima.
  bool get isInvalidTiming => timingError == 'rilevamento_non_valido';

  /// Tempo PS calcolato ma con affidabilità ridotta (fine speciale non
  /// rilevata, chiusa con stima di recovery REALE — dati GPS effettivamente
  /// presenti — o forzata da FINE GARA): il tempo resta visibile, ma va
  /// segnalato all'admin per un'eventuale penalità manuale. Fix 3 — esclude
  /// [skipped] e [notDetected], che hanno la propria dicitura dedicata e
  /// non un tempo calcolato da dati reali.
  bool get hasTimingWarning =>
      timingError != null && !isInvalidTiming && !skipped && !notDetected;
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
  // Percorso alternativo (10/08/2026, Parte 5) — variante ('A'/'B') con cui
  // questa entry ha corso, risolta dal campo `routeVariantId` scritto sul
  // tracking di ciascun pilota da GpsService.startRecording — MAI da
  // `event.activeRouteId`. [mixedRouteVariants] è true solo nel caso
  // anomalo (errore di gestione admin) in cui i membri della stessa
  // squadra abbiano corso su varianti diverse: le classifiche non sarebbero
  // confrontabili, va segnalato in UI (TimingScreen admin).
  final String routeIdUsed;
  final bool mixedRouteVariants;

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
    this.routeIdUsed = 'A',
    this.mixedRouteVariants = false,
  });

  bool get hasFinished => specialiCompletati.length == totaleSpeciali;
  bool get hasStarted => specialiCompletati.isNotEmpty || isLive;

  String get tempoTotaleFormatted {
    if (tempoTotale == Duration.zero) return '--:--.--';
    return TimeFormatUtils.formatRaceTime(tempoTotale);
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
