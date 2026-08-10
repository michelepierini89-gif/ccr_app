import 'package:latlong2/latlong.dart';
import '../utils/location_utils.dart';
import 'special_model.dart';
import 'waypoint_model.dart';

/// Percorso alternativo per evento (Fix percorso B, 10/08/2026) — raccoglie
/// tutto ciò che definisce UN percorso: tracciato, speciali con checkpoint,
/// punti pericolo, zone a velocità controllata, punto ristoro.
///
/// Solo la variante B è rappresentata da un'istanza di questa classe dentro
/// [EventModel] (`routeB`, opzionale): la variante A resta sui campi diretti
/// di [EventModel] (rinominati con suffisso `RouteA`) per non richiedere
/// nessuna migrazione dei documenti Firestore esistenti — vedi
/// `EventModel.routeAAsVariant` per una vista di sola lettura della
/// variante A nella stessa forma, utile per riusare la UI in modo simmetrico
/// tra A e B (es. riepilogo diff all'attivazione, Parte 3).
class RouteVariantModel {
  final String id; // 'A' | 'B'
  final String label;
  final String? trackUrl;
  final List<SpecialModel> speciali;
  final List<DangerPointModel> dangerPoints;
  final List<SpeedZoneModel> speedZones;
  final WaypointModel? fuelPoint;

  const RouteVariantModel({
    required this.id,
    required this.label,
    this.trackUrl,
    this.speciali = const [],
    this.dangerPoints = const [],
    this.speedZones = const [],
    this.fuelPoint,
  });

  factory RouteVariantModel.fromMap(String id, Map<String, dynamic> m) =>
      RouteVariantModel(
        id: id,
        label: m['label'] as String? ??
            (id == 'B' ? 'Percorso alternativo' : 'Percorso principale'),
        trackUrl: m['trackUrl'] as String?,
        speciali: (m['speciali'] as List<dynamic>? ?? [])
            .map((e) => SpecialModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        dangerPoints: (m['dangerPoints'] as List<dynamic>? ?? [])
            .map((e) => DangerPointModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        speedZones: (m['speedZones'] as List<dynamic>? ?? [])
            .map((e) => SpeedZoneModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        fuelPoint: m['fuelPoint'] != null
            ? WaypointModel.fromMap(m['fuelPoint'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'trackUrl': trackUrl,
        'speciali': speciali.map((s) => s.toMap()).toList(),
        'dangerPoints': dangerPoints.map((d) => d.toMap()).toList(),
        'speedZones': speedZones.map((z) => z.toMap()).toList(),
        'fuelPoint': fuelPoint?.toMap(),
      };

  RouteVariantModel copyWith({
    String? label,
    String? trackUrl,
    bool clearTrackUrl = false,
    List<SpecialModel>? speciali,
    List<DangerPointModel>? dangerPoints,
    List<SpeedZoneModel>? speedZones,
    WaypointModel? fuelPoint,
    bool clearFuelPoint = false,
  }) =>
      RouteVariantModel(
        id: id,
        label: label ?? this.label,
        trackUrl: clearTrackUrl ? null : (trackUrl ?? this.trackUrl),
        speciali: speciali ?? this.speciali,
        dangerPoints: dangerPoints ?? this.dangerPoints,
        speedZones: speedZones ?? this.speedZones,
        fuelPoint: clearFuelPoint ? null : (fuelPoint ?? this.fuelPoint),
      );

  /// Lunghezza totale in km del tracciato di questa variante, calcolata
  /// (mai persistita) su [trackPoints] già caricati da Storage — stesso
  /// algoritmo Haversine già in uso in `event_management_screen.dart` e
  /// `specials_editor_screen.dart` prima di questo fix, ora centralizzato
  /// qui invece che duplicato.
  double totalLengthKm(List<LatLng> trackPoints) {
    if (trackPoints.length < 2) return 0;
    var totalMeters = 0.0;
    for (var i = 1; i < trackPoints.length; i++) {
      totalMeters += LocationUtils.haversineDistance(
        trackPoints[i - 1].latitude,
        trackPoints[i - 1].longitude,
        trackPoints[i].latitude,
        trackPoints[i].longitude,
      );
    }
    return totalMeters / 1000.0;
  }

  /// Speciali non annullate — usato dai riepiloghi (Parte 3: diff
  /// all'attivazione) per non contare le speciali che l'admin ha annullato.
  int get specialiAttiveCount => speciali.where((s) => !s.annullata).length;
}
