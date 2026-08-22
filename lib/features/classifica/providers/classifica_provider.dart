import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../../core/services/training_classifica_engine.dart';
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

/// Percorso alternativo (10/08/2026, Parte 5) — userId -> routeVariantId
/// ('A'/'B'), leggibile da tutti gli autenticati (a differenza del
/// documento tracking/pilots, privato): la classifica lo usa per calcolare
/// i tempi di ogni pilota sulla variante con cui ha REALMENTE corso.
final routeVariantByUserProvider =
    StreamProvider.family<Map<String, String>, String>((ref, eventId) => ref
        .watch(firestoreServiceProvider)
        .routeVariantByUserStream(eventId));

/// Classifica di un evento di allenamento (bug segnalato dopo il primo test
/// sul campo, 22/08/2026): "I miei tempi"/"Classifica" risultavano vuoti
/// perché [classificaProvider] leggeva SEMPRE `tracking/{eventId}/passages`
/// (percorso di gara), mai le sottocollezioni `attempts/{attemptId}/passages`
/// dove l'allenamento scrive davvero (verificato su Firestore: i tentativi
/// erano presenti e completi, il problema era solo in lettura — CASO B).
/// Converte [TrainingClassificaEntry] (miglior tempo per PS fra TUTTI i
/// tentativi completati di TUTTI i membri squadra, vedi
/// [TrainingClassificaEngine]) in [ClassificaEntry] per riusare
/// TimingScreen/ClassificaScreen senza duplicare la UI — stesso approccio
/// già usato da `myTrainingTeamBestProvider` (Step 48), qui esteso a TUTTE
/// le squadre dell'evento invece della sola squadra dell'utente.
final trainingClassificaProvider =
    FutureProvider.family<List<ClassificaEntry>, String>(
        (ref, eventId) async {
  final svc = ref.watch(firestoreServiceProvider);
  final event = await svc.getEvent(eventId);
  if (event == null || !event.isAllenamento) return const [];

  final regs = await ref.watch(registrationsProvider(eventId).future);
  final approved =
      regs.where((r) => r.stato == RegistrationStatus.approvato).toList();

  final allCompleted = await svc.getCompletedAttemptsForEvent(eventId);
  if (allCompleted.isEmpty) return const [];

  final teams = await ref.watch(teamsProvider(eventId).future);
  final penalties = await svc.getEffectivePenaltySettings(eventId);

  final passagesByAttemptId = <String, List<WaypointPassageRecord>>{};
  final violationsByAttemptId = <String, List<SpeedZoneViolation>>{};
  for (final attempt in allCompleted) {
    passagesByAttemptId[attempt.id] = await svc.getAttemptPassagesOnce(
        eventId, attempt.userId, attempt.id);
    violationsByAttemptId[attempt.id] =
        await svc.getAttemptSpeedZoneViolationsOnce(
            eventId, attempt.userId, attempt.id);
  }

  final userNames = {
    for (final r in approved) r.userId: r.nomeCompleto,
  };

  final entries = TrainingClassificaEngine.compute(
    event: event,
    registrations: approved,
    teams: teams,
    completedAttempts: allCompleted,
    passagesByAttemptId: passagesByAttemptId,
    speedViolationsByAttemptId: violationsByAttemptId,
    userNames: userNames,
    penalties: penalties,
  );

  final memberIdsBySquadra = <String, Set<String>>{};
  for (final r in approved) {
    if (r.squadraId == null) continue;
    memberIdsBySquadra.putIfAbsent(r.squadraId!, () => {}).add(r.userId);
  }

  return entries
      .map((e) => ClassificaEntry(
            entryId: e.entryId,
            teamNome: e.teamNome,
            membriNomi: e.membriNomi,
            membriIds: memberIdsBySquadra[e.entryId] ?? const {},
            specialiCompletati:
                e.bestBySpecialId.values.map((b) => b.tempo).toList(),
            totaleSpeciali: e.totaleSpeciali,
            tempoTotale: e.tempoTotale,
            punteggioTotale: e.punteggioTotale,
            posizione: e.posizione,
            ritirato: false,
            isLive: false,
          ))
      .toList();
});

/// Computes the live ranking. Returns `AsyncValue<List<ClassificaEntry>>`.
/// Re-runs whenever any underlying stream emits a new value.
final classificaProvider =
    Provider.family<AsyncValue<List<ClassificaEntry>>, String>(
        (ref, eventId) {
  final eventAv = ref.watch(eventStreamProvider(eventId));
  final event = eventAv.valueOrNull;

  // Allenamento — percorso di lettura completamente diverso (vedi
  // trainingClassificaProvider sopra): nessuna delle stream di gara sotto
  // (passages/withdrawals/live tracking) contiene mai dati per un
  // allenamento, quindi non ha senso aspettarle prima di rispondere.
  if (event != null && event.isAllenamento) {
    return ref.watch(trainingClassificaProvider(eventId));
  }
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
  final routeVariantByUserAv = ref.watch(routeVariantByUserProvider(eventId));

  if (eventAv.isLoading || passAv.isLoading || regsAv.isLoading) {
    return const AsyncValue.loading();
  }
  final err = eventAv.error ?? passAv.error ?? regsAv.error;
  if (err != null) return AsyncValue.error(err, StackTrace.empty);

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
    routeVariantByUserId: routeVariantByUserAv.valueOrNull ?? {},
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
    final routeVariantByUserId = await svc.getRouteVariantByUserOnce(eventId);

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
      routeVariantByUserId: routeVariantByUserId,
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
