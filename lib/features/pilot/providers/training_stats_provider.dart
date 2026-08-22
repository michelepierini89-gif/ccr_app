import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../../core/services/training_classifica_engine.dart';
import '../../admin/providers/admin_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Step 47, Parte 2F — riepilogo personale di un evento di allenamento:
/// tentativi effettuati e migliori tempi PERSONALI (non di squadra, a
/// differenza della classifica evento) per PS, indipendente dalle
/// statistiche di gara.
class TrainingEventStats {
  final String eventId;
  final String eventNome;
  final int tentativiCompletati;
  final Map<String, Duration> migliorTempoPersonalePerPs;

  const TrainingEventStats({
    required this.eventId,
    required this.eventNome,
    required this.tentativiCompletati,
    required this.migliorTempoPersonalePerPs,
  });
}

final trainingStatsProvider =
    FutureProvider<List<TrainingEventStats>>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const [];
  final svc = ref.watch(firestoreServiceProvider);

  final allEvents = await svc.getEvents().first;
  final trainingEvents = allEvents.where((e) => e.isAllenamento).toList();

  final result = <TrainingEventStats>[];
  for (final event in trainingEvents) {
    final attempts = await svc.attemptsStream(event.id, user.uid).first;
    final completed =
        attempts.where((a) => a.status == AttemptStatus.completed).toList();
    if (completed.isEmpty) continue;

    final penalties = await svc.getEffectivePenaltySettings(event.id);
    final best = <String, Duration>{};
    for (final attempt in completed) {
      final variant =
          event.routeVariant(attempt.routeVariantId ?? event.activeRouteId) ??
              event.routeAAsVariant;
      final passages = await svc.getAttemptPassagesOnce(
          event.id, user.uid, attempt.id);
      final violations = await svc.getAttemptSpeedZoneViolationsOnce(
          event.id, user.uid, attempt.id);
      final speciali = ClassificaEngine.computeSpeciali(
          variant, passages, violations, penalties, {user.uid}, const {});
      for (final st in speciali) {
        final valido = !st.skipped &&
            !st.notDetected &&
            st.timingError != 'rilevamento_non_valido';
        if (!valido) continue;
        final current = best[st.specialeId];
        if (current == null || st.tempo < current) {
          best[st.specialeId] = st.tempo;
        }
      }
    }

    result.add(TrainingEventStats(
      eventId: event.id,
      eventNome: event.nome,
      tentativiCompletati: completed.length,
      migliorTempoPersonalePerPs: best,
    ));
  }
  return result;
});

/// Rifiniture Step 47 — record di SQUADRA su un evento di allenamento,
/// mostrato direttamente nella pagina dettaglio evento del pilota (senza
/// passare dalle Statistiche): riusa [TrainingClassificaEngine] filtrato
/// alla sola squadra dell'utente. Sorgente dati riscritta allo Step 51 —
/// legge `tracking/{eventId}/trainingResults` (riepilogo pubblico) invece
/// di una collectionGroup query su `attempts` più le passages/violazioni
/// di ogni membro (mai autorizzata per un non-admin, vedi
/// [trainingClassificaProvider]).
final myTrainingTeamBestProvider =
    FutureProvider.family<TrainingClassificaEntry?, String>(
        (ref, eventId) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  final svc = ref.watch(firestoreServiceProvider);

  final event = await svc.getEvent(eventId);
  if (event == null || !event.isAllenamento) return null;

  final allRegs = await svc.getRegistrations(eventId).first;
  final myReg = allRegs.where((r) => r.userId == user.uid).firstOrNull;
  if (myReg?.squadraId == null) return null;

  final teamRegs = allRegs
      .where((r) =>
          r.squadraId == myReg!.squadraId &&
          r.stato == RegistrationStatus.approvato)
      .toList();
  final memberIds = teamRegs.map((r) => r.userId).toSet();

  final allResults = await svc.getTrainingResultsForEvent(eventId);
  final teamResults =
      allResults.where((r) => memberIds.contains(r.userId)).toList();
  if (teamResults.isEmpty) return null;

  final teams = await svc.getTeams(eventId).first;

  final userNames = {
    for (final r in teamRegs) r.userId: '${r.nome} ${r.cognome}',
  };

  final entries = TrainingClassificaEngine.compute(
    event: event,
    registrations: teamRegs,
    teams: teams,
    results: teamResults,
    userNames: userNames,
  );
  return entries.firstOrNull;
});
