import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../utils/kalman_filter.dart';

/// Campione grezzo di traccia GPS: posizione + accuracy dichiarata dal
/// chip + timestamp originale. Input di [TrackSmoother.smooth].
class RawTrackSample {
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime timestamp;

  const RawTrackSample({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
  });
}

/// Punto di traccia smussato: stessa posizione/timestamp semantica di
/// [RawTrackSample], ma con lat/lng ricalcolati dallo smoother RTS.
class SmoothedTrackPoint {
  final LatLng position;
  final DateTime timestamp;

  const SmoothedTrackPoint({required this.position, required this.timestamp});
}

/// Rauch-Tung-Striebel (RTS) smoother per il ricalcolo post-gara della
/// traccia GPS, sullo stesso modello cinematico 4D (stato
/// [lat, lng, vLat, vLng]) di [GpsKalmanFilter] usato in tempo reale.
///
/// Il filtro live è forward-only: ogni stima usa solo i punti passati.
/// A gara conclusa la traccia è intera, quindi un secondo passaggio
/// all'indietro (RTS) può correggere ogni stima anche coi dati futuri,
/// producendo una traiettoria sensibilmente più accurata — in particolare
/// nei tratti dove il filtro live aveva poca informazione (es. subito
/// dopo un gap di segnale, dove la stima forward-only è debole finché
/// non arrivano più campioni).
class TrackSmoother {
  TrackSmoother._();

  // Soglie di velocità geometrica (stesse di GpsService) per scegliere il
  // sigma di processo più adatto a ciascun tratto: cammino/fermo (poca
  // dinamica) vs enduro (accelerazioni/cambi direzione bruschi).
  static const double _kSpeedWalkingKmh = 10.0;
  static const double _kSpeedMediumKmh = 40.0;

  /// Smussa [samples] (in ordine temporale crescente) e ritorna una
  /// traiettoria della stessa lunghezza, con i timestamp originali
  /// invariati. Ritorna una lista vuota se [samples] è vuota; ritorna
  /// [samples] invariati (come singolo punto) se ce n'è solo uno.
  static List<SmoothedTrackPoint> smooth(List<RawTrackSample> samples) {
    final n = samples.length;
    if (n == 0) return [];
    if (n == 1) {
      return [
        SmoothedTrackPoint(
          position: LatLng(samples[0].lat, samples[0].lng),
          timestamp: samples[0].timestamp,
        ),
      ];
    }

    // ── Forward pass: Kalman standard, salvando ad ogni step lo stato e
    // la covarianza SIA predetti (pre-update) SIA aggiornati (post-update),
    // più la matrice di transizione F usata — tutti necessari al backward
    // pass RTS sotto.
    final predictedStates = <List<double>>[];
    final predictedCovs = <List<List<double>>>[];
    final filteredStates = <List<double>>[];
    final filteredCovs = <List<List<double>>>[];
    final transitions = <List<List<double>>>[];

    final r0 = _measurementNoise(samples[0].accuracy);
    filteredStates.add([samples[0].lat, samples[0].lng, 0.0, 0.0]);
    filteredCovs.add([
      [r0, 0.0, 0.0, 0.0],
      [0.0, r0, 0.0, 0.0],
      [0.0, 0.0, r0, 0.0],
      [0.0, 0.0, 0.0, r0],
    ]);
    // Placeholder per l'indice 0 (nessuna predizione al primo campione):
    // mai letti dal backward pass, che parte da k = n-2.
    predictedStates.add(filteredStates[0]);
    predictedCovs.add(filteredCovs[0]);
    transitions.add(_identity4());

    for (var k = 1; k < n; k++) {
      final dtSec =
          samples[k].timestamp.difference(samples[k - 1].timestamp).inMilliseconds /
              1000.0;
      // Clamp: dt<=0 (timestamp duplicati/non ordinati) userebbe una F
      // degenere; dt enorme (pausa lunghissima) farebbe esplodere Q
      // (scala con dt^4) senza guadagno informativo reale.
      final dt = dtSec.clamp(0.05, 30.0);

      final speedKmh = _geometricSpeedKmh(samples[k - 1], samples[k], dtSec);
      final sigmaAccel = speedKmh < _kSpeedWalkingKmh
          ? GpsKalmanFilter.kSigmaAccelWalking
          : speedKmh < _kSpeedMediumKmh
              ? GpsKalmanFilter.kSigmaAccelMedium
              : GpsKalmanFilter.kSigmaAccelMotorcycle;

      final f = _transitionMatrix(dt);
      final q = _processNoise(dt, sigmaAccel);

      final predState = _matVec(f, filteredStates[k - 1]);
      final fp = _matMul(f, filteredCovs[k - 1]);
      final fpft = _matMul(fp, _transpose(f));
      final predCov = _matAdd(fpft, q);

      final r = _measurementNoise(samples[k].accuracy);
      const h = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
      ];
      final z = [samples[k].lat, samples[k].lng];
      final hx = _matVec(h, predState);
      final y = [z[0] - hx[0], z[1] - hx[1]];
      final pht = _matMul(predCov, _transpose(h));
      final hpht = _matMul(h, pht);
      final s = [
        [hpht[0][0] + r, hpht[0][1]],
        [hpht[1][0], hpht[1][1] + r],
      ];
      final sInv = _inverse2x2(s);
      final kGain = _matMul(pht, sInv);
      final ky = _matVec(kGain, y);
      final updState = List.generate(4, (i) => predState[i] + ky[i]);
      final kh = _matMul(kGain, h);
      final ikh = List.generate(
          4, (i) => List.generate(4, (j) => (i == j ? 1.0 : 0.0) - kh[i][j]));
      final updCov = _matMul(ikh, predCov);

      predictedStates.add(predState);
      predictedCovs.add(predCov);
      filteredStates.add(updState);
      filteredCovs.add(updCov);
      transitions.add(f);
    }

