import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/services/firestore_service.dart';
import '../../auth/providers/auth_provider.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

final adminEventsProvider = StreamProvider<List<EventModel>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).getEvents(createdBy: user.uid);
});

final registrationsProvider =
    StreamProvider.family<List<RegistrationModel>, String>((ref, eventId) {
  return ref.watch(firestoreServiceProvider).getRegistrations(eventId);
});

final teamsProvider =
    StreamProvider.family<List<TeamModel>, String>((ref, eventId) {
  return ref.watch(firestoreServiceProvider).getTeams(eventId);
});

final liveTrackingProvider =
    StreamProvider.family<List<GpsPointModel>, String>((ref, eventId) {
  return ref.watch(firestoreServiceProvider).getPilotTracking(eventId);
});
