import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../admin/providers/admin_provider.dart';

final passagesStreamProvider =
    StreamProvider.family<List<WaypointPassageRecord>, String>(
        (ref, eventId) =>
            ref.watch(firestoreServiceProvider).getPassagesStream(eventId));

final withdrawalsStreamProvider =
    StreamProvider.family<Set<String>, String>((ref, eventId) =>
        ref.watch(firestoreServiceProvider).getWithdrawalsStream(eventId));

/// Impostazioni penalità in real-time da Firestore.
final penaltySettingsProvider = StreamProvider<PenaltySettingsModel>((ref) =>
    ref.watch(firestoreServiceProvider).penaltySettingsStream());

/// Computes the live ranking. Returns `AsyncValue<List<ClassificaEntry>>`.
/// Re-runs whenever any underlying stream emits a new value.
final classificaProvider =
    Provider.family<AsyncValue<List<ClassificaEntry>>, String>(
        (ref, eventId) {
  final eventAv = ref.watch(eventStreamProvider(eventId));
  final passAv = ref.watch(passagesStreamProvider(eventId));
  final regsAv = ref.watch(registrationsProvider(eventId));
  final teamsAv = ref.watch(teamsProvider(eventId));
  final wdAv = ref.watch(withdrawalsStreamProvider(eventId));
  final liveAv = ref.watch(liveTrackingProvider(eventId));
  final penaltyAv = ref.watch(penaltySettingsProvider);

  if (eventAv.isLoading || passAv.isLoading || regsAv.isLoading) {
    return const AsyncValue.loading();
  }
  final err = eventAv.error ?? passAv.error ?? regsAv.error;
  if (err != null) return AsyncValue.error(err, StackTrace.empty);

  final event = eventAv.valueOrNull;
  final passages = passAv.valueOrNull;
  final regs = regsAv.valueOrNull;
  if (event == null || passages == null || regs == null) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(ClassificaEngine.compute(
    event: event,
    passages: passages,
    registrations: regs,
    teams: teamsAv.valueOrNull ?? [],
    withdrawals: wdAv.valueOrNull ?? {},
    liveTracking: liveAv.valueOrNull ?? [],
    penalties: penaltyAv.valueOrNull ?? const PenaltySettingsModel(),
  ));
});
