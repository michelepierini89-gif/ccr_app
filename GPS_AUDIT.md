# Audit GPS — CCR App (analisi codice reale)

Audit puramente in lettura, basato sul codice sorgente effettivo (non sul PROGETTO_CCR.md), eseguito il 15/06/2026.

File analizzati:
- `lib/core/services/gps_service.dart`
- `lib/core/utils/kalman_filter.dart`
- `lib/core/services/waypoint_detector.dart`
- `lib/features/pilot/screens/gps_recording_screen.dart`
- `lib/features/map/widgets/track_layer.dart`
- `lib/features/map/widgets/waypoint_marker.dart`
- `lib/core/constants/app_constants.dart`

---

## 1. FREQUENZA GPS

**Implementata realmente**, non è un valore fisso. Costanti in `app_constants.dart`:

```dart
gpsIntervalNearWaypointMs = 250
gpsIntervalInSpecialMs    = 250
gpsIntervalTransferMs     = 1000
gpsIntervalNearDangerMs   = 500
```

La selezione avviene in `WaypointDetector.adaptiveInterval()`:
- entro `nearWaypointThresholdMeters` (50m) da un waypoint → 250ms
- in speciale → 250ms
- altrimenti (trasferimento) → 1000ms
- se vicino a un punto pericolo (entro 150m) → `min(intervallo_calcolato, 500ms)`

Il cambio di intervallo avviene in `_onPosition` quando `newMode != _mode || dangerNear != wasDangerNear`, richiamando `_startPositionStream(newInterval)` (che cancella e ricrea la subscription Geolocator).

⚠️ **Discrepanza con PROGETTO_CCR.md**: lo Step 14 dichiara "gpsIntervalInSpecialMs ridotto da 1000ms a 500ms", ma nel codice attuale il valore è **250ms**. Il documento non riflette l'ultimo valore reale.

---

## 2. KALMAN FILTER

Il file **esiste** (`lib/core/utils/kalman_filter.dart`) ed è **effettivamente integrato**.

Codice (filtro 1D indipendente su lat/lng, in gradi):
```dart
class GpsKalmanFilter {
  static const double _q = 1e-5; // process noise in degrees²
  _K1D? _lat;
  _K1D? _lng;
  DateTime? _lastTs;

  LatLng filter(double lat, double lng, double accuracy, DateTime ts) {
    final r = _measurementNoise(accuracy);
    if (_lat == null || ts.difference(_lastTs!).inSeconds > 10) {
      _lat = _K1D(lat, r); _lng = _K1D(lng, r); _lastTs = ts;
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

  static double _measurementNoise(double accuracyM) {
    final d = accuracyM / 111111.0;
    return d * d;
  }
}
```

Chiamata in `gps_service.dart` → `_onPosition`:
```dart
final filtered = _kalmanFilter.filter(
    pos.latitude, pos.longitude, pos.accuracy, now);
_filteredPosition = filtered;
final latLng = filtered;
```
Tutta la logica successiva (distanza totale, traccia, waypoint, bearing, recovery, scrittura Firestore) usa `latLng` (filtrato), non le coordinate raw.

Reset automatico se il gap tra punti supera 10s, e reset manuale via `_kalmanFilter.reset()` su `startRecording`, `stopRecording` e dopo 4 "jump" consecutivi.

---

## 3. FILTRO ACCURATEZZA

Sì, esiste:
```dart
static const double kMaxAcceptableAccuracyMeters = 25.0;
...
if (pos.accuracy > kMaxAcceptableAccuracyMeters) {
  _consecutiveDiscarded++;
  notifyListeners();
  return;
}
_consecutiveDiscarded = 0;
```
**Soglia esatta: 25.0 metri.** Il punto viene scartato completamente (non entra in Kalman, traccia, waypoint detection). `_lastPosition` e `positionStream` vengono comunque aggiornati prima del controllo (per mostrare LAT/LNG/PREC in UI). `isAccuracyPoor` (banner "Segnale GPS debole") diventa true dopo 5 scarti consecutivi.

---

## 4. FILTRO VELOCITÀ/JUMPS

