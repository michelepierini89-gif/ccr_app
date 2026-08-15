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
///
/// Nello stesso giro di eventi calcola anche le metriche ristrette alla
/// squadra preferita del pilota (`UserModel.preferredTeamName`, confronto
/// case-insensitive col nome squadra dell'evento) e l'elenco dei compagni
/// con cui si è corso più spesso in quella squadra — evita un secondo giro
/// completo di query N+1 sugli stessi eventi.
final pilotStatsProvider = FutureProvider<PilotStatsModel>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const PilotStatsModel();
  final svc = ref.watch(firestoreServiceProvider);
  final userModel = await ref.watch(currentUserModelProvider.future);
  final preferredTeamName = userModel?.preferredTeamName?.trim().toLowerCase();

  final allEvents = await svc.getEvents().first;

  var gareDisputate = 0;
  var gareVinte = 0;
  var garePodio = 0;
  var specialiVinte = 0;
  var specialiPodio = 0;

  var prefGareDisputate = 0;
  var prefGareVinte = 0;
  var prefGarePodio = 0;
  var prefSpecialiVinte = 0;
  var prefSpecialiPodio = 0;
  final compagniCount = <String, int>{};
  final compagniNomi = <String, (String, String)>{};
  final teamNameCounts = <String, int>{};
  final teamNameDisplay = <String, String>{};

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

    var raceSpecialiVinte = 0;
    var raceSpecialiPodio = 0;
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
      if (rank == 1) raceSpecialiVinte++;
      if (rank <= 3) raceSpecialiPodio++;
    }

    // Squadra preferita: stesso confronto case-insensitive usato in
    // team_screen.dart/event_detail_screen.dart.
    final myTeam = reg.squadraId == null
        ? null
        : teams.where((t) => t.id == reg.squadraId).firstOrNull;
    final raceTeamDisplayName = (myTeam?.nome ?? reg.teamName)?.trim();
    final raceTeamName = raceTeamDisplayName?.toLowerCase();
    if (raceTeamDisplayName != null && raceTeamDisplayName.isNotEmpty) {
      teamNameCounts[raceTeamName!] = (teamNameCounts[raceTeamName] ?? 0) + 1;
      teamNameDisplay.putIfAbsent(raceTeamName, () => raceTeamDisplayName);
    }
    if (preferredTeamName != null &&
        preferredTeamName.isNotEmpty &&
        raceTeamName == preferredTeamName) {
      prefGareDisputate++;
      if (myEntry.posizione == 1) prefGareVinte++;
      if (myEntry.posizione >= 1 && myEntry.posizione <= 3) prefGarePodio++;
      prefSpecialiVinte += raceSpecialiVinte;
      prefSpecialiPodio += raceSpecialiPodio;

      if (myTeam != null) {
        for (final memberId in myTeam.membriIds) {
          if (memberId == user.uid) continue;
          compagniCount[memberId] = (compagniCount[memberId] ?? 0) + 1;
          if (!compagniNomi.containsKey(memberId)) {
            final memberReg =
                registrations.where((r) => r.userId == memberId).firstOrNull;
            compagniNomi[memberId] =
                (memberReg?.nome ?? '', memberReg?.cognome ?? '');
          }
        }
      }
    }
  }

  final compagni = compagniCount.entries.map((e) {
    final names = compagniNomi[e.key] ?? ('', '');
    return TeammateStat(
      userId: e.key,
      nome: names.$1,
      cognome: names.$2,
      gareInsieme: e.value,
    );
  }).toList()
    ..sort((a, b) => b.gareInsieme.compareTo(a.gareInsieme));

  final raceTeamNames = teamNameCounts.keys.toList()
    ..sort((a, b) => teamNameCounts[b]!.compareTo(teamNameCounts[a]!));

  return PilotStatsModel(
    gareDisputate: gareDisputate,
    gareVinte: gareVinte,
    garePodio: garePodio,
    specialiVinte: specialiVinte,
    specialiPodio: specialiPodio,
    preferredTeamGareDisputate: prefGareDisputate,
    preferredTeamGareVinte: prefGareVinte,
    preferredTeamGarePodio: prefGarePodio,
    preferredTeamSpecialiVinte: prefSpecialiVinte,
    preferredTeamSpecialiPodio: prefSpecialiPodio,
    preferredTeamCompagni: compagni,
    raceTeamNames: raceTeamNames.map((k) => teamNameDisplay[k]!).toList(),
  );
});
