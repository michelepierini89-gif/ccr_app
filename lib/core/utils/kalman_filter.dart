import 'package:latlong2/latlong.dart';

class _K1D {
  double est; // position estimate in degrees
  double p; // error covariance in degrees²
  _K1D(this.est, this.p);
}

/// 1D Kalman filter applied independently to latitude and longitude.
///
/// All quantities are kept in degrees; GPS accuracy (meters) is converted
/// to degrees before computing the measurement noise R = (accuracy/111111)².
/// With processNoise = 1e-5 deg² the filter is responsive (K ≈ 1) and
/// correctly weights each measurement by its declared GPS accuracy:
/// lower accuracy → lower K → less pull toward the new sample.
///
/// The filter resets automatically when the gap between consecutive points
/// exceeds 10 seconds (e.g. after signal loss or a new recording session).
class GpsKalmanFilter {
  static const double _q = 1e-5; // process noise in degrees²

  _K1D? _lat;
  _K1D? _lng;
  DateTime? _lastTs;

  /// Returns the Kalman-filtered [LatLng] for the given raw GPS sample.
  LatLng filter(double lat, double lng, double accuracy, DateTime ts) {
    final r = _measurementNoise(accuracy);

    if (_lat == null || ts.difference(_lastTs!).inSeconds > 10) {
      _lat = _K1D(lat, r);
      _lng = _K1D(lng, r);
      _lastTs = ts;
      return LatLng(lat, lng);
    }

    _lastTs = ts;
    return LatLng(_step(_lat!, lat, r), _step(_lng!, lng, r));
  }

  double _step(_K1D s, double z, double r) {
    final pPred = s.p + _q;
    final k = pPred / (pPred + r);
    s.est += k * (z - s.est);
    s.p = (1.0 - k) * pPred;
    return s.est;
  }

  // Converts accuracy (meters) to degrees² for consistent units.
  static double _measurementNoise(double accuracyM) {
    final d = accuracyM / 111111.0;
    return d * d;
  }

  void reset() {
    _lat = null;
    _lng = null;
    _lastTs = null;
  }
}
