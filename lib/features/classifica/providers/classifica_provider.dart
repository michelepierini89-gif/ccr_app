import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../admin/providers/admin_provider.dart';
import '../../auth/providers/auth_provider.dart';

final passagesStreamProvider =
    StreamProvider.family<List<WaypointPassageRecord>, String>(
        (ref, eventId) =>
            ref.watch(firestoreServiceProvider).getPassagesStream(eventId));

final withdrawalsStreamProvider =
    StreamProvider.family<Set<String>, String>((ref, eventId) =>
        ref.watch(firestoreServiceProvider).getWithdrawalsStream(eventId));

/// Violazioni zona a velocità controllata, in tempo reale (visibili solo
/// all'admin tramite ClassificaEngine/timing_screen).
final speedZoneViolationsStreamProvider =
    StreamProvider.family<List<SpeedZoneViolation>, String>((ref, eventId) =>
        ref
            .watch(firestoreServiceProvider)
            .getSpeedZoneViolationsStream(eventId));

/// Impostazioni penalità predefinite (globali) in real-time da Firestore.
final penaltySettingsProvider = StreamProvider<PenaltySettingsModel>((ref) =>
    ref.watch(firestoreServiceProvider).penaltySettingsStream());

/// Override penalità contestuale all'evento (null se non impostato).
final eventPenaltyOverrideProvider =
    StreamProvider.family<PenaltySettingsModel?, String>((ref, eventId) =>
        ref.watch(firestoreServiceProvider).eventPenaltySettingsStream(eventId));

/// Tempi ufficiali ricalcolati post-gara (Blocco B), in tempo reale —
/// la classifica li preferisce ai tempi live quando presenti per una PS.
final officialTimesStreamProvider = StreamProvider.family<
    Map<String, Map<String, OfficialSpecialTime>>, String>((ref, eventId) =>
    ref.watch(firestoreServiceProvider).officialTimesStream(eventId));

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
  final penaltyAv = ref.watch(penaltySettingsProvider);
  final penaltyOverrideAv = ref.watch(eventPenaltyOverrideProvider(eventId));

  // tracking/{eventId}/pilots è leggibile solo dagli admin (privacy GPS):
  // i piloti non devono sottoscriversi a quello stream, altrimenti
  // Firestore restituisce permission-denied. La classifica per i piloti
  // viene quindi calcolata senza il badge "LIVE".
  final isAdmin =
      ref.watch(currentUserModelProvider).valueOrNull?.role == UserRole.admin;
  final liveAv = isAdmin
      ? ref.watch(liveTrackingProvider(eventId))
      : const AsyncValue<List<GpsPointModel>>.data(<GpsPointModel>[]);

  // Le violazioni zona velocità servono al motore di classifica per TUTTI
  // (anche il pilota deve vedere la penalità nel proprio tempo finale); il
  // dettaglio (nome zona, velocità) viene mostrato solo all'admin a livello
  // di UI in timing_screen.dart, non qui.
  final speedViolationsAv =
      ref.watch(speedZoneViolationsStreamProvider(eventId));
  final officialTimesAv = ref.watch(officialTimesStreamProvider(eventId));

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
    penalties: penaltyOverrideAv.valueOrNull ??
        penaltyAv.valueOrNull ??
        const PenaltySettingsModel(),
    speedZoneViolations: speedViolationsAv.valueOrNull ?? [],
    officialTimesByUserId: officialTimesAv.valueOrNull ?? {},
  ));
});

/// Calcola la classifica di campionato (con scarto dei 3 risultati peggiori),
/// ricalcolando la classifica di ogni gara inclusa nel campionato.
final championshipStandingsProvider =
    FutureProvider.family<ChampionshipStandings, String>(
        (ref, championshipId) async {
  final svc = ref.watch(firestoreServiceProvider);

  final championship = await svc.getChampionshipById(championshipId).first;
  if (championship == null || championship.eventIds.isEmpty) {
    return const ChampionshipStandings(teams: []);
  }

  final events = <EventModel>[];
  final results = <EventResults>[];

  for (final eventId in championship.eventIds) {
    final event = await svc.getEvent(eventId);
    if (event == null) continue;
    events.add(event);

    final penalties = await svc.getEffectivePenaltySettings(eventId);
    final passages = await svc.getPassagesOnce(eventId);
    final registrations = await svc.getRegistrationsOnce(eventId);
    final teams = await svc.getTeamsOnce(eventId);
    final withdrawals = await svc.getWithdrawalsOnce(eventId);
    final speedZoneViolations = await svc.getSpeedZoneViolationsOnce(eventId);
    final officialTimes = await svc.getOfficialTimesOnce(eventId);

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: registrations,
      teams: teams,
      withdrawals: withdrawals,
      liveTracking: const <GpsPointModel>[],
      penalties: penalties,
      speedZoneViolations: speedZoneViolations,
      officialTimesByUserId: officialTimes,
    );

    results.add(EventResults(eventId: eventId, entries: entries));
  }

  return ClassificaEngine.computeChampionship(championship, events, results);
});

/// entryId (teamId o userId) del pilota corrente in un campionato, basato
/// sulla sua iscrizione (approvata) a una qualunque gara del campionato.
final myChampionshipEntryIdProvider =
    FutureProvider.family<String?, String>((ref, championshipId) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  final svc = ref.watch(firestoreServiceProvider);

  final championship = await svc.getChampionshipById(championshipId).first;
  if (championship == null) return null;

  for (final eventId in championship.eventIds) {
    final regs = await svc.getRegistrationsOnce(eventId);
    final myReg = regs.where((r) => r.userId == user.uid).firstOrNull;
    if (myReg != null && myReg.stato == RegistrationStatus.approvato) {
      return myReg.squadraId ?? myReg.userId;
    }
  }
  return null;
});
