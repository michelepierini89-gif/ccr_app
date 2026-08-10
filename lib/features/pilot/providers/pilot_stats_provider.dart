import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/pilot_stats_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../admin/providers/admin_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Calcola le statistiche del pilota loggato ricalcolando la classifica di
/// ogni gara a cui ha un'iscrizione approvata (stesso pattern N+1 di
/// `championshipStandingsProvider`). Le statistiche sono di squadra: una
/// vittoria/podio di squadra conta per tutti i piloti della squadra.
final pilotStatsProvider = FutureProvider<PilotStatsModel>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const PilotStatsModel();
  final svc = ref.watch(firestoreServiceProvider);

  final allEvents = await svc.getEvents().first;

  var gareDisputate = 0;
  var gareVinte = 0;
  var garePodio = 0;
  var specialiVinte = 0;
  var specialiPodio = 0;

  for (final event in allEvents) {
    final reg = await svc.getMyRegistration(event.id, user.uid);
    if (reg == null || reg.stato != RegistrationStatus.approvato) continue;
    gareDisputate++;

    final penalties = await svc.getEffectivePenaltySettings(event.id);
    final passages = await svc.getPassagesOnce(event.id);
    final registrations = await svc.getRegistrationsOnce(event.id);
    final teams = await svc.getTeamsOnce(event.id);
    final withdrawals = await svc.getWithdrawalsOnce(event.id);
    final speedZoneViolations =
        await svc.getSpeedZoneViolationsOnce(event.id);
    final routeVariantByUserId =
        await svc.getRouteVariantByUserOnce(event.id);

    final entries = ClassificaEngine.compute(
      event: event,
      passages: passages,
      registrations: registrations,
      teams: teams,
      withdrawals: withdrawals,
      liveTracking: const <GpsPointModel>[],
      penalties: penalties,
      speedZoneViolations: speedZoneViolations,
      routeVariantByUserId: routeVariantByUserId,
    );

    final myEntryId = reg.squadraId ?? reg.userId;
    final myEntry = entries.where((e) => e.entryId == myEntryId).firstOrNull;
    if (myEntry == null) continue;

    if (myEntry.posizione == 1) gareVinte++;
    if (myEntry.posizione >= 1 && myEntry.posizione <= 3) garePodio++;

    for (final special in myEntry.specialiCompletati) {
      if (special.isInvalidTiming) continue;
      // Posizione della speciale: numero di team con un tempo valido
      // migliore del mio, +1 (i pari merito condividono la stessa posizione).
      final betterCount = entries.where((e) {
        if (e.entryId == myEntryId) return false;
        final t = e.specialiCompletati
            .where((s) =>
                s.specialeId == special.specialeId && !s.isInvalidTiming)
            .firstOrNull;
        return t != null && t.tempo < special.tempo;
      }).length;
      final rank = betterCount + 1;
      if (rank == 1) specialiVinte++;
      if (rank <= 3) specialiPodio++;
    }
  }

  return PilotStatsModel(
    gareDisputate: gareDisputate,
    gareVinte: gareVinte,
    garePodio: garePodio,
    specialiVinte: specialiVinte,
    specialiPodio: specialiPodio,
  );
});
