import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gps_point_model.dart';
import 'firestore_service.dart';

class OfflineQueueService extends ChangeNotifier {
  static const _kPassagesKey = 'offline_passages';
  static const _kRegistrationsKey = 'offline_registrations';
  static const _kJoinTeamsKey = 'offline_join_teams';
  static const _kTrackingKey = 'offline_tracking';

  final SharedPreferences _prefs;
  bool _syncing = false;

  OfflineQueueService(this._prefs);

  // ── List helpers ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _getList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveList(String key, List<Map<String, dynamic>> list) =>
      _prefs.setString(key, jsonEncode(list));

  Map<String, dynamic> _getMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMap(String key, Map<String, dynamic> map) =>
      _prefs.setString(key, jsonEncode(map));

  // ── Queue operations ─────────────────────────────────────────────────────────

  Future<void> queuePassage({
    required String eventId,
    required String userId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
    String timingMethod = 'radius',
    // Rifiniture Step 47 — non-null per un passaggio di allenamento: la
    // riproduzione (vedi _syncList sotto) instrada verso la sottocollezione
    // del tentativo invece che verso la collezione piatta di gara.
    String? attemptId,
  }) async {
    final list = _getList(_kPassagesKey)
      ..add({
        'eventId': eventId,
        'userId': userId,
        'waypointId': waypointId,
        'waypointNome': waypointNome,
        'timestamp': timestamp.toIso8601String(),
        'timingMethod': timingMethod,
        'attemptId': ?attemptId,
      });
    await _saveList(_kPassagesKey, list);
    debugPrint('OfflineQueue: passage queued (${list.length} pending)');
    notifyListeners();
  }

  Future<void> queueRegistration({
    required String eventId,
    required String userId,
    required String nome,
    required String cognome,
    String? squadraId,
    String? teamName,
    required DateTime createdAt,
  }) async {
    final entry = <String, dynamic>{
      'eventId': eventId,
      'userId': userId,
      'nome': nome,
      'cognome': cognome,
      'createdAt': createdAt.toIso8601String(),
    };
    if (squadraId != null) entry['squadraId'] = squadraId;
    if (teamName != null) entry['teamName'] = teamName;
    final list = _getList(_kRegistrationsKey)..add(entry);
    await _saveList(_kRegistrationsKey, list);
    debugPrint('OfflineQueue: registration queued (${list.length} pending)');
    notifyListeners();
  }

  Future<void> queueJoinTeam({
    required String eventId,
    required String teamId,
    required String userId,
  }) async {
    final list = _getList(_kJoinTeamsKey)
      ..add({
        'eventId': eventId,
        'teamId': teamId,
        'userId': userId,
      });
    await _saveList(_kJoinTeamsKey, list);
    debugPrint('OfflineQueue: joinTeam queued (${list.length} pending)');
    notifyListeners();
  }

  /// Keeps only the latest position per eventId/userId (no accumulation).
  Future<void> queueTracking(GpsPointModel point) async {
    final key = '${point.eventId}_${point.userId}';
    final map = _getMap(_kTrackingKey);
    map[key] = {
      'userId': point.userId,
      'eventId': point.eventId,
      'lat': point.lat,
      'lng': point.lng,
      'accuracy': point.accuracy,
      'speed': point.speed,
      'timestamp': point.timestamp.toIso8601String(),
      'specialeId': point.specialeId,
      'waypointPassati': point.waypointPassati,
    };
    await _saveMap(_kTrackingKey, map);
    notifyListeners();
  }

  // ── Pending counts ───────────────────────────────────────────────────────────

  int get pendingPassagesCount => _getList(_kPassagesKey).length;
  int get pendingRegistrationsCount => _getList(_kRegistrationsKey).length;
  int get pendingJoinTeamsCount => _getList(_kJoinTeamsKey).length;
  int get pendingTrackingCount => _getMap(_kTrackingKey).length;

  int get totalPendingCount =>
      pendingPassagesCount +
      pendingRegistrationsCount +
      pendingJoinTeamsCount +
      pendingTrackingCount;

  bool get hasPending => totalPendingCount > 0;

  // ── Sync with exponential backoff ────────────────────────────────────────────

