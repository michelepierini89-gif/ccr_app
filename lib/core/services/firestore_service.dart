import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../constants/firebase_constants.dart';
import '../models/app_notification_model.dart';
import '../models/championship_model.dart';
import '../models/cp_dispute_model.dart';
import '../models/event_model.dart';
import '../models/penalty_settings_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';
import '../models/classifica_model.dart';
import 'track_smoother.dart';

class FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Events
  Future<String> createEvent(EventModel event) async {
    final ref = await _db
        .collection(FirebaseConstants.events)
        .add(event.toFirestore());
    return ref.id;
  }

  Future<void> updateEvent(EventModel event) => _db
      .collection(FirebaseConstants.events)
      .doc(event.id)
      .update(event.toFirestore());

  Future<void> deleteEvent(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .delete();

  Stream<List<EventModel>> getEvents({String? createdBy}) {
    Query q = _db
        .collection(FirebaseConstants.events)
        .orderBy('createdAt', descending: true);
    if (createdBy != null) q = q.where('createdBy', isEqualTo: createdBy);
    return q.snapshots().map(
        (s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());
  }

  Stream<List<EventModel>> getOpenEvents() => _db
      .collection(FirebaseConstants.events)
      .where('stato', whereIn: ['aperto', 'inCorso'])
      .orderBy('data')
      .snapshots()
      .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());

  Stream<List<EventModel>> getArchivedEvents() => _db
      .collection(FirebaseConstants.events)
      .where('stato', isEqualTo: 'archiviata')
      .orderBy('data', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());

  Future<EventModel?> getEvent(String id) async {
    final doc =
        await _db.collection(FirebaseConstants.events).doc(id).get();
    if (!doc.exists) return null;
    return EventModel.fromFirestore(doc);
  }

  Stream<EventModel?> getEventById(String id) => _db
      .collection(FirebaseConstants.events)
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? EventModel.fromFirestore(doc) : null);

  // Registrations
  Future<void> registerForEvent({
    required String eventId,
    required String userId,
    required String nome,
    required String cognome,
    String? squadraId,
    String? teamName,
  }) async {
    final reg = RegistrationModel(
      userId: userId,
      eventId: eventId,
      nome: nome,
      cognome: cognome,
      stato: RegistrationStatus.inAttesa,
      squadraId: squadraId,
      teamName: teamName,
      createdAt: DateTime.now(),
    );
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .set(reg.toFirestore());
    await _createNotification(eventId, {
      'type': 'new_registration',
      'userId': userId,
      'nome': '$nome $cognome',
      'squadraId': squadraId,
    });
  }

  Stream<RegistrationModel?> streamMyRegistration(
          String eventId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.iscritti)
          .doc(userId)
          .snapshots()
          .map((doc) =>
              doc.exists ? RegistrationModel.fromFirestore(doc, eventId) : null);

  Future<void> updateRegistrationStatus(
    String eventId,
    String userId,
    RegistrationStatus stato,
  ) async {
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .update({'stato': stato.name});
    final approved = stato == RegistrationStatus.approvato;
    await _sendUserNotification(
      recipientId: userId,
      type: approved
          ? NotificationType.registrationApproved
          : NotificationType.registrationRejected,
      title: approved ? 'Iscrizione approvata' : 'Iscrizione rifiutata',
      body: approved
          ? 'La tua iscrizione all\'evento è stata approvata!'
          : 'La tua iscrizione all\'evento è stata rifiutata.',
    );
  }

  Stream<List<RegistrationModel>> getRegistrations(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.iscritti)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => RegistrationModel.fromFirestore(d, eventId))
          .toList());

  Future<RegistrationModel?> getMyRegistration(
      String eventId, String userId) async {
    final doc = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    return RegistrationModel.fromFirestore(doc, eventId);
  }

  // Teams
  /// Crea una squadra solo se non esiste già una con lo stesso nome
  /// (case-insensitive, trim) nello stesso evento.
  /// Lancia [Exception('team_name_exists')] in caso di duplicato.
  Future<String> createTeam(TeamModel team) async {
    final existing = await _db
        .collection(FirebaseConstants.events)
        .doc(team.eventId)
        .collection(FirebaseConstants.teams)
        .get();
    final nameLower = team.nome.trim().toLowerCase();
    final duplicate = existing.docs.any(
      (d) => (d.data()['nome'] as String? ?? '').trim().toLowerCase() == nameLower,
    );
    if (duplicate) throw Exception('team_name_exists');

    final ref = await _db
        .collection(FirebaseConstants.events)
        .doc(team.eventId)
        .collection(FirebaseConstants.teams)
        .add(team.toFirestore());
    return ref.id;
  }

  Stream<List<TeamModel>> getTeams(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.teams)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TeamModel.fromFirestore(d, eventId)).toList());

  Future<void> joinTeam(
          String eventId, String teamId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.teams)
          .doc(teamId)
          .update({
        'membriIds': FieldValue.arrayUnion([userId])
      });

  Future<void> leaveTeam(
          String eventId, String teamId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.teams)
          .doc(teamId)
          .update({
        'membriIds': FieldValue.arrayRemove([userId])
      });

  // GPS Tracking
  Future<void> updatePilotTracking(GpsPointModel point) => _db
      .collection(FirebaseConstants.tracking)
      .doc(point.eventId)
      .collection(FirebaseConstants.pilots)
      .doc(point.userId)
      .set(point.toFirestore(), SetOptions(merge: true));

  Future<void> setRaceStatus(
          String eventId, String userId, String status,
          {String? retiredReason, DateTime? finishedAt}) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .set({
            'raceStatus': status,
            'retiredReason': ?retiredReason,
            if (finishedAt != null)
              'finishedAt': Timestamp.fromDate(finishedAt),
          }, SetOptions(merge: true));

  /// Persists the full GPS track for post-race replay.
  /// Called on FINE GARA and RITIRO so the result screen can show the polyline.
  Future<void> savePilotTrack(
          String eventId, String userId, List<LatLng> track) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .set({
            'pilotTrack': track
                .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                .toList(),
          }, SetOptions(merge: true));

  /// Fix 5 (09/08/2026) — campioni per chunk della sottocollezione
  /// [FirebaseConstants.fullTrackChunks]: a questa dimensione un chunk resta
  /// largamente sotto il limite Firestore di 1 MiB per documento anche nel
  /// caso peggiore (accuracy con molti decimali). Un batch write può
  /// contenere al più 500 operazioni: con gare fino a 4-5 ore a 250ms in
  /// speciale, il numero di chunk resta comunque a una piccola frazione di
  /// quel limite.
  static const int _fullTrackChunkSize = 2000;

  /// Persiste la traccia grezza completa (posizione + accuracy + timestamp
  /// per ogni fix accettato), separata dal semplice `pilotTrack` (solo
  /// lat/lng, usato per il replay della polyline): serve da input al
  /// ricalcolo post-gara con [TrackSmoother] (Blocco B).
  ///
  /// Fix 5 — PRIMA di questo fix, `samples` veniva scritto come un unico
  /// campo array sul documento `tracking/{eventId}/pilots/{userId}`: su una
  /// gara lunga (es. il test 100km del 09/08) questo campo, sommato al
  /// resto del documento, può superare il limite Firestore di 1 MiB per
  /// documento — il `.set()` fallisce, l'eccezione viene ingoiata dal
  /// `catch` generico attorno alla chiamata (in `gps_recording_screen.dart`)
  /// e la traccia risulta silenziosamente assente, mentre `pilotTrack`
  /// (molto più piccolo: solo lat/lng) continua a salvarsi correttamente —
  /// esattamente il sintomo osservato ("la mappa disegna la traccia, il
  /// ricalcolo dice che non c'è"). Ora `samples` viene spezzato in chunk in
  /// una sottocollezione dedicata, ciascuno ben sotto il limite.
  ///
  /// Cancella prima eventuali chunk di un salvataggio precedente per lo
  /// stesso pilota (idempotente: un secondo salvataggio con meno campioni
  /// non lascia chunk residui più vecchi e più lunghi).
  Future<void> saveFullPilotTrack(
      String eventId, String userId, List<RawTrackSample> samples) async {
    final chunksRef = _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .collection(FirebaseConstants.fullTrackChunks);

    final existing = await chunksRef.get();
    if (existing.docs.isNotEmpty || samples.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (var i = 0; i < samples.length; i += _fullTrackChunkSize) {
        final end = (i + _fullTrackChunkSize < samples.length)
            ? i + _fullTrackChunkSize
            : samples.length;
        final chunk = samples.sublist(i, end);
        batch.set(chunksRef.doc(i.toString().padLeft(8, '0')), {
          'samples': chunk
              .map((s) => {
                    'lat': s.lat,
                    'lng': s.lng,
                    'accuracy': s.accuracy,
                    'ts': s.timestamp.millisecondsSinceEpoch,
                  })
              .toList(),
        });
      }
      await batch.commit();
    }

    // Campo legacy sul documento pilota: mantenuto vuoto/rimosso per non
    // lasciare doppioni, ma senza toccare gli altri campi del documento
    // (raceStatus, pilotTrack, waypointPassati, ...).
    await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .set({'pilotTrackFull': FieldValue.delete()}, SetOptions(merge: true));
  }

  /// Legge la traccia grezza completa salvata da [saveFullPilotTrack] per
  /// [userId] nell'evento [eventId], o lista vuota se assente (es. pilota
  /// mai concluso una sessione). Fix 5 — legge dalla sottocollezione a
  /// chunk (nome doc ordinabile lessicograficamente, zero-padded);
  /// fallback sul vecchio campo singolo `pilotTrackFull` per le tracce
  /// salvate prima di questo fix e ancora presenti (sotto 1 MiB, quindi mai
  /// state colpite dal bug).
  Future<List<RawTrackSample>> getFullPilotTrack(
      String eventId, String userId) async {
    final pilotDocRef = _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId);

    final chunks = await pilotDocRef
        .collection(FirebaseConstants.fullTrackChunks)
        .orderBy(FieldPath.documentId)
        .get();
    if (chunks.docs.isNotEmpty) {
      final result = <RawTrackSample>[];
      for (final doc in chunks.docs) {
        final raw = doc.data()['samples'] as List<dynamic>? ?? const [];
        result.addAll(raw.map((e) => RawTrackSample(
              lat: (e['lat'] as num).toDouble(),
              lng: (e['lng'] as num).toDouble(),
              accuracy: (e['accuracy'] as num).toDouble(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(e['ts'] as int),
            )));
      }
      return result;
    }

    final doc = await pilotDocRef.get();
    final raw = doc.data()?['pilotTrackFull'] as List<dynamic>?;
    if (raw == null) return [];
    return raw
        .map((e) => RawTrackSample(
              lat: (e['lat'] as num).toDouble(),
              lng: (e['lng'] as num).toDouble(),
              accuracy: (e['accuracy'] as num).toDouble(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(e['ts'] as int),
            ))
        .toList();
  }

  /// Salva i tempi ufficiali di [userId] ricalcolati post-gara (Blocco B),
  /// uno per speciale, in campi separati dai tempi live — la classifica
  /// (ClassificaEngine) li preferisce quando presenti.
  Future<void> saveOfficialTimes(String eventId, String userId,
          Map<String, OfficialSpecialTime> bySpecialId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection('officialTimes')
          .doc(userId)
          .set({
        'specials': {
          for (final e in bySpecialId.entries) e.key: e.value.toMap(),
        },
      });

  /// Stream dei tempi ufficiali di tutti i piloti dell'evento [eventId],
  /// come userId -> specialeId -> [OfficialSpecialTime].
  Stream<Map<String, Map<String, OfficialSpecialTime>>> officialTimesStream(
          String eventId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection('officialTimes')
          .snapshots()
          .map((s) => _parseOfficialTimes(s.docs));

  Future<Map<String, Map<String, OfficialSpecialTime>>> getOfficialTimesOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection('officialTimes')
        .get();
    return _parseOfficialTimes(snap.docs);
  }

  Map<String, Map<String, OfficialSpecialTime>> _parseOfficialTimes(
      List<QueryDocumentSnapshot> docs) {
    final result = <String, Map<String, OfficialSpecialTime>>{};
    for (final doc in docs) {
      final specials =
          (doc.data() as Map<String, dynamic>)['specials'] as Map<String, dynamic>? ??
              {};
      result[doc.id] = {
        for (final e in specials.entries)
          e.key: OfficialSpecialTime.fromMap(e.value as Map<String, dynamic>),
      };
    }
    return result;
  }

  /// Stream of the current pilot's tracking doc fields (lightweight, no GPS parsing).
  Stream<Map<String, dynamic>?> myPilotStatusStream(
          String eventId, String userId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .snapshots()
          .map((doc) => doc.exists ? doc.data() as Map<String, dynamic> : null);

  Stream<List<GpsPointModel>> getPilotTracking(String eventId) => _db
      .collection(FirebaseConstants.tracking)
      .doc(eventId)
      .collection(FirebaseConstants.pilots)
      .snapshots()
      .map((s) => s.docs
          .map((d) => GpsPointModel.fromFirestore(d, eventId))
          .toList());

  Future<void> setStartEnabled(String eventId, bool enabled) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .update({'startEnabled': enabled});

  Future<void> recordWithdrawal(String eventId, String userId,
      {List<LatLng> partialTrack = const [], String? retiredReason}) async {
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.withdrawals)
        .doc(userId)
        .set({
      'userId': userId,
      'timestamp': Timestamp.fromDate(DateTime.now()),
      if (partialTrack.isNotEmpty)
        'partialTrack': partialTrack
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      'retiredReason': ?retiredReason,
    });
    await _createNotification(eventId, {
      'type': 'withdrawal',
      'userId': userId,
    });
  }

  Stream<List<WaypointPassageRecord>> getPassagesStream(String eventId) => _db
      .collection(FirebaseConstants.tracking)
      .doc(eventId)
      .collection(FirebaseConstants.passages)
      .orderBy('timestamp')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => WaypointPassageRecord.fromFirestore(d)).toList());

  Stream<Set<String>> getWithdrawalsStream(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.withdrawals)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  Future<void> _createNotification(
      String eventId, Map<String, dynamic> data) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.notifications)
          .add({
        ...data,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'read': false,
      });

  Future<void> _sendUserNotification({
    required String recipientId,
    required NotificationType type,
    required String title,
    required String body,
  }) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(recipientId)
          .collection(FirebaseConstants.items)
          .add({
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'read': false,
      });

  Stream<List<AppNotificationModel>> getUnreadNotificationsStream(
          String userId) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(userId)
          .collection(FirebaseConstants.items)
          .where('read', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) => AppNotificationModel.fromFirestore(d))
              .toList());

  Future<void> markNotificationRead(String userId, String notifId) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(userId)
          .collection(FirebaseConstants.items)
          .doc(notifId)
          .update({'read': true});

  // Championships

  Future<String> createChampionship(ChampionshipModel c) async {
    final ref = await _db
        .collection(FirebaseConstants.championships)
        .add(c.toFirestore());
    return ref.id;
  }

  Future<void> updateChampionship(ChampionshipModel c) => _db
      .collection(FirebaseConstants.championships)
      .doc(c.id)
      .update(c.toFirestore());

  Future<void> deleteChampionship(String id) => _db
      .collection(FirebaseConstants.championships)
      .doc(id)
      .delete();

  Stream<List<ChampionshipModel>> getChampionships({String? createdBy}) {
    // Nota: orderBy('stagione') + where('createdBy') richiede un indice composito.
    // Filtriamo solo per createdBy in Firestore e ordiniamo per stagione in Dart.
    Query q = _db.collection(FirebaseConstants.championships);
    if (createdBy != null) q = q.where('createdBy', isEqualTo: createdBy);
    return q.snapshots().map((s) {
      final list =
          s.docs.map((d) => ChampionshipModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.stagione.compareTo(a.stagione));
      return list;
    });
  }

  Future<ChampionshipModel?> getChampionshipForEvent(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.championships)
        .where('eventIds', arrayContains: eventId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ChampionshipModel.fromFirestore(snap.docs.first);
  }

  Stream<ChampionshipModel?> getChampionshipById(String id) => _db
      .collection(FirebaseConstants.championships)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? ChampionshipModel.fromFirestore(doc) : null);

  Future<void> addEventToChampionship(
          String championshipId, String eventId) =>
      _db
          .collection(FirebaseConstants.championships)
          .doc(championshipId)
          .update({
        'eventIds': FieldValue.arrayUnion([eventId])
      });

  Future<void> removeEventFromChampionship(
          String championshipId, String eventId) =>
      _db
          .collection(FirebaseConstants.championships)
          .doc(championshipId)
          .update({
        'eventIds': FieldValue.arrayRemove([eventId])
      });

  Future<List<WaypointPassageRecord>> getPassagesOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.passages)
        .orderBy('timestamp')
        .get();
    return snap.docs
        .map((d) => WaypointPassageRecord.fromFirestore(d))
        .toList();
  }

  Future<List<RegistrationModel>> getRegistrationsOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .get();
    return snap.docs
        .map((d) => RegistrationModel.fromFirestore(d, eventId))
        .toList();
  }

  Future<List<TeamModel>> getTeamsOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.teams)
        .get();
    return snap.docs
        .map((d) => TeamModel.fromFirestore(d, eventId))
        .toList();
  }

  Future<Set<String>> getWithdrawalsOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.withdrawals)
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  Future<void> saveUserFcmToken(String userId, String token) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {FirebaseConstants.fcmToken: token},
        SetOptions(merge: true),
      );

  Future<void> savePreferredTeamName(String userId, String teamName) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {'preferredTeamName': teamName},
        SetOptions(merge: true),
      );

  Future<void> recordWaypointPassage({
    required String eventId,
    required String userId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
    bool recoveredStart = false,
    bool recoveredEnd = false,
    String? timingError,
    // Precisione del timing di questo passaggio: 'gate' (porta virtuale +
    // interpolazione), 'radius' (raggio) o 'recovery' (recovery
    // retroattivo/forfeit) — vedi Blocco A del timing di precisione.
    // Mostrato come badge discreto in TimingScreen (admin).
    String timingMethod = 'radius',
  }) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.passages)
          .add({
        'userId': userId,
        'waypointId': waypointId,
        'waypointNome': waypointNome,
        'timestamp': Timestamp.fromDate(timestamp),
        if (recoveredStart) 'recoveredStart': true,
        if (recoveredEnd) 'recoveredEnd': true,
        'timingError': ?timingError,
        'timingMethod': timingMethod,
      });

  /// Salva una violazione di zona a velocità controllata. Best-effort: a
  /// differenza dei passaggi waypoint (che determinano il tempo PS), una
  /// violazione persa non altera il risultato della gara in modo critico —
  /// solo la penalità non viene applicata — quindi non serve un fallback
  /// su coda offline.
  Future<void> recordSpeedZoneViolation({
    required String eventId,
    required String userId,
    required String zoneId,
    required double avgSpeedKmh,
    required double limitKmh,
    required DateTime timestamp,
  }) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.speedZoneViolations)
          .add({
        'userId': userId,
        'zoneId': zoneId,
        'avgSpeedKmh': avgSpeedKmh,
        'limitKmh': limitKmh,
        'timestamp': Timestamp.fromDate(timestamp),
      });

  Stream<List<SpeedZoneViolation>> getSpeedZoneViolationsStream(
          String eventId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.speedZoneViolations)
          .snapshots()
          .map((s) => s.docs
              .map((d) => SpeedZoneViolation.fromFirestore(d))
              .toList());

  Future<List<SpeedZoneViolation>> getSpeedZoneViolationsOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.speedZoneViolations)
        .get();
    return snap.docs
        .map((d) => SpeedZoneViolation.fromFirestore(d))
        .toList();
  }

  // ── Segnalazioni CP mancati (pilota → admin) ────────────────────────────

  Future<void> createCpDispute({
    required String eventId,
    required String pilotId,
    required String pilotName,
    required String teamName,
    required List<DisputedCp> missedCps,
    String? pilotNote,
  }) async {
    final now = DateTime.now();
    final disputeId = '${pilotId}_${now.millisecondsSinceEpoch}';
    await _db
        .collection(FirebaseConstants.cpDisputes)
        .doc(eventId)
        .collection(FirebaseConstants.disputes)
        .doc(disputeId)
        .set(CpDisputeModel(
          id: disputeId,
          eventId: eventId,
          pilotId: pilotId,
          pilotName: pilotName,
          teamName: teamName,
          missedCps: missedCps,
          pilotNote: pilotNote,
          timestamp: now,
          status: CpDisputeStatus.pending,
        ).toFirestore());
    await _createNotification(eventId, {
      'type': 'cp_dispute',
      'pilotId': pilotId,
      'pilotName': pilotName,
    });
  }

  /// Solo admin (vedi firestore.rules — bypass globale): tutte le dispute
  /// dell'evento, per la banner/lista di gestione.
  Stream<List<CpDisputeModel>> getCpDisputesStream(String eventId) => _db
      .collection(FirebaseConstants.cpDisputes)
      .doc(eventId)
      .collection(FirebaseConstants.disputes)
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => CpDisputeModel.fromFirestore(d)).toList());

  /// Fix 4 (09/08/2026) — SOLO le dispute di [pilotId] per [eventId]: la
  /// regola Firestore per un pilota non-admin richiede una query
  /// esplicitamente ristretta al proprio `pilotId` (una lettura
  /// dell'intera collezione senza filtro verrebbe negata, non
  /// silenziosamente troncata). Usata dalla UI pilota (stato della propria
  /// segnalazione), mai dall'admin (che usa [getCpDisputesStream]).
  Stream<List<CpDisputeModel>> getMyCpDisputesStream(
          String eventId, String pilotId) =>
      _db
          .collection(FirebaseConstants.cpDisputes)
          .doc(eventId)
          .collection(FirebaseConstants.disputes)
          .where('pilotId', isEqualTo: pilotId)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => CpDisputeModel.fromFirestore(d)).toList());

  /// Risolve una segnalazione CP. Se accolta, registra un passaggio
  /// sintetico per ogni CP contestato con timestamp a metà tra inizio e
  /// fine della PS (stessa risoluzione start/end usata da
  /// ClassificaEngine._computeSpeciali): da quel momento il CP risulta
  /// passato e la penalità sparisce dal calcolo senza alcuna logica
  /// speciale nel motore di classifica.
  Future<void> resolveCpDispute({
    required EventModel event,
    required String disputeId,
    required bool accept,
    required String pilotId,
    required List<DisputedCp> missedCps,
  }) async {
    final eventId = event.id;
    await _db
        .collection(FirebaseConstants.cpDisputes)
        .doc(eventId)
        .collection(FirebaseConstants.disputes)
        .doc(disputeId)
        .update({'status':
            (accept ? CpDisputeStatus.accepted : CpDisputeStatus.rejected)
                .name});

    if (accept) {
      final myPassages = (await getPassagesOnce(eventId))
          .where((p) => p.userId == pilotId)
          .toList();
      for (final cp in missedCps) {
        final special =
            event.speciali.where((s) => s.id == cp.specialeId).firstOrNull;
        if (special == null) continue;
        final iniP = myPassages
            .where((p) => p.waypointId == special.waypointInizio.id)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final finP = myPassages
            .where((p) => p.waypointId == special.waypointFine.id)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (iniP.isEmpty || finP.isEmpty) continue;
        final start = iniP.first;
        final end = finP.firstWhere(
            (p) => p.timestamp.isAfter(start.timestamp),
            orElse: () => finP.first);
        if (!end.timestamp.isAfter(start.timestamp)) continue;
        final midTs = start.timestamp
            .add((end.timestamp.difference(start.timestamp)) ~/ 2);
        await recordWaypointPassage(
          eventId: eventId,
          userId: pilotId,
          waypointId: cp.cpId,
          waypointNome: cp.cpNome,
          timestamp: midTs,
        );
      }
    }

    await _sendUserNotification(
      recipientId: pilotId,
      type: accept
          ? NotificationType.cpDisputeAccepted
          : NotificationType.cpDisputeRejected,
      title: accept
          ? '✅ Segnalazione CP accolta'
          : '❌ Segnalazione CP rifiutata',
      body: accept
          ? 'La tua segnalazione sui checkpoint mancati è stata accolta: la penalità è stata rimossa.'
          : 'La tua segnalazione sui checkpoint mancati è stata rifiutata.',
    );
  }

  // Penalty settings (documento unico 'default' nella collezione penalty_settings)

  static const _penaltyDocId = 'default';

  Stream<PenaltySettingsModel> penaltySettingsStream() => _db
      .collection(FirebaseConstants.penaltySettings)
      .doc(_penaltyDocId)
      .snapshots()
      .map((doc) => doc.exists
          ? PenaltySettingsModel.fromMap(
              doc.data() as Map<String, dynamic>)
          : const PenaltySettingsModel());

  Future<PenaltySettingsModel> getPenaltySettings() async {
    final doc = await _db
        .collection(FirebaseConstants.penaltySettings)
        .doc(_penaltyDocId)
        .get();
    if (!doc.exists) return const PenaltySettingsModel();
    return PenaltySettingsModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  Future<void> savePenaltySettings(PenaltySettingsModel settings) => _db
      .collection(FirebaseConstants.penaltySettings)
      .doc(_penaltyDocId)
      .set(settings.toMap());

  // Override penalità contestuale all'evento
  // (events/{eventId}/penalty_settings/override) — null se non impostato,
  // in tal caso si applicano i valori predefiniti globali

  static const _penaltyOverrideDocId = 'override';

  DocumentReference<Map<String, dynamic>> _eventPenaltyOverrideDoc(
          String eventId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.penaltySettings)
          .doc(_penaltyOverrideDocId);

  Stream<PenaltySettingsModel?> eventPenaltySettingsStream(String eventId) =>
      _eventPenaltyOverrideDoc(eventId).snapshots().map((doc) =>
          doc.exists ? PenaltySettingsModel.fromMap(doc.data()!) : null);

  Future<PenaltySettingsModel?> getEventPenaltySettings(String eventId) async {
    final doc = await _eventPenaltyOverrideDoc(eventId).get();
    if (!doc.exists) return null;
    return PenaltySettingsModel.fromMap(doc.data()!);
  }

  Future<void> saveEventPenaltySettings(
          String eventId, PenaltySettingsModel settings) =>
      _eventPenaltyOverrideDoc(eventId).set(settings.toMap());

  Future<void> resetEventPenaltySettings(String eventId) =>
      _eventPenaltyOverrideDoc(eventId).delete();

  /// Penalità effettive per un evento: override contestuale se presente,
  /// altrimenti i valori predefiniti globali.
  Future<PenaltySettingsModel> getEffectivePenaltySettings(
      String eventId) async {
    final override = await getEventPenaltySettings(eventId);
    if (override != null) return override;
    return getPenaltySettings();
  }
}
