import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/waypoint_model.dart';
import '../models/gps_point_model.dart';
import '../constants/app_constants.dart';
import '../services/waypoint_detector.dart';
import '../services/firestore_service.dart';

enum GpsMode { idle, transfer, inSpecial, nearWaypoint }

class WaypointPassage {
  final WaypointModel waypoint;
  final DateTime timestamp;
  WaypointPassage({required this.waypoint, required this.timestamp});
}

class GpsService extends ChangeNotifier {
  final FirestoreService _firestoreService;
  GpsService(this._firestoreService);

  bool _isRecording = false;
  GpsMode _mode = GpsMode.idle;
  Position? _lastPosition;
  String? _activeEventId;
  String? _activeUserId;
  List<WaypointModel> _waypoints = [];
  final Set<String> _passedWaypoints = {};
  final List<WaypointPassage> _passages = [];
  String? _currentSpecialId;
  DateTime? _recordingStart;
  StreamSubscription<Position>? _positionSub;

  bool get isRecording => _isRecording;
  GpsMode get mode => _mode;
  Position? get lastPosition => _lastPosition;
  List<WaypointPassage> get passages => List.unmodifiable(_passages);
  String? get currentSpecialId => _currentSpecialId;
  DateTime? get recordingStart => _recordingStart;
  Duration get elapsed => _recordingStart != null
      ? DateTime.now().difference(_recordingStart!)
      : Duration.zero;

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
  }) async {
    if (_isRecording) return;
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permesso GPS negato');

    _activeEventId = eventId;
    _activeUserId = userId;
    _waypoints = waypoints;
    _passedWaypoints.clear();
    _passages.clear();
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

  void _onPosition(Position pos) async {
    _lastPosition = pos;
    final latLng = LatLng(pos.latitude, pos.longitude);

    // Detect waypoint passage
    final wp = WaypointDetector.detectPassage(
        latLng, _waypoints, _passedWaypoints);
    if (wp != null) {
      _passedWaypoints.add(wp.id);
      final passage =
          WaypointPassage(waypoint: wp, timestamp: DateTime.now());
      _passages.add(passage);
      if (_activeEventId != null && _activeUserId != null) {
        await _firestoreService.recordWaypointPassage(
          eventId: _activeEventId!,
          userId: _activeUserId!,
          waypointId: wp.id,
          waypointNome: wp.nome,
          timestamp: passage.timestamp,
        );
      }
    }

    // Determine mode
    final nearest =
        WaypointDetector.nearestWaypointDistance(latLng, _waypoints);
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

    // Push to Firestore
    if (_activeEventId != null && _activeUserId != null) {
      await _firestoreService.updatePilotTracking(GpsPointModel(
        userId: _activeUserId!,
        eventId: _activeEventId!,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        speed: pos.speed,
        timestamp: DateTime.now(),
        specialeId: _currentSpecialId,
        waypointPassati: _passedWaypoints.toList(),
      ));
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
    _recordingStart = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