Sì, implementato come "secondo livello di sicurezza dopo Kalman":
```dart
static const double kMaxSpeedFilterKmh = 250.0;
```
Logica:
- calcola `speedKmh` tra l'ultimo punto raw accettato e quello attuale
- se `speedKmh > 250` → scarta il punto (`_jumpCount++`), ma solo per i primi 3 jump consecutivi
- al 4° jump consecutivo → accetta il punto come "teletrasporto GPS" e resetta il filtro Kalman (`_kalmanFilter.reset()`)

**Soglia esatta: 250 km/h.**

---

## 5. BEARING E ROTAZIONE MAPPA

**Non usa `position.heading`** — calcolo puramente geometrico (azimuth) tra gli ultimi due punti *filtrati Kalman*:

```dart
static double _computeBearingDeg(LatLng from, LatLng to) {
  final lat1 = from.latitude * pi / 180;
  final lat2 = to.latitude * pi / 180;
  final dLon = (to.longitude - from.longitude) * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
}
```

Buffer circolare degli ultimi 5 punti filtrati (`_recentPoints`), ma usa solo gli ultimi 2. Aggiornamento condizionato:
```dart
final speedKmh = pos.speed * 3.6;  // <-- usa position.speed, NON la velocità geometrica
if (speedKmh > _kMinSpeedKmh && _recentPoints.length >= 2) {
  _lastHighSpeedBearingDeg = _computeBearingDeg(_recentPoints[...-2], _recentPoints[...-1]);
  _bearingDeg = _lastHighSpeedBearingDeg;
}
// sotto i 5 km/h: _bearingDeg resta congelato all'ultimo valore valido
```

**Applicazione in UI** (`gps_recording_screen.dart`):
```dart
final arrowAngle = _headingMode ? 0.0 : gps.bearingDeg * pi / 180;
...
Marker(
  point: curPos, width: 36, height: 36,
  rotate: _headingMode,
  child: Transform.rotate(angle: arrowAngle, child: Icon(Icons.navigation, ...)),
)
```
- **Modalità NORD**: mappa fissa, freccia ruota di `bearingDeg`.
- **Modalità HEADING**: `_mapController.rotate(-gps.bearingDeg)` ruota la mappa; la freccia ha `rotate: true` (cancella la rotazione del layer) e `angle: 0`, quindi resta sempre verso l'alto.

---

## 6. RECOVERY START PS

Sì, implementato in `_trySpecialStartRecovery` (chiamato ad ogni punto accettato dopo il waypoint detection):

```dart
static const double kSpecialStartRecoveryRadiusMeters = 80.0;
static const int kSpecialStartRecoveryLookbackSeconds = 30;
```

Algoritmo (per ogni speciale non ancora iniziata, non già tentata, non annullata):
1. Se la posizione corrente è entro `80m * 3 = 240m` dal waypoint START
2. → marca `_recoveryAttempted` (un solo tentativo per speciale)
3. Scansiona `_localTrack`/`_trackTimestamps` all'indietro fino a 30s nel passato, cerca il punto più vicino al waypoint START
4. Se quel punto è < 80m → registra `entryTime` retroattivo, segna `inizioId` come passato, apre la `SpecialEntry` con `recoveredStart: true`, emette messaggio su `recoveryStream`, salva su Firestore (o offline queue) con `recoveredStart: true`

---

## 7. WAKELOCK E BACKGROUND

- `WakelockPlus.enable()` chiamato sia in `GpsService.startRecording()` sia in `_GpsRecordingScreenState.initState()` (doppia chiamata idempotente)
- `AndroidSettings` con:
```dart
foregroundNotificationConfig: const ForegroundNotificationConfig(
  notificationText: 'CCR Rally — GPS attivo in background',
  notificationTitle: 'Registrazione GPS',
  enableWakeLock: true,
  setOngoing: true,
  notificationChannelName: 'CCR GPS Tracking',
)
```
- iOS: `AppleSettings` con `activityType: ActivityType.fitness`, `pauseLocationUpdatesAutomatically: false`, `showBackgroundLocationIndicator: true`
- Secondo PROGETTO_CCR.md, `AndroidManifest.xml` ha `foregroundServiceType="location"` e permesso `FOREGROUND_SERVICE_LOCATION` (non verificato in questo audit perché non richiesto, ma citato come "verificato" nello Step 16)

