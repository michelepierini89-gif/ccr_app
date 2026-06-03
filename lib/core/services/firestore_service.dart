import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firebase_constants.dart';
import '../models/event_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';
import '../models/classifica_model.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

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
  }) async {
    final reg = RegistrationModel(
      userId: userId,
      eventId: eventId,
      nome: nome,
      cognome: cognome,
      stato: RegistrationStatus.inAttesa,
      squadraId: squadraId,
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
  ) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.iscritti)
          .doc(userId)
          .update({'stato': stato.name});

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

  Future<void> recordWithdrawal(String eventId, String userId) async {
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.withdrawals)
        .doc(userId)
        .set({
      'userId': userId,
      'timestamp': Timestamp.fromDate(DateTime.now()),
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
}
