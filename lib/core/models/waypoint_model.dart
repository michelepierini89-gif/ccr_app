import 'package:latlong2/latlong.dart';

enum WaypointType { inizio, fine, intermedio }

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
