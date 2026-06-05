import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/waypoint_model.dart';
import '../models/gps_point_model.dart';
import '../models/special_model.dart';
import '../constants/app_constants.dart';
import '../services/waypoint_detector.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue_service.dart';

enum GpsMode { idle, transfer, inSpecial, nearWaypoint }

class WaypointPassage {
  final WaypointModel waypoint;
  final DateTime timestamp;
  WaypointPassage({required this.waypoint, required this.timestamp});
}

class SpecialEntry {
  final String specialeId;
  final String specialeNome;
  final DateTime entryTime;
  final DateTime? exitTime;

  const SpecialEntry({
    required this.specialeId,
    required this.specialeNome,
    required this.entryTime,
    this.exitTime,
  });

  Duration? get elapsed => exitTime?.difference(entryTime);

  SpecialEntry withExit(DateTime t) => SpecialEntry(
        specialeId: specialeId,
        specialeNome: specialeNome,
        entryTime: entryTime,
        exitTime: t,
      );
}

class GpsService extends ChangeNotifier {
  final FirestoreService _firestoreService;
  final OfflineQueueService _offlineQueue;

  GpsService(this._firestoreService, this._offlineQueue);

  final StreamController<Position> _posStreamCtrl =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _posStreamCtrl.stream;

  bool _isRecording = false;
  GpsMode _mode = GpsMode.idle;
  Position? _lastPosition;
  String? _activeEventId;
  String? _activeUserId;
  List<WaypointModel> _waypoints = [];
  List<SpecialModel> _specials = [];
  final Map<String, String> _inizioToSpecial = {};
  final Map<String, String> _fineToSpecial = {};
  final Set<String> _passedWaypoints = {};
  final List<WaypointPassage> _passages = [];
  String? _currentSpecialId;
  String? _currentSpecialNome;
  final List<SpecialEntry> _specialEntries = [];
  DateTime? _recordingStart;
  StreamSubscription<Position>? _positionSub;
  final List<LatLng> _localTrack = [];
  double _totalDistanceKm = 0.0;

  bool get isRecording => _isRecording;
  GpsMode get mode => _mode;
  Position? get lastPosition => _lastPosition;
  List<WaypointPassage> get passages => List.unmodifiable(_passages);
  List<LatLng> get localTrack => List.unmodifiable(_localTrack);
  double get totalDistanceKm => _totalDistanceKm;
  String? get currentSpecialId => _currentSpecialId;
  String? get currentSpecialNome => _currentSpecialNome;
  List<SpecialEntry> get specialEntries => List.unmodifiable(_specialEntries);
  DateTime? get recordingStart => _recordingStart;
  Duration get elapsed => _recordingStart != null
      ? DateTime.now().difference(_recordingStart!)
      : Duration.zero;
  List<WaypointModel> get remainingWaypoints =>
      _waypoints.where((w) => !_passedWaypoints.contains(w.id)).toList();

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<void> startRecording({
    required String eventId,
    required String userId,
    required List<WaypointModel> waypoints,
    List<SpecialModel> specials = const [],
  }) async {
    if (_isRecording) return;
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permesso GPS negato');
    // Try to flush any data queued during previous offline sessions
    if (_offlineQueue.hasPending) {
      _offlineQueue.syncPending(_firestoreService).ignore();
    }

    _activeEventId = eventId;
    _activeUserId = userId;
    _waypoints = waypoints;
    _specials = specials;
    _inizioToSpecial.clear();
    _fineToSpecial.clear();
    for (final s in specials) {
      _inizioToSpecial[s.waypointInizio.id] = s.id;
      _fineToSpecial[s.waypointFine.id] = s.id;
    }
    _passedWaypoints.clear();
    _passages.clear();
    _specialEntries.clear();
    _localTrack.clear();
    _totalDistanceKm = 0.0;
    _currentSpecialId = null;
    _currentSpecialNome = null;
    _isRecording = true;
    _mode = GpsMode.transfer;
    _recordingStart = DateTime.now();
    notifyListeners();

    _startPositionStream(AppConstants.gpsIntervalTransferMs);
  }

