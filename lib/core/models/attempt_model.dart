import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Step 47, Parte 2B — un tentativo di un pilota su un evento di
/// allenamento: sessione completa e indipendente (propria traccia, propri
/// tempi, propri checkpoint/penalità), mai un documento condiviso con gli
/// altri tentativi. Path Firestore:
/// `tracking/{eventId}/pilots/{userId}/attempts/{attemptId}`, con
/// `fullTrackChunks`/`passages`/`speedZoneViolations` annidati sotto —
/// stesso meccanismo a chunk già in uso per gli eventi di gara, solo
/// scoperto per tentativo invece che per pilota.
enum AttemptStatus { inProgress, completed, abandoned }

class AttemptModel {
  final String id;
  final String eventId;
  final String userId;

  /// 1-based, per la UI ("Tentativo 3") — assegnato in ordine di
  /// creazione, mai riassegnato.
  final int attemptNumber;
  final AttemptStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? routeVariantId;

  /// Solo lat/lng (replay polyline) — la traccia completa con
  /// accuracy/timestamp vive in `fullTrackChunks` (vedi
  /// `FirestoreService.getFullAttemptTrack`), stesso schema di
  /// `EventModel`/gara.
  final List<LatLng> pilotTrack;

  const AttemptModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.attemptNumber,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.routeVariantId,
    this.pilotTrack = const [],
  });

  factory AttemptModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AttemptModel(
      id: doc.id,
      eventId: d['eventId'] ?? '',
      userId: d['userId'] ?? '',
      attemptNumber: (d['attemptNumber'] as num?)?.toInt() ?? 1,
      status: AttemptStatus.values.firstWhere(
        (s) => s.name == (d['status'] ?? 'inProgress'),
        orElse: () => AttemptStatus.inProgress,
      ),
      startedAt: (d['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      finishedAt: (d['finishedAt'] as Timestamp?)?.toDate(),
      routeVariantId: d['routeVariantId'] as String?,
      pilotTrack: (d['pilotTrack'] as List<dynamic>? ?? [])
          .map((e) => LatLng(
              (e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'eventId': eventId,
        'userId': userId,
        'attemptNumber': attemptNumber,
        'status': AttemptStatus.inProgress.name,
        'startedAt': Timestamp.fromDate(startedAt),
      };

  bool get isInProgress => status == AttemptStatus.inProgress;

  Duration? get durata => finishedAt?.difference(startedAt);
}
