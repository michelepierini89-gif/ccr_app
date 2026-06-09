import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/gps_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';

final eventProvider =
    FutureProvider.family<EventModel?, String>((ref, id) async {
  return ref.read(firestoreServiceProvider).getEvent(id);
});

final openEventsProvider = StreamProvider<List<EventModel>>((ref) {
  return ref.watch(firestoreServiceProvider).getOpenEvents();
});

final archivedEventsProvider = StreamProvider<List<EventModel>>((ref) {
  return ref.watch(firestoreServiceProvider).getArchivedEvents();
});

final myRegistrationsProvider =
    StreamProvider<List<RegistrationModel>>((ref) async* {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return;
  final events = await ref.watch(openEventsProvider.future);
  final service = ref.watch(firestoreServiceProvider);
  final regs = <RegistrationModel>[];
  for (final event in events) {
    final reg = await service.getMyRegistration(event.id, user.uid);
    if (reg != null) regs.add(reg);
  }
  yield regs;
});

final myRegistrationStreamProvider =
    StreamProvider.family<RegistrationModel?, String>((ref, eventId) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref
      .watch(firestoreServiceProvider)
      .streamMyRegistration(eventId, user.uid);
});

final gpsServiceProvider = ChangeNotifierProvider<GpsService>((ref) {
  return GpsService(
    ref.watch(firestoreServiceProvider),
    ref.watch(offlineQueueProvider),
  );
});