  void _startPositionStream(int intervalMs) {
    _positionSub?.cancel();
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: Duration(milliseconds: intervalMs),
    );
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      _onPosition,
      onError: (e) => debugPrint('GPS error: $e'),
    );
  }

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final aVal =
        sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  void _onPosition(Position pos) async {
    _lastPosition = pos;
    _posStreamCtrl.add(pos);
    final latLng = LatLng(pos.latitude, pos.longitude);
    if (_localTrack.isNotEmpty) {
      _totalDistanceKm += _haversineKm(_localTrack.last, latLng);
    }
    _localTrack.add(latLng);

    // Detect waypoint passage
    final wp = WaypointDetector.detectPassage(
        latLng, _waypoints, _passedWaypoints);
    if (wp != null) {
      _passedWaypoints.add(wp.id);
      final now = DateTime.now();
      final passage = WaypointPassage(waypoint: wp, timestamp: now);
      _passages.add(passage);

      // Special entry/exit detection
      if (_inizioToSpecial.containsKey(wp.id) && _currentSpecialId == null) {
        final specialId = _inizioToSpecial[wp.id]!;
        final special = _specials.where((s) => s.id == specialId).firstOrNull;
        _currentSpecialId = specialId;
        _currentSpecialNome = special?.nome;
        _specialEntries.add(SpecialEntry(
          specialeId: specialId,
          specialeNome: special?.nome ?? specialId,
          entryTime: now,
        ));
      } else if (_fineToSpecial.containsKey(wp.id) &&
          _currentSpecialId == _fineToSpecial[wp.id]) {
        final idx =
            _specialEntries.lastIndexWhere((e) => e.exitTime == null);
        if (idx >= 0) {
          _specialEntries[idx] = _specialEntries[idx].withExit(now);
        }
        _currentSpecialId = null;
        _currentSpecialNome = null;
      }

      if (_activeEventId != null && _activeUserId != null) {
        try {
          await _firestoreService.recordWaypointPassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: wp.id,
            waypointNome: wp.nome,
            timestamp: passage.timestamp,
          );
        } catch (_) {
          await _offlineQueue.queuePassage(
            eventId: _activeEventId!,
            userId: _activeUserId!,
            waypointId: wp.id,
            waypointNome: wp.nome,
            timestamp: passage.timestamp,
          );
        }
      }
    }

    // Determine mode
    final remainingForMode =
        _waypoints.where((w) => !_passedWaypoints.contains(w.id)).toList();
    final nearest =
        WaypointDetector.nearestWaypointDistance(latLng, remainingForMode);
    final newMode = nearest != null &&
            nearest <= AppConstants.nearWaypointThresholdMeters
        ? GpsMode.nearWaypoint
        : (_currentSpecialId != null ? GpsMode.inSpecial : GpsMode.transfer);

    // Adapt interval if mode changed
    if (newMode != _mode) {
      _mode = newMode;
      final newInterval = WaypointDetector.adaptiveInterval(
          nearest, _currentSpecialId != null);
      _startPositionStream(newInterval);
    }

    // Push live tracking to Firestore — queue offline if unavailable
    if (_activeEventId != null && _activeUserId != null) {
      final point = GpsPointModel(
        userId: _activeUserId!,
        eventId: _activeEventId!,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        speed: pos.speed,
        timestamp: DateTime.now(),
        specialeId: _currentSpecialId,
        waypointPassati: _passedWaypoints.toList(),
      );
      _firestoreService.updatePilotTracking(point).catchError((_) {
        _offlineQueue.queueTracking(point).ignore();
      });
    }

    notifyListeners();
  }

  Future<void> stopRecording() async {
    _positionSub?.cancel();
    _positionSub = null;
    _isRecording = false;
    _mode = GpsMode.idle;
    _activeEventId = null;
    _activeUserId = null;
    _currentSpecialId = null;
    _currentSpecialNome = null;
    _recordingStart = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _posStreamCtrl.close();
    super.dispose();
  }
}
