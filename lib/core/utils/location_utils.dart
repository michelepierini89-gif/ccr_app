import 'dart:math';

class LocationUtils {
  LocationUtils._();

  static double haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLambda = (lng2 - lng1) * pi / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Bearing iniziale (0-360°, 0=Nord) lungo il grande cerchio da
  /// (lat1,lng1) a (lat2,lng2).
  static double bearingDegrees(
      double lat1, double lng1, double lat2, double lng2) {
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dLambda = (lng2 - lng1) * pi / 180;
    final y = sin(dLambda) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda);
    final theta = atan2(y, x);
    return (theta * 180 / pi + 360) % 360;
  }

  /// Punto di destinazione a [distanceM] metri da (lat,lng) lungo il
  /// bearing [bearingDeg] (0=Nord). Ritorna `[lat, lng]`.
  static List<double> destinationPoint(
      double lat, double lng, double bearingDeg, double distanceM) {
    const r = 6371000.0;
    final delta = distanceM / r;
    final theta = bearingDeg * pi / 180;
    final phi1 = lat * pi / 180;
    final lambda1 = lng * pi / 180;
    final phi2 = asin(
        sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta));
    final lambda2 = lambda1 +
        atan2(sin(theta) * sin(delta) * cos(phi1),
            cos(delta) - sin(phi1) * sin(phi2));
    return [phi2 * 180 / pi, lambda2 * 180 / pi];
  }

  /// Proietta (lat,lng) in coordinate locali in metri (est, nord) rispetto
  /// a un'origine (originLat,originLng), con approssimazione
  /// equirettangolare — valida su distanze di poche decine di metri come
  /// quelle delle porte virtuali. Ritorna `[est, nord]`.
  static List<double> toLocalMeters(
      double originLat, double originLng, double lat, double lng) {
    const r = 6371000.0;
    final east =
        (lng - originLng) * pi / 180 * r * cos(originLat * pi / 180);
    final north = (lat - originLat) * pi / 180 * r;
    return [east, north];
  }

  /// Distanza minima (metri) tra (pointLat,pointLng) e il SEGMENTO
  /// [aLat,aLng]->[bLat,bLng] — non solo tra il punto e i suoi estremi.
  /// Proietta tutto in coordinate locali (vedi [toLocalMeters]) centrate su
  /// A, calcola la proiezione perpendicolare del punto sul segmento e la
  /// clampa a [0,1] se cade fuori dagli estremi (Fix 1, checkpoint su
  /// traiettoria — 09/08/2026).
  static double distanceToSegmentMeters(
    double pointLat,
    double pointLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final p = toLocalMeters(aLat, aLng, pointLat, pointLng);
    final b = toLocalMeters(aLat, aLng, bLat, bLng);
    final abx = b[0], aby = b[1];
    final apx = p[0], apy = p[1];
    final abLenSq = abx * abx + aby * aby;
    if (abLenSq < 1e-9) {
      // A e B coincidono: la distanza è semplicemente quella dal punto A.
      return sqrt(apx * apx + apy * apy);
    }
    var t = (apx * abx + apy * aby) / abLenSq;
    t = t.clamp(0.0, 1.0);
    final closestX = abx * t;
    final closestY = aby * t;
    final dx = apx - closestX;
    final dy = apy - closestY;
    return sqrt(dx * dx + dy * dy);
  }

  static String formatTimestamp(DateTime dt) {
    final ms = dt.millisecondsSinceEpoch % 1000;
    final tenths = (ms / 100).floor();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss.$tenths';
  }

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
