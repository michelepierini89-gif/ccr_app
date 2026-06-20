import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/imu_fusion_service.dart';
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

/// Registrazioni approvate del pilota loggato per le gare archiviate
/// (usato per filtrare la sezione "Gare passate").
final myArchivedRegistrationsProvider =
    StreamProvider<List<RegistrationModel>>((ref) async* {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return;
  final events = await ref.watch(archivedEventsProvider.future);
  final service = ref.watch(firestoreServiceProvider);
  final regs = <RegistrationModel>[];
  for (final event in events) {
    final reg = await service.getMyRegistration(event.id, user.uid);
    if (reg != null && reg.stato == RegistrationStatus.approvato) {
      regs.add(reg);
    }
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

final imuFusionServiceProvider = ChangeNotifierProvider<ImuFusionService>((ref) {
  return ImuFusionService();
});

final gpsServiceProvider = ChangeNotifierProvider<GpsService>((ref) {
  // `ref.read`, non `ref.watch`: GpsService usa questi servizi come
  // dipendenze fisse, non deve essere ricreato ogni volta che
  // OfflineQueueService o ImuFusionService chiamano notifyListeners()
  // (es. ImuFusionService.updateWithGps() al primo fix GPS). Un
  // `ref.watch` qui distruggeva e ricreava l'istanza di GpsService,
  // azzerando `_isRecording` e facendo tornare la UI alla schermata
  // pre-avvio non appena arrivava il primo fix GPS.
  return GpsService(
    ref.read(firestoreServiceProvider),
    ref.read(offlineQueueProvider),
    ref.read(imuFusionServiceProvider),
  );
});

/// Streams the raw tracking doc for the logged-in pilot in a given event.
/// Returns null if the doc doesn't exist yet (pilot never started GPS).
final myPilotStatusProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>?, String>(
        (ref, eventId) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(firestoreServiceProvider)
      .myPilotStatusStream(eventId, user.uid);
});
