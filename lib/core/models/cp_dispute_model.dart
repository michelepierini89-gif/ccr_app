import 'package:cloud_firestore/cloud_firestore.dart';

enum CpDisputeStatus { pending, accepted, rejected }

/// Riferimento a un checkpoint mancato segnalato dal pilota, con tutto il
/// necessario per la risoluzione admin (recordWaypointPassage diretto sul
/// CP, senza dover ri-risolvere posizione → id tramite l'EventModel).
class DisputedCp {
  final String specialeId;
  final String specialeNome;
  final String cpId;
  final String cpNome;
  final int position;

  const DisputedCp({
    required this.specialeId,
    required this.specialeNome,
    required this.cpId,
    required this.cpNome,
    required this.position,
  });

  factory DisputedCp.fromMap(Map<String, dynamic> m) => DisputedCp(
        specialeId: m['specialeId'] ?? '',
        specialeNome: m['specialeNome'] ?? '',
        cpId: m['cpId'] ?? '',
        cpNome: m['cpNome'] ?? '',
        position: (m['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'specialeId': specialeId,
        'specialeNome': specialeNome,
        'cpId': cpId,
        'cpNome': cpNome,
        'position': position,
      };
}

/// Segnalazione di un pilota che contesta uno o più CP rilevati come
/// mancati durante la gara, in attesa di verifica admin.
class CpDisputeModel {
  final String id;
  final String eventId;
  final String pilotId;
  final String pilotName;
  final String teamName;
  final List<DisputedCp> missedCps;
  final String? pilotNote;
  final DateTime timestamp;
  final CpDisputeStatus status;

  const CpDisputeModel({
    required this.id,
    required this.eventId,
    required this.pilotId,
    required this.pilotName,
    required this.teamName,
    required this.missedCps,
    this.pilotNote,
    required this.timestamp,
    required this.status,
  });

  factory CpDisputeModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CpDisputeModel(
      id: doc.id,
      eventId: d['eventId'] ?? '',
      pilotId: d['pilotId'] ?? '',
      pilotName: d['pilotName'] ?? '',
      teamName: d['teamName'] ?? '',
      missedCps: (d['missedCps'] as List<dynamic>? ?? [])
          .map((m) => DisputedCp.fromMap(m as Map<String, dynamic>))
          .toList(),
      pilotNote: d['pilotNote'] as String?,
      timestamp: (d['timestamp'] as Timestamp).toDate(),
      status: CpDisputeStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => CpDisputeStatus.pending,
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'eventId': eventId,
        'pilotId': pilotId,
        'pilotName': pilotName,
        'teamName': teamName,
        'missedCps': missedCps.map((c) => c.toMap()).toList(),
        'pilotNote': pilotNote,
        'timestamp': Timestamp.fromDate(timestamp),
        'status': status.name,
      };
}
