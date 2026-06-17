import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../utils/location_utils.dart';

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

/// Zona a velocità controllata interna a una prova speciale: il pilota deve
/// mantenere una velocità media sotto [maxSpeedKmh] tra il punto di inizio e
/// quello di fine. Il superamento genera una penalità sul tempo della PS
/// (vedi [PenaltySettingsModel.speedZonePenaltySeconds]), visibile solo
/// all'admin in classifica — il pilota non viene avvisato durante la guida.
class SpeedZoneModel {
  final String id;
  final String nome;
  final String specialeId;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final double maxSpeedKmh;

  const SpeedZoneModel({
    required this.id,
    required this.nome,
    required this.specialeId,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.maxSpeedKmh,
  });

  LatLng get startLatLng => LatLng(startLat, startLng);
  LatLng get endLatLng => LatLng(endLat, endLng);

  /// Lunghezza in linea d'aria tra inizio e fine zona (stessa precisione
  /// usata per le soglie di prossimità di punti pericolo/ristoro).
  double get lengthMeters =>
      LocationUtils.haversineDistance(startLat, startLng, endLat, endLng);

  factory SpeedZoneModel.fromMap(Map<String, dynamic> m) => SpeedZoneModel(
        id: m['id'] ?? '',
        nome: m['nome'] ?? '',
        specialeId: m['specialeId'] ?? '',
        startLat: (m['startLat'] as num).toDouble(),
        startLng: (m['startLng'] as num).toDouble(),
        endLat: (m['endLat'] as num).toDouble(),
        endLng: (m['endLng'] as num).toDouble(),
        maxSpeedKmh: (m['maxSpeedKmh'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'specialeId': specialeId,
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'maxSpeedKmh': maxSpeedKmh,
      };

  SpeedZoneModel copyWith({
    String? nome,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    double? maxSpeedKmh,
  }) =>
      SpeedZoneModel(
        id: id,
        nome: nome ?? this.nome,
        specialeId: specialeId,
        startLat: startLat ?? this.startLat,
        startLng: startLng ?? this.startLng,
        endLat: endLat ?? this.endLat,
        endLng: endLng ?? this.endLng,
        maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
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
