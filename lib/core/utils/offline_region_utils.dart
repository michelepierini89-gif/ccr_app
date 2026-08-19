import 'package:latlong2/latlong.dart';

import '../models/event_model.dart';

/// Estratta da `offline_maps_screen.dart` (Step 49) per essere testabile
/// senza montare il widget: con la cache che fino allo Step 49 non veniva
/// mai letta a runtime, questa logica non era mai stata verificata sul
/// campo nonostante fosse lì dal 10/08.
class OfflineRegionUtils {
  OfflineRegionUtils._();

  /// Bounding box (SW, NE) con 10 km di margine attorno a tutti i waypoint
  /// (inizio/fine PS + CP) di un evento — copre SEMPRE l'unione di
  /// ENTRAMBE le varianti di percorso (non solo quella attiva): il cambio
  /// di percorso può avvenire quando il pilota è già senza connessione,
  /// quindi le mappe scaricate devono coprire anche il percorso che
  /// potrebbe diventare attivo dopo.
  static (LatLng, LatLng)? eventBoundingBox(EventModel event) {
    final lats = <double>[];
    final lons = <double>[];
    final variants = [
      event.routeAAsVariant,
      if (event.routeB != null) event.routeB!,
    ];
    for (final variant in variants) {
      for (final s in variant.speciali) {
        if (s.annullata) continue;
        lats.addAll([s.waypointInizio.lat, s.waypointFine.lat]);
        lons.addAll([s.waypointInizio.lng, s.waypointFine.lng]);
        for (final cp in s.controlPoints) {
          lats.add(cp.lat);
          lons.add(cp.lng);
        }
      }
    }
    if (lats.isEmpty) return null;
    const pad = 0.09; // ~10 km
    final sw = LatLng(
        lats.reduce((a, b) => a < b ? a : b) - pad,
        lons.reduce((a, b) => a < b ? a : b) - pad);
    final ne = LatLng(
        lats.reduce((a, b) => a > b ? a : b) + pad,
        lons.reduce((a, b) => a > b ? a : b) + pad);
    return (sw, ne);
  }
}
