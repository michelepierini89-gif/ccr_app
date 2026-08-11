import 'package:cloud_firestore/cloud_firestore.dart';

enum CpDisputeStatus { pending, accepted, rejected }

/// Riferimento a un checkpoint mancato segnalato dal pilota, con tutto il
/// necessario per la risoluzione admin (recordWaypointPassage diretto sul
/// CP, senza dover ri-risolvere posizione → id tramite l'EventModel).
///
/// Step 42 — selezione granulare: ogni voce ha ora uno stato indipendente
/// ([status]), una nota facoltativa del pilota specifica per quel CP
/// ([pilotNote]), la distanza minima rilevata tra la traccia e il punto al
/// momento della segnalazione ([distanceMeters], solo informativa per il
/// pilota/admin) e la motivazione della decisione admin
/// ([decisionReason]). Prima di questo Step l'intera segnalazione aveva un
/// unico stato: vedi [CpDisputeModel.fromFirestore] per la
/// retrocompatibilità con le dispute già su Firestore in quel formato.
class DisputedCp {
  final String specialeId;
  final String specialeNome;
  final String cpId;
  final String cpNome;
  final int position;
  final double? distanceMeters;
  final String? pilotNote;
  final CpDisputeStatus status;
  final String? decisionReason;

  const DisputedCp({
    required this.specialeId,
    required this.specialeNome,
    required this.cpId,
    required this.cpNome,
    required this.position,
    this.distanceMeters,
    this.pilotNote,
    this.status = CpDisputeStatus.pending,
    this.decisionReason,
  });

  /// [legacyStatus] è lo stato dell'intera dispute pre-Step 42, usato come
  /// fallback quando la voce non ha un proprio campo 'status' (documento
  /// scritto prima di questo Step).
  factory DisputedCp.fromMap(Map<String, dynamic> m,
          {CpDisputeStatus legacyStatus = CpDisputeStatus.pending}) =>
      DisputedCp(
        specialeId: m['specialeId'] ?? '',
        specialeNome: m['specialeNome'] ?? '',
        cpId: m['cpId'] ?? '',
        cpNome: m['cpNome'] ?? '',
        position: (m['position'] as num?)?.toInt() ?? 0,
        distanceMeters: (m['distanceMeters'] as num?)?.toDouble(),
        pilotNote: m['pilotNote'] as String?,
        status: m['status'] != null
            ? CpDisputeStatus.values.firstWhere(
                (s) => s.name == m['status'],
                orElse: () => legacyStatus,
              )
            : legacyStatus,
        decisionReason: m['decisionReason'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'specialeId': specialeId,
        'specialeNome': specialeNome,
        'cpId': cpId,
        'cpNome': cpNome,
        'position': position,
        if (distanceMeters != null) 'distanceMeters': distanceMeters,
        if (pilotNote != null) 'pilotNote': pilotNote,
        'status': status.name,
        if (decisionReason != null) 'decisionReason': decisionReason,
      };

  DisputedCp copyWith({
    CpDisputeStatus? status,
    String? decisionReason,
  }) =>
      DisputedCp(
        specialeId: specialeId,
        specialeNome: specialeNome,
        cpId: cpId,
        cpNome: cpNome,
        position: position,
        distanceMeters: distanceMeters,
        pilotNote: pilotNote,
        status: status ?? this.status,
        decisionReason: decisionReason ?? this.decisionReason,
      );
}

/// Segnalazione di un pilota che contesta uno o più CP rilevati come
/// mancati durante la gara, in attesa di verifica admin. Ogni voce di
/// [missedCps] porta il proprio stato indipendente (Step 42) — non esiste
/// più uno stato unico per l'intera segnalazione, se non come riepilogo
/// derivato (vedi [allAccepted]/[allRejected]/[hasPending]).
class CpDisputeModel {
  final String id;
  final String eventId;
  final String pilotId;
  final String pilotName;
  final String teamName;
  final List<DisputedCp> missedCps;
  final String? pilotNote;
  final DateTime timestamp;

  const CpDisputeModel({
    required this.id,
    required this.eventId,
    required this.pilotId,
    required this.pilotName,
    required this.teamName,
    required this.missedCps,
    this.pilotNote,
    required this.timestamp,
  });

  bool get hasPending =>
      missedCps.any((c) => c.status == CpDisputeStatus.pending);
  bool get allAccepted =>
      missedCps.isNotEmpty &&
      missedCps.every((c) => c.status == CpDisputeStatus.accepted);
  bool get allRejected =>
      missedCps.isNotEmpty &&
      missedCps.every((c) => c.status == CpDisputeStatus.rejected);
  int get acceptedCount =>
      missedCps.where((c) => c.status == CpDisputeStatus.accepted).length;
  int get rejectedCount =>
      missedCps.where((c) => c.status == CpDisputeStatus.rejected).length;

  factory CpDisputeModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    // Retrocompatibilità: documenti scritti prima dello Step 42 hanno un
    // solo campo 'status' a livello di dispute, mai sulle singole voci di
    // missedCps — diventa il fallback per ogni voce priva del proprio.
    final legacyStatus = CpDisputeStatus.values.firstWhere(
      (s) => s.name == d['status'],
      orElse: () => CpDisputeStatus.pending,
    );
    return CpDisputeModel(
      id: doc.id,
      eventId: d['eventId'] ?? '',
      pilotId: d['pilotId'] ?? '',
      pilotName: d['pilotName'] ?? '',
      teamName: d['teamName'] ?? '',
      missedCps: (d['missedCps'] as List<dynamic>? ?? [])
          .map((m) => DisputedCp.fromMap(m as Map<String, dynamic>,
              legacyStatus: legacyStatus))
          .toList(),
      pilotNote: d['pilotNote'] as String?,
      timestamp: (d['timestamp'] as Timestamp).toDate(),
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
        // Riepilogo per compatibilità con eventuali letture esterne/vecchie
        // versioni dell'app — mai più la fonte di verità, quella sono le
        // singole voci in missedCps.
        'status': allAccepted
            ? CpDisputeStatus.accepted.name
            : allRejected
                ? CpDisputeStatus.rejected.name
                : CpDisputeStatus.pending.name,
      };
}
