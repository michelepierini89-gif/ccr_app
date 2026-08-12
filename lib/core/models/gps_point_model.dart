import 'package:cloud_firestore/cloud_firestore.dart';

class GpsPointModel {
  final String userId;
  final String eventId;
  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final DateTime timestamp;
  final String? specialeId;
  final List<String> waypointPassati;
  final String raceStatus;
  final String? retiredReason;
  // Fix (bug test 18/08, "Carring CLO 3") — un pilota il cui documento di
  // tracking non ha ancora alcun fix GPS (es. gara conclusa entro pochi
  // secondi dall'avvio, vedi race_session_guard.dart) non ha i campi
  // `lat`/`lng` affatto: prima di questo fix il cast diretto `as num`
  // lanciava un `TypeError` non gestito che abbatteva l'intera schermata
  // Live admin (riprodotto esattamente dal documento reale di quel
  // pilota). Distingue questo caso da un vero fix a (0,0), così i
  // chiamanti possono scegliere di non disegnare il marker invece di
  // piazzarlo silenziosamente al largo dell'Africa.
  final bool hasPosition;

  const GpsPointModel({
    required this.userId,
    required this.eventId,
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.speed,
    required this.timestamp,
    this.specialeId,
    required this.waypointPassati,
    this.raceStatus = 'not_started',
    this.retiredReason,
    this.hasPosition = true,
  });

  factory GpsPointModel.fromFirestore(DocumentSnapshot doc, String eventId) {
    final d = doc.data() as Map<String, dynamic>;
    final rawLat = d['lat'] as num?;
    final rawLng = d['lng'] as num?;
    return GpsPointModel(
      userId: doc.id,
      eventId: eventId,
      lat: rawLat?.toDouble() ?? 0.0,
      lng: rawLng?.toDouble() ?? 0.0,
      hasPosition: rawLat != null && rawLng != null,
      accuracy: (d['accuracy'] as num?)?.toDouble() ?? 0,
      speed: (d['speed'] as num?)?.toDouble(),
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      specialeId: d['specialeId'],
      waypointPassati: List<String>.from(d['waypointPassati'] ?? []),
      raceStatus: d['raceStatus'] as String? ?? 'not_started',
      retiredReason: d['retiredReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'speed': speed,
        'timestamp': Timestamp.fromDate(timestamp),
        'specialeId': specialeId,
        'waypointPassati': waypointPassati,
      };
}
