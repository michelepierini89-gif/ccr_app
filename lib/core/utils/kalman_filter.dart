import 'package:latlong2/latlong.dart';

/// 4D kinematic Kalman filter: state = [lat, lng, vLat, vLng]
/// (vLat/vLng in degrees/second). Models constant-velocity motion so the
/// filter "knows" the device is moving and resists jumps incoherent with
/// the current velocity — unlike a 1D position-only filter, which with a
/// typical 2m accuracy collapses to a near-1.0 gain (pure passthrough).
///
/// All quantities are kept in degrees; GPS accuracy (meters) is converted
/// to degrees before computing the measurement noise R = (accuracy/111111)².
///
/// The filter resets automatically when the gap between consecutive points
/// exceeds 10 seconds (e.g. after signal loss or a new recording session).
class GpsKalmanFilter {
  /// Process-noise acceleration in m/s². Higher values let the filter
  /// track faster direction/speed changes at the cost of more smoothing lag.
  final double sigmaAccel;

  /// Tuned for motorcycle/enduro use: tolerates the rapid accel/decel and
  /// direction changes typical off-road, while still smoothing urban multipath.
  static const double kSigmaAccelMotorcycle = 3.0;

  GpsKalmanFilter({this.sigmaAccel = 1.0});

  List<double>? _state; // [lat, lng, vLat, vLng]
  List<List<double>>? _p; // 4x4 covariance
  DateTime? _lastTs;

  /// Returns the Kalman-filtered [LatLng] for the given raw GPS sample.
  LatLng filter(double lat, double lng, double accuracyM, DateTime ts) {
    if (_state == null || ts.difference(_lastTs!).inSeconds > 10) {
      _initState(lat, lng, accuracyM);
      _lastTs = ts;
      return LatLng(lat, lng);
    }

    final dt = ts.difference(_lastTs!).inMilliseconds / 1000.0;
    _lastTs = ts;
    _predict(dt);
    _update(lat, lng, accuracyM);
    return LatLng(_state![0], _state![1]);
  }

  void reset() {
    _state = null;
    _p = null;
    _lastTs = null;
  }

  void _initState(double lat, double lng, double accuracyM) {
    final r = _measurementNoise(accuracyM);
    _state = [lat, lng, 0.0, 0.0];
    _p = [
      [r, 0.0, 0.0, 0.0],
      [0.0, r, 0.0, 0.0],
      [0.0, 0.0, r, 0.0],
      [0.0, 0.0, 0.0, r],
    ];
  }

  void _predict(double dt) {
    final f = [
      [1.0, 0.0, dt, 0.0],
      [0.0, 1.0, 0.0, dt],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
    ];

    // Process noise Q, derived from a constant-acceleration model.
    final saDeg = sigmaAccel / 111111.0; // m/s² -> deg/s²
    final sa2 = saDeg * saDeg;
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt3 * dt;

    final q = List.generate(4, (_) => List.filled(4, 0.0));
    q[0][0] = sa2 * dt4 / 4;
    q[1][1] = sa2 * dt4 / 4;
    q[0][2] = q[2][0] = sa2 * dt3 / 2;
    q[1][3] = q[3][1] = sa2 * dt3 / 2;
    q[2][2] = sa2 * dt2;
    q[3][3] = sa2 * dt2;

    final predictedState = _matVec(f, _state!);
    final fp = _matMul(f, _p!);
    final fpft = _matMul(fp, _transpose(f));

    _state = predictedState;
    _p = _matAdd(fpft, q);
  }

  void _update(double lat, double lng, double accuracyM) {
    final r = _measurementNoise(accuracyM);
    final h = [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
    ];
    final z = [lat, lng];

    final hx = _matVec(h, _state!);
    final y = [z[0] - hx[0], z[1] - hx[1]]; // innovation

    final pht = _matMul(_p!, _transpose(h)); // 4x2
    final hpht = _matMul(h, pht); // 2x2
    final s = [
      [hpht[0][0] + r, hpht[0][1]],
      [hpht[1][0], hpht[1][1] + r],
    ];
    final sInv = _inverse2x2(s);
    final k = _matMul(pht, sInv); // 4x2 Kalman gain

    final ky = _matVec(k, y);
    for (var i = 0; i < 4; i++) {
      _state![i] += ky[i];
    }

    // P = (I - K*H) * P
    final kh = _matMul(k, h); // 4x4
    final ikh = List.generate(
        4, (i) => List.generate(4, (j) => (i == j ? 1.0 : 0.0) - kh[i][j]));
    _p = _matMul(ikh, _p!);
  }

  // Converts accuracy (meters) to degrees² for consistent units.
  static double _measurementNoise(double accuracyM) {
    final d = accuracyM / 111111.0;
    return d * d;
  }

  // ── Matrix helpers (small fixed-size matrices, no external dependency) ──

  static List<double> _matVec(List<List<double>> m, List<double> v) {
    return List.generate(m.length, (i) {
      var sum = 0.0;
      for (var j = 0; j < v.length; j++) {
        sum += m[i][j] * v[j];
      }
      return sum;
    });
  }

  static List<List<double>> _matMul(
      List<List<double>> a, List<List<double>> b) {
    final rows = a.length, cols = b[0].length, inner = b.length;
    return List.generate(
        rows,
        (i) => List.generate(cols, (j) {
              var sum = 0.0;
              for (var k = 0; k < inner; k++) {
                sum += a[i][k] * b[k][j];
              }
              return sum;
            }));
  }

  static List<List<double>> _transpose(List<List<double>> m) {
    final rows = m.length, cols = m[0].length;
    return List.generate(cols, (i) => List.generate(rows, (j) => m[j][i]));
  }

  static List<List<double>> _matAdd(
      List<List<double>> a, List<List<double>> b) {
    return List.generate(
        a.length, (i) => List.generate(a[i].length, (j) => a[i][j] + b[i][j]));
  }

  static List<List<double>> _inverse2x2(List<List<double>> m) {
    final det = m[0][0] * m[1][1] - m[0][1] * m[1][0];
    final invDet = det.abs() < 1e-30 ? 0.0 : 1.0 / det;
    return [
      [m[1][1] * invDet, -m[0][1] * invDet],
      [-m[1][0] * invDet, m[0][0] * invDet],
    ];
  }
}
