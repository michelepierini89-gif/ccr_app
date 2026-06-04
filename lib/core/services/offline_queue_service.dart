import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';

class OfflineQueueService {
  static const _kPassagesKey = 'offline_passages';
  static const _kRegistrationsKey = 'offline_registrations';

  final SharedPreferences _prefs;
  bool _syncing = false;

  OfflineQueueService(this._prefs);

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

  Future<void> queuePassage({
    required String eventId,
    required String userId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
  }) async {
    final list = _getList(_kPassagesKey)
      ..add({
        'eventId': eventId,
        'userId': userId,
        'waypointId': waypointId,
        'waypointNome': waypointNome,
        'timestamp': timestamp.toIso8601String(),
      });
    await _saveList(_kPassagesKey, list);
    debugPrint('OfflineQueue: passage queued (${list.length} pending)');
  }

  Future<void> queueRegistration({
    required String eventId,
    required String userId,
    required String nome,
    required String cognome,
    String? squadraId,
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
    final list = _getList(_kRegistrationsKey)..add(entry);
    await _saveList(_kRegistrationsKey, list);
    debugPrint('OfflineQueue: registration queued (${list.length} pending)');
  }

  int get pendingPassagesCount => _getList(_kPassagesKey).length;
  int get pendingRegistrationsCount => _getList(_kRegistrationsKey).length;
  bool get hasPending => pendingPassagesCount > 0 || pendingRegistrationsCount > 0;

  Future<int> syncPending(FirestoreService firestore) async {
    if (_syncing) return 0;
    _syncing = true;
    int synced = 0;

    try {
      // Sync waypoint passages
      final passages = _getList(_kPassagesKey);
      if (passages.isNotEmpty) {
        final failed = <Map<String, dynamic>>[];
        for (final p in passages) {
          try {
            await firestore.recordWaypointPassage(
              eventId: p['eventId'] as String,
              userId: p['userId'] as String,
              waypointId: p['waypointId'] as String,
              waypointNome: p['waypointNome'] as String,
              timestamp: DateTime.parse(p['timestamp'] as String),
            );
            synced++;
          } catch (e) {
            failed.add(p);
            debugPrint('OfflineQueue: passage sync failed: $e');
          }
        }
        await _saveList(_kPassagesKey, failed);
        if (synced > 0) debugPrint('OfflineQueue: synced $synced passages');
      }

      // Sync registrations
      final registrations = _getList(_kRegistrationsKey);
      if (registrations.isNotEmpty) {
        final failed = <Map<String, dynamic>>[];
        for (final r in registrations) {
          try {
            await firestore.registerForEvent(
              eventId: r['eventId'] as String,
              userId: r['userId'] as String,
              nome: r['nome'] as String,
              cognome: r['cognome'] as String,
              squadraId: r['squadraId'] as String?,
            );
            synced++;
          } catch (e) {
            failed.add(r);
            debugPrint('OfflineQueue: registration sync failed: $e');
          }
        }
        await _saveList(_kRegistrationsKey, failed);
      }
    } finally {
      _syncing = false;
    }

    return synced;
  }

  void clearAll() {
    _prefs.remove(_kPassagesKey);
    _prefs.remove(_kRegistrationsKey);
  }
}