  Future<int> syncPending(FirestoreService firestore) async {
    if (_syncing) return 0;
    _syncing = true;
    int synced = 0;

    try {
      synced += await _syncList(
        _kPassagesKey,
        (p) {
          final attemptId = p['attemptId'] as String?;
          if (attemptId != null) {
            return firestore.recordAttemptWaypointPassage(
              eventId: p['eventId'] as String,
              userId: p['userId'] as String,
              attemptId: attemptId,
              waypointId: p['waypointId'] as String,
              waypointNome: p['waypointNome'] as String,
              timestamp: DateTime.parse(p['timestamp'] as String),
              timingMethod: p['timingMethod'] as String? ?? 'radius',
            );
          }
          return firestore.recordWaypointPassage(
            eventId: p['eventId'] as String,
            userId: p['userId'] as String,
            waypointId: p['waypointId'] as String,
            waypointNome: p['waypointNome'] as String,
            timestamp: DateTime.parse(p['timestamp'] as String),
            timingMethod: p['timingMethod'] as String? ?? 'radius',
          );
        },
      );

      synced += await _syncList(
        _kRegistrationsKey,
        (r) => firestore.registerForEvent(
          eventId: r['eventId'] as String,
          userId: r['userId'] as String,
          nome: r['nome'] as String,
          cognome: r['cognome'] as String,
          squadraId: r['squadraId'] as String?,
          teamName: r['teamName'] as String?,
        ),
      );

      synced += await _syncList(
        _kJoinTeamsKey,
        (j) => firestore.joinTeam(
          j['eventId'] as String,
          j['teamId'] as String,
          j['userId'] as String,
        ),
      );

      synced += await _syncTrackingMap(firestore);
    } finally {
      _syncing = false;
    }

    if (synced > 0) {
      debugPrint('OfflineQueue: synced $synced items total');
      notifyListeners();
    }
    return synced;
  }

  /// Syncs a list with exponential backoff per item.
  /// Failed items get `retryCount` incremented and `nextRetryAt` set.
  Future<int> _syncList(
    String key,
    Future<void> Function(Map<String, dynamic>) action,
  ) async {
    final items = _getList(key);
    if (items.isEmpty) return 0;

    final now = DateTime.now();
    final stillPending = <Map<String, dynamic>>[];
    int synced = 0;

    for (final item in items) {
      final nextRetryStr = item['nextRetryAt'] as String?;
      if (nextRetryStr != null &&
          now.isBefore(DateTime.parse(nextRetryStr))) {
        stillPending.add(item);
        continue;
      }

      try {
        await action(item);
        synced++;
      } catch (e) {
        final retryCount = (item['retryCount'] as int? ?? 0) + 1;
        final delaySec = min(30 * pow(2, retryCount - 1).toInt(), 3600);
        final nextRetry =
            DateTime.now().add(Duration(seconds: delaySec));
        stillPending.add({
          ...item,
          'retryCount': retryCount,
          'nextRetryAt': nextRetry.toIso8601String(),
        });
        debugPrint(
            'OfflineQueue: $key item failed (retry $retryCount in ${delaySec}s): $e');
      }
    }

    await _saveList(key, stillPending);
    return synced;
  }

  Future<int> _syncTrackingMap(FirestoreService firestore) async {
    final map = _getMap(_kTrackingKey);
    if (map.isEmpty) return 0;

    final failed = <String, dynamic>{};
    int synced = 0;

    for (final entry in map.entries) {
      try {
        final d = entry.value as Map<String, dynamic>;
        await firestore.updatePilotTracking(GpsPointModel(
          userId: d['userId'] as String,
          eventId: d['eventId'] as String,
          lat: (d['lat'] as num).toDouble(),
          lng: (d['lng'] as num).toDouble(),
          accuracy: (d['accuracy'] as num).toDouble(),
          speed: (d['speed'] as num?)?.toDouble(),
          timestamp: DateTime.parse(d['timestamp'] as String),
          specialeId: d['specialeId'] as String?,
          waypointPassati: (d['waypointPassati'] as List).cast<String>(),
        ));
        synced++;
      } catch (e) {
        failed[entry.key] = entry.value;
        debugPrint('OfflineQueue: tracking sync failed: $e');
      }
    }

    if (failed.isEmpty) {
      await _prefs.remove(_kTrackingKey);
    } else {
      await _saveMap(_kTrackingKey, failed);
    }
    return synced;
  }

  void clearAll() {
    _prefs.remove(_kPassagesKey);
    _prefs.remove(_kRegistrationsKey);
    _prefs.remove(_kJoinTeamsKey);
    _prefs.remove(_kTrackingKey);
    notifyListeners();
  }
}
