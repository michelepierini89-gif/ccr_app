import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../constants/firebase_constants.dart';
import '../models/app_notification_model.dart';
import '../models/championship_model.dart';
import '../models/event_model.dart';
import '../models/penalty_settings_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';
import '../models/classifica_model.dart';

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
  Future<String> createTeam(TeamModel team) async {
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
      .set(point.toFirestore());

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
      {List<LatLng> partialTrack = const []}) async {
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

  Future<void> recordWaypointPassage({
    required String eventId,
    required String userId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
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
      });

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
