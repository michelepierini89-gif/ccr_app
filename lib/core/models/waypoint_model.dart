import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

enum WaypointType { inizio, fine, intermedio }

class DangerPointModel {
  final String id;
  final double latitude;
  final double longitude;
  final String comment;
  final DateTime createdAt;

  const DangerPointModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.comment,
    required this.createdAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory DangerPointModel.fromMap(Map<String, dynamic> m) => DangerPointModel(
        id: m['id'] ?? '',
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        comment: m['comment'] ?? '',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'comment': comment,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  DangerPointModel copyWith({
    double? latitude,
    double? longitude,
    String? comment,
  }) =>
      DangerPointModel(
        id: id,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        comment: comment ?? this.comment,
        createdAt: createdAt,
      );
}

class WaypointModel {
  final String id;
  final String nome;
  final double lat;
  final double lng;
  final WaypointType type;

  const WaypointModel({
    required this.id,
    required this.nome,
    required this.lat,
    required this.lng,
    required this.type,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory WaypointModel.fromMap(Map<String, dynamic> m) => WaypointModel(
        id: m['id'] ?? '',
        nome: m['nome'] ?? '',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        type: WaypointType.values.firstWhere(
          (e) => e.name == (m['type'] ?? 'intermedio'),
          orElse: () => WaypointType.intermedio,
        ),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'lat': lat,
        'lng': lng,
        'type': type.name,
      };
}
