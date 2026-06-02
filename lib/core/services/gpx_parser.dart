import 'package:gpx/gpx.dart' as gpx_pkg;
import 'package:latlong2/latlong.dart';
import '../models/waypoint_model.dart';

class ParsedTrack {
  final List<LatLng> points;
  final List<WaypointModel> waypoints;
  ParsedTrack({required this.points, required this.waypoints});
}

class GpxParser {
  GpxParser._();

  static ParsedTrack parseGpx(String content) {
    final reader = gpx_pkg.GpxReader();
    final gpxData = reader.fromString(content);
    final points = <LatLng>[];
    for (final trk in gpxData.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat != null && pt.lon != null) {
            points.add(LatLng(pt.lat!, pt.lon!));
          }
        }
      }
    }
    final waypoints = <WaypointModel>[];
    for (int i = 0; i < gpxData.wpts.length; i++) {
      final wpt = gpxData.wpts[i];
      if (wpt.lat != null && wpt.lon != null) {
        waypoints.add(WaypointModel(
          id: 'wpt_$i',
          nome: wpt.name ?? 'Waypoint ${i + 1}',
          lat: wpt.lat!,
          lng: wpt.lon!,
          type: WaypointType.intermedio,
        ));
      }
    }
    return ParsedTrack(points: points, waypoints: waypoints);
  }

  static ParsedTrack parseKml(String content) {
    final points = <LatLng>[];
    final waypoints = <WaypointModel>[];
    try {
      final coordRegex = RegExp(r'<coordinates>([\s\S]*?)</coordinates>');
      final matches = coordRegex.allMatches(content);
      for (final match in matches) {
        final raw = match.group(1)!.trim();
        for (final line in raw.split(RegExp(r'\s+'))) {
          final parts = line.split(',');
          if (parts.length >= 2) {
            final lng = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat != null && lng != null) points.add(LatLng(lat, lng));
          }
        }
      }
      final placemarkRegex = RegExp(r'<Placemark>([\s\S]*?)</Placemark>');
      int idx = 0;
      for (final pm in placemarkRegex.allMatches(content)) {
        final pmContent = pm.group(1)!;
        final nameMatch =
            RegExp(r'<name>(.*?)</name>').firstMatch(pmContent);
        final pointMatch = RegExp(
                r'<Point>[\s\S]*?<coordinates>(.*?)</coordinates>[\s\S]*?</Point>')
            .firstMatch(pmContent);
        if (nameMatch != null && pointMatch != null) {
          final parts = pointMatch.group(1)!.trim().split(',');
          if (parts.length >= 2) {
            final lng = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              waypoints.add(WaypointModel(
                id: 'kml_wpt_$idx',
                nome: nameMatch.group(1)!,
                lat: lat,
                lng: lng,
                type: WaypointType.intermedio,
              ));
              idx++;
            }
          }
        }
      }
    } catch (_) {}
    return ParsedTrack(points: points, waypoints: waypoints);
  }
}