→ **Sì, il GPS è configurato per continuare con schermo spento** tramite foreground service Android + wakelock.

---

## 8. DISTANCEFILTER

```dart
final distanceFilter =
    (_mode == GpsMode.nearWaypoint || _mode == GpsMode.inSpecial) ? 0 : 2;
```
- **In trasferimento: 2 metri.**
- **Vicino waypoint o in speciale: 0 metri** (ogni fix viene emesso indipendentemente dallo spostamento).

È **aggiornato dinamicamente**: ogni volta che `_startPositionStream()` viene richiamato per cambio modalità, viene ricalcolato e applicato alle nuove `LocationSettings`.

---

## Cose che sembrano incomplete / potenzialmente bugged

1. **Recovery PS — tentativo "consumato" troppo presto**: `_recoveryAttempted.add(special.id)` viene eseguito appena il pilota entra nei 240m, *prima* di sapere se nel lookback di 30s esiste un punto <80m. Se il pilota arriva da lontano ad alta velocità ed entra nei 240m senza che negli ultimi 30s ci sia stato un punto <80m, il recovery per quella speciale è **perso per sempre**, anche se 5 secondi dopo il pilota passa realmente a <80m (a quel punto però il passaggio normale del waypoint dovrebbe comunque scattare — ma se il GPS è debole proprio in quel punto, il recovery non avrà una seconda chance).

2. **Bearing basato su `position.speed`, non sulla velocità geometrica**: la soglia dei 5 km/h per "congelare" il bearing usa `pos.speed * 3.6` (valore GPS raw), mentre altrove (`geometricSpeedKmh`, mostrato in UI come "VEL") si usa esplicitamente la velocità calcolata geometricamente perché `position.speed` è descritta come "inaffidabile" nei commenti del codice stesso. C'è quindi un'incoerenza: il filtro di velocità per i jump usa la velocità geometrica, ma il freeze del bearing usa `position.speed`.

3. **distanceFilter=0 + intervallo 250ms in speciale**: ogni fix GPS viene scritto su Firestore (`updatePilotTracking`) senza alcun throttling separato dalla frequenza di campionamento. In una speciale lunga questo significa una scrittura Firestore ogni 250ms per pilota — potenzialmente notevole in termini di costi/quota con molti piloti in gara contemporaneamente. Non risulta nessun debounce/batching per le scritture di tracking live.

4. **Punto accuracy-discarded blocca completamente l'aggiornamento di modalità/intervallo**: se l'accuratezza è > 25m, la funzione fa `return` immediato senza ricalcolare `nearest`/`newMode`. Se il pilota è entrato in modalità `nearWaypoint` (intervallo 250ms) e il segnale degrada sopra 25m per un periodo prolungato, l'intervallo resta bloccato a 250ms (consumo batteria) finché non arriva un fix sufficientemente accurato.

5. **Reset rotazione mappa solo all'uscita da HEADING**: `_mapController.rotate(0)` viene chiamato solo quando l'utente disattiva manualmente la modalità HEADING tramite il pulsante. Se l'utente ruota la mappa con gesto a due dita in modalità NORD, non c'è alcun reset automatico — la mappa potrebbe restare ruotata in modo inatteso (probabilmente minore, ma non gestito).

6. **`_recentPoints` buffer di 5 elementi ma ne usa solo 2**: non è un bug funzionale, ma il buffer da 5 sembra preparato per un calcolo di bearing più sofisticato (media/smoothing su più punti) che però non è implementato — viene usato solo l'ultimo segmento.

Tutto il resto (Kalman, filtro accuracy, filtro jump, recovery, wakelock/background, distanceFilter dinamico, intervalli GPS adattivi) risulta **effettivamente implementato e coerente** con quanto descritto, salvo la discrepanza sul valore di `gpsIntervalInSpecialMs` indicata al punto 1.
