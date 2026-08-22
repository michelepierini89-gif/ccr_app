import '../models/classifica_model.dart';
import '../models/event_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/training_result_model.dart';

/// Il miglior tempo di una squadra su una PS (Step 47, Parte 2C), con chi
/// l'ha realizzato e in quale tentativo — a differenza della gara (dove il
/// tempo di squadra è implicito nel pool dei passaggi di tutti i membri),
/// qui serve mostrare esplicitamente il contributo individuale.
class TrainingSpecialBest {
  final SpecialTempo tempo;
  final String userId;
  final String userName;
  final int attemptNumber;

  const TrainingSpecialBest({
    required this.tempo,
    required this.userId,
    required this.userName,
    required this.attemptNumber,
  });
}

class TrainingClassificaEntry {
  final String entryId; // squadraId
  final String teamNome;
  final List<String> membriNomi;

  /// specialeId -> miglior tempo, solo per le PS effettivamente completate
  /// da almeno un tentativo di un membro — le altre semplicemente non
  /// compaiono (nessun tempo forfettario, vedi richiesta).
  final Map<String, TrainingSpecialBest> bestBySpecialId;

  final int specialiCompletati;
  final int totaleSpeciali;
  final Duration tempoTotale;
  final int punteggioTotale;
  final int posizione;

  const TrainingClassificaEntry({
    required this.entryId,
    required this.teamNome,
    required this.membriNomi,
    required this.bestBySpecialId,
    required this.specialiCompletati,
    required this.totaleSpeciali,
    required this.tempoTotale,
    required this.punteggioTotale,
    required this.posizione,
  });

  TrainingClassificaEntry copyWith({int? punteggioTotale, int? posizione}) =>
      TrainingClassificaEntry(
        entryId: entryId,
        teamNome: teamNome,
        membriNomi: membriNomi,
        bestBySpecialId: bestBySpecialId,
        specialiCompletati: specialiCompletati,
        totaleSpeciali: totaleSpeciali,
        tempoTotale: tempoTotale,
        punteggioTotale: punteggioTotale ?? this.punteggioTotale,
        posizione: posizione ?? this.posizione,
      );
}

/// Classifica per eventi di allenamento (Step 47, Parte 2C; sorgente dati
/// riscritta Step 51) — separata da [ClassificaEngine] (gara), con regole
/// di aggregazione diverse, richieste esplicitamente:
///   - nessun tempo forfettario per le PS non completate: non concorrono
///   - nessuna penalità per squadra incompleta: ci si allena anche da soli
///   - le penalità CP mancati/zona velocità restano (già dentro il
///     riepilogo [TrainingResultModel], calcolate una volta alla chiusura
///     del tentativo da `FirestoreService.publishTrainingResult` — questo
///     motore NON ricalcola più da passaggi grezzi: leggerli fra piloti
///     diversi richiederebbe una collectionGroup query mai autorizzata per
///     un non-admin, ed esporrebbe `pilotTrack`, vedi Step 51)
///   - il tempo di squadra per ogni PS è il MIGLIOR tempo fra TUTTI i
///     tentativi COMPLETATI di TUTTI i membri, non un pool di passaggi
///     implicito come in gara (qui i tentativi sono sessioni indipendenti,
///     mai sovrapposte nel tempo come i passaggi di gara)
class TrainingClassificaEngine {
  TrainingClassificaEngine._();

