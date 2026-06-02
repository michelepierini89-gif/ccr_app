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
  });

  factory GpsPointModel.fromFirestore(DocumentSnapshot doc, String eventId) {
    final d = doc.data() as Map<String, dynamic>;
    return GpsPointModel(
      userId: doc.id,
      eventId: eventId,
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      accuracy: (d['accuracy'] as num?)?.toDouble() ?? 0,
      speed: (d['speed'] as num?)?.toDouble(),
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      specialeId: d['specialeId'],
      waypointPassati: List<String>.from(d['waypointPassati'] ?? []),
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