    // ── Backward pass: ricorsione RTS.
    // Guadagno di smoothing C = P_filt[k] * F[k+1]' * P_pred[k+1]^-1
    // stato_smussato[k] = stato_filtrato[k] + C * (stato_smussato[k+1] - stato_predetto[k+1])
    final smoothedStates = List<List<double>>.filled(n, const []);
    smoothedStates[n - 1] = filteredStates[n - 1];

    for (var k = n - 2; k >= 0; k--) {
      final f = transitions[k + 1];
      final pPredNextInv = _inverse4x4(predictedCovs[k + 1]);
      final c = _matMul(_matMul(filteredCovs[k], _transpose(f)), pPredNextInv);
      final diff = List.generate(
          4, (i) => smoothedStates[k + 1][i] - predictedStates[k + 1][i]);
      final correction = _matVec(c, diff);
      smoothedStates[k] =
          List.generate(4, (i) => filteredStates[k][i] + correction[i]);
    }

    return List.generate(
      n,
      (k) => SmoothedTrackPoint(
        position: LatLng(smoothedStates[k][0], smoothedStates[k][1]),
        timestamp: samples[k].timestamp,
      ),
    );
  }

  static double _geometricSpeedKmh(
      RawTrackSample prev, RawTrackSample curr, double dtSec) {
    if (dtSec <= 0) return 0.0;
    const r = 6371000.0;
    final lat1 = prev.lat * pi / 180;
    final lat2 = curr.lat * pi / 180;
    final dLat = (curr.lat - prev.lat) * pi / 180;
    final dLng = (curr.lng - prev.lng) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final a = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distM = r * c;
    return (distM / dtSec) * 3.6;
  }

  static double _measurementNoise(double accuracyM) {
    final d = accuracyM / 111111.0;
    return d * d;
  }

  static List<List<double>> _transitionMatrix(double dt) => [
        [1.0, 0.0, dt, 0.0],
        [0.0, 1.0, 0.0, dt],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ];

  static List<List<double>> _processNoise(double dt, double sigmaAccel) {
    final saDeg = sigmaAccel / 111111.0;
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
    return q;
  }

  static List<List<double>> _identity4() => [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ];

  // ── Matrix helpers (stesso stile di kalman_filter.dart) ──

  static List<double> _matVec(List<List<double>> m, List<double> v) =>
      List.generate(m.length, (i) {
        var sum = 0.0;
        for (var j = 0; j < v.length; j++) {
          sum += m[i][j] * v[j];
        }
        return sum;
      });

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

  /// Inversa 4x4 via eliminazione di Gauss-Jordan con pivot parziale.
  /// Se una colonna risulta numericamente singolare (covarianza degenere,
  /// caso patologico con dt~0 già escluso dal clamp sopra), quella
  /// colonna viene lasciata invariata: risultato comunque stabile, mai
  /// NaN/infinito.
  static List<List<double>> _inverse4x4(List<List<double>> m) {
    const n = 4;
    final a = List.generate(n, (i) => List<double>.from(m[i]));
    final inv =
        List.generate(n, (i) => List.generate(n, (j) => i == j ? 1.0 : 0.0));

    for (var col = 0; col < n; col++) {
      var pivotRow = col;
      var maxVal = a[col][col].abs();
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > maxVal) {
          maxVal = a[r][col].abs();
          pivotRow = r;
        }
      }
      if (maxVal < 1e-12) continue;
      if (pivotRow != col) {
        final tmp = a[col];
        a[col] = a[pivotRow];
        a[pivotRow] = tmp;
        final tmpI = inv[col];
        inv[col] = inv[pivotRow];
        inv[pivotRow] = tmpI;
      }
      final pivot = a[col][col];
      for (var j = 0; j < n; j++) {
        a[col][j] /= pivot;
        inv[col][j] /= pivot;
      }
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final factor = a[r][col];
        if (factor == 0) continue;
        for (var j = 0; j < n; j++) {
          a[r][j] -= factor * a[col][j];
          inv[r][j] -= factor * inv[col][j];
        }
      }
    }
    return inv;
  }
}
