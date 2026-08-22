import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attempt_model.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/route_variant_model.dart';
import '../../../core/services/classifica_engine.dart';
import '../../admin/providers/admin_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'training_stats_provider.dart';

/// Il tempo di UNA prova speciale in UN tentativo — vedi
/// [AttemptHistoryEntry]. [tempo] è `null` quando questo tentativo non ha
/// completato quella PS (nessun passaggio inizio+fine registrato).
class AttemptSpecialRow {
  final String specialeId;
  final String specialeNome;
  final int ordine;
  final SpecialTempo? tempo;

  /// Il tempo di questo tentativo è il miglior tempo PERSONALE del pilota
  /// su questa PS (fra tutti i propri tentativi completati).
  final bool isPersonalRecord;

  /// Il tempo di questo tentativo è quello che la classifica di SQUADRA
  /// (`TrainingClassificaEngine`, miglior tempo fra tutti i tentativi di
  /// tutti i membri) usa per questa PS — "il giro che conta".
  final bool countsForClassifica;

  const AttemptSpecialRow({
    required this.specialeId,
    required this.specialeNome,
    required this.ordine,
    required this.tempo,
    required this.isPersonalRecord,
    required this.countsForClassifica,
  });
}

/// Un tentativo del pilota corrente con i tempi di ogni PS calcolati —
/// storico completo (punto 3 del test sul campo 22/08/2026), non solo il
/// riepilogo di squadra già mostrato in pagina evento
/// ([myTrainingTeamBestProvider]).
class AttemptHistoryEntry {
  final AttemptModel attempt;
  final List<AttemptSpecialRow> speciali;

  const AttemptHistoryEntry({required this.attempt, required this.speciali});
}

/// Tutti i tentativi del pilota corrente su [eventId], più recente prima
/// (stesso ordine di `attemptsStream`), con i tempi PS di ciascuno e i due
/// indicatori richiesti: record personale e "conta per la classifica".
final myAttemptsHistoryProvider =
    FutureProvider.family<List<AttemptHistoryEntry>, String>(
        (ref, eventId) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const [];
  final svc = ref.watch(firestoreServiceProvider);

  final event = await svc.getEvent(eventId);
  if (event == null || !event.isAllenamento) return const [];

  final attempts = await svc.attemptsStream(eventId, user.uid).first;
  if (attempts.isEmpty) return const [];

  final penalties = await svc.getEffectivePenaltySettings(eventId);

  final variantByAttempt = <String, RouteVariantModel>{};
  final speicaliByAttempt = <String, List<SpecialTempo>>{};
  for (final attempt in attempts) {
    final variant =
        event.routeVariant(attempt.routeVariantId ?? event.activeRouteId) ??
            event.routeAAsVariant;
    variantByAttempt[attempt.id] = variant;
    final passages =
        await svc.getAttemptPassagesOnce(eventId, user.uid, attempt.id);
    final violations = await svc.getAttemptSpeedZoneViolationsOnce(
        eventId, user.uid, attempt.id);
    speicaliByAttempt[attempt.id] = ClassificaEngine.computeSpeciali(
        variant, passages, violations, penalties, {user.uid}, const {});
  }

  // Record personale per PS — solo tentativi completati e tempi validi
  // (mai un forfait/salto/rilevamento non valido, non sono tempi reali).
  final personalBest = <String, Duration>{};
  for (final attempt in attempts) {
    if (attempt.status != AttemptStatus.completed) continue;
    for (final st in speicaliByAttempt[attempt.id] ?? const []) {
      final valid = !st.skipped &&
          !st.notDetected &&
          st.timingError != 'rilevamento_non_valido';
      if (!valid) continue;
      final current = personalBest[st.specialeId];
      if (current == null || st.tempo < current) {
        personalBest[st.specialeId] = st.tempo;
      }
    }
  }

  // "Conta per la classifica" — confronta con il tentativo di squadra
  // vincente per ogni PS (già calcolato da myTrainingTeamBestProvider,
  // Step 48): nessuna duplicazione della query su tutta la squadra qui.
  final teamEntry =
      await ref.watch(myTrainingTeamBestProvider(eventId).future);
  final teamBest = teamEntry?.bestBySpecialId ?? const {};

  final result = <AttemptHistoryEntry>[];
  for (final attempt in attempts) {
    final variant = variantByAttempt[attempt.id]!;
    final activeSpeciali = [...variant.speciali]
      ..sort((a, b) => a.ordine.compareTo(b.ordine));
    final bySpecialId = {
      for (final st in speicaliByAttempt[attempt.id]!) st.specialeId: st,
    };
    final rows = <AttemptSpecialRow>[];
    for (final s in activeSpeciali) {
      if (s.annullata) continue;
      final st = bySpecialId[s.id];
      final valid = st != null &&
          !st.skipped &&
          !st.notDetected &&
          st.timingError != 'rilevamento_non_valido';
      final isPR = valid && personalBest[s.id] == st.tempo;
      final counts = valid &&
          teamBest[s.id]?.userId == user.uid &&
          teamBest[s.id]?.attemptNumber == attempt.attemptNumber;
      rows.add(AttemptSpecialRow(
        specialeId: s.id,
        specialeNome: s.nome,
        ordine: s.ordine,
        tempo: st,
        isPersonalRecord: isPR,
        countsForClassifica: counts,
      ));
    }
    result.add(AttemptHistoryEntry(attempt: attempt, speciali: rows));
  }
  return result;
});