  static List<TrainingClassificaEntry> compute({
    required EventModel event,
    required List<RegistrationModel> registrations,
    required List<TeamModel> teams,
    required List<TrainingResultModel> results,
    required Map<String, String> userNames,
  }) {
    final approved = registrations
        .where((r) => r.stato == RegistrationStatus.approvato && r.squadraId != null)
        .toList();
    final bySquadra = <String, List<RegistrationModel>>{};
    for (final r in approved) {
      bySquadra.putIfAbsent(r.squadraId!, () => []).add(r);
    }

    final entries = <TrainingClassificaEntry>[];
    for (final squadraId in bySquadra.keys) {
      final members = bySquadra[squadraId]!;
      final memberIds = members.map((m) => m.userId).toSet();
      final team = teams.where((t) => t.id == squadraId).firstOrNull;
      final teamNome = team?.nome ?? members.first.teamName ?? 'Squadra';

      final best = <String, TrainingSpecialBest>{};
      var referenceVariant = event.routeAAsVariant;
      for (final result in results.where((r) => memberIds.contains(r.userId))) {
        referenceVariant =
            event.routeVariant(result.routeVariantId ?? event.activeRouteId) ??
                event.routeAAsVariant;
        for (final summary in result.speciali) {
          final valido = !summary.skipped &&
              !summary.notDetected &&
              summary.timingError != 'rilevamento_non_valido';
          if (!valido) continue;
          final current = best[summary.specialeId];
          if (current == null || summary.tempo < current.tempo.tempo) {
            best[summary.specialeId] = TrainingSpecialBest(
              tempo: summary.toSpecialTempo(),
              userId: result.userId,
              userName: userNames[result.userId] ?? '?',
              attemptNumber: result.attemptNumber,
            );
          }
        }
      }

      final totaleSpeciali =
          referenceVariant.speciali.where((s) => !s.annullata).length;
      final tempoTotale =
          best.values.fold<Duration>(Duration.zero, (sum, b) => sum + b.tempo.tempo);

      entries.add(TrainingClassificaEntry(
        entryId: squadraId,
        teamNome: teamNome,
        membriNomi: members.map((m) => userNames[m.userId] ?? '${m.nome} ${m.cognome}').toList(),
        bestBySpecialId: best,
        specialiCompletati: best.length,
        totaleSpeciali: totaleSpeciali,
        tempoTotale: tempoTotale,
        punteggioTotale: 0,
        posizione: 0,
      ));
    }

    if (event.tipologiaClassifica == TipologiaClassifica.punteggioSpeciale) {
      return _rankByPoints(entries);
    }
    return _rankByTime(entries);
  }

  static List<TrainingClassificaEntry> _rankByTime(
      List<TrainingClassificaEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) {
        if (a.specialiCompletati != b.specialiCompletati) {
          return b.specialiCompletati.compareTo(a.specialiCompletati);
        }
        return a.tempoTotale.compareTo(b.tempoTotale);
      });
    return [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(posizione: i + 1),
    ];
  }

  static List<TrainingClassificaEntry> _rankByPoints(
      List<TrainingClassificaEntry> entries) {
    // Per ogni PS con almeno un tempo: classifica le squadre che l'hanno
    // completata (le altre non concorrono su quella PS, nessun tempo
    // forfettario) e assegna i punti F1 standard (stessa scala della gara).
    final specialIds = <String>{
      for (final e in entries) ...e.bestBySpecialId.keys,
    };
    final pointsByEntry = <String, int>{for (final e in entries) e.entryId: 0};
    for (final specialId in specialIds) {
      final withTime = entries
          .where((e) => e.bestBySpecialId.containsKey(specialId))
          .toList()
        ..sort((a, b) => a
            .bestBySpecialId[specialId]!
            .tempo
            .tempo
            .compareTo(b.bestBySpecialId[specialId]!.tempo.tempo));
      for (var i = 0; i < withTime.length; i++) {
        pointsByEntry[withTime[i].entryId] =
            (pointsByEntry[withTime[i].entryId] ?? 0) + pointsForPosition(i + 1);
      }
    }

    final sorted = [...entries]
      ..sort((a, b) {
        final pa = pointsByEntry[a.entryId] ?? 0;
        final pb = pointsByEntry[b.entryId] ?? 0;
        if (pa != pb) return pb.compareTo(pa);
        return a.tempoTotale.compareTo(b.tempoTotale);
      });
    return [
      for (var i = 0; i < sorted.length; i++)
        sorted[i].copyWith(
            punteggioTotale: pointsByEntry[sorted[i].entryId] ?? 0, posizione: i + 1),
    ];
  }
}
