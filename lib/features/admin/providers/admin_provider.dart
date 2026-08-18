import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/user_model.dart';
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

final eventStreamProvider =
    StreamProvider.family<EventModel?, String>((ref, id) {
  return ref.watch(firestoreServiceProvider).getEventById(id);
});

/// Step 47, Parte 2B/2E — tentativi di un pilota su un evento di
/// allenamento, più recente prima. Usato dalla vista admin "tentativi per
/// pilota" e dall'elenco tentativi lato pilota.
final attemptsStreamProvider = StreamProvider.family<List<AttemptModel>,
    ({String eventId, String userId})>((ref, key) {
  return ref
      .watch(firestoreServiceProvider)
      .attemptsStream(key.eventId, key.userId);
});

/// Elenco utenti registrati all'app (Step 42) — schermata admin dedicata,
/// distinta dalle iscrizioni ai singoli eventi.
final allUsersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  return ref.watch(firestoreServiceProvider).getAllUsersStream();
});

/// Numero di eventi a cui un utente ha partecipato (iscrizioni approvate),
/// per riga dell'elenco utenti admin. `.future` è cacheato per userId da
/// Riverpod: ogni riga lo richiede una volta sola.
final userEventsCountProvider =
    FutureProvider.family<int, String>((ref, userId) {
  return ref
      .watch(firestoreServiceProvider)
      .countApprovedRegistrationsForUser(userId);
});
