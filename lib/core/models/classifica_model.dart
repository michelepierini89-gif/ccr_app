import 'package:cloud_firestore/cloud_firestore.dart';

class WaypointPassageRecord {
  final String id;
  final String userId;
  final String waypointId;
  final String waypointNome;
  final DateTime timestamp;

  const WaypointPassageRecord({
    required this.id,
    required this.userId,
    required this.waypointId,
    required this.waypointNome,
    required this.timestamp,
  });

  factory WaypointPassageRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WaypointPassageRecord(
      id: doc.id,
      userId: d['userId'] ?? '',
      waypointId: d['waypointId'] ?? '',
      waypointNome: d['waypointNome'] ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class SpecialTempo {
  final String specialeId;
  final String specialeNome;
  final int ordine;
  final Duration tempo;       // include già la penalità CP
  final bool controlPointsOk;
  final List<int> missedCpPositions; // 1-based positions of missed control points
  final int penaltySeconds;          // secondi di penalità CP aggiunti

  const SpecialTempo({
    required this.specialeId,
    required this.specialeNome,
    required this.ordine,
    required this.tempo,
    required this.controlPointsOk,
    this.missedCpPositions = const [],
    this.penaltySeconds = 0,
  });

  String get tempoFormatted {
    final m = tempo.inMinutes;
    final s = tempo.inSeconds % 60;
    final cs = (tempo.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }
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
