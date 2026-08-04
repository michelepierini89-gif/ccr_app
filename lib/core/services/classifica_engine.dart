import '../models/event_model.dart';
import '../models/classifica_model.dart';
import '../models/championship_model.dart';
import '../models/penalty_settings_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';

class ClassificaEngine {
  static List<ClassificaEntry> compute({
    required EventModel event,
    required List<WaypointPassageRecord> passages,
    required List<RegistrationModel> registrations,
    required List<TeamModel> teams,
    required Set<String> withdrawals,
    required List<GpsPointModel> liveTracking,
    PenaltySettingsModel penalties = const PenaltySettingsModel(),
    List<SpeedZoneViolation> speedZoneViolations = const [],
    // Tempi ufficiali ricalcolati post-gara (Blocco B), userId -> specialeId
    // -> tempo ufficiale. Se presente per almeno un membro dell'entry,
    // sostituisce il tempo netto calcolato dai passaggi live per quella PS
    // (le penalità CP/zona velocità restano invariate, calcolate sempre
    // dai passaggi live).
    Map<String, Map<String, OfficialSpecialTime>> officialTimesByUserId =
        const {},
  }) {
    final approvedRegs =
        registrations.where((r) => r.stato == RegistrationStatus.approvato).toList();

    // Determine which userIds have a recent GPS ping (within 2 minutes)
    final now = DateTime.now();
    final liveUserIds = liveTracking
        .where((p) => now.difference(p.timestamp).inSeconds < 120)
        .map((p) => p.userId)
        .toSet();

    // Build retiredReason map from tracking docs
    final retiredReasonMap = <String, String>{
      for (final p in liveTracking)
        if (p.retiredReason != null) p.userId: p.retiredReason!,
    };

    // Group approved regs by team
    final byTeam = <String, List<RegistrationModel>>{};
    final soloRegs = <RegistrationModel>[];
    for (final reg in approvedRegs) {
      if (reg.squadraId != null) {
        byTeam.putIfAbsent(reg.squadraId!, () => []).add(reg);
      } else {
        soloRegs.add(reg);
      }
    }

    final rawEntries = <_RawEntry>[];

    // Team entries
    for (final teamId in byTeam.keys) {
      final teamRegs = byTeam[teamId]!;
      final teamModel = teams.where((t) => t.id == teamId).firstOrNull;
      final memberIds = teamRegs.map((r) => r.userId).toSet();
      final teamPassages =
          passages.where((p) => memberIds.contains(p.userId)).toList();
      final teamViolations = speedZoneViolations
          .where((v) => memberIds.contains(v.userId))
          .toList();
      final isLive = memberIds.any(liveUserIds.contains);
      final membriNomi = teamRegs.map((r) => r.nomeCompleto).toList();

      // ritirato = TUTTI i membri si sono ritirati
      // ritiroCompagno = ALCUNI (non tutti) si sono ritirati (penalità, ma non classificato come ritirato)
      final withdrawnCount = memberIds.where(withdrawals.contains).length;
      final ritirato = withdrawnCount == memberIds.length && withdrawnCount > 0;
      final ritiroCompagno =
          !ritirato && withdrawnCount > 0 && memberIds.length > 1;

      final pilotiMancanti =
          (event.minSquadra - memberIds.length).clamp(0, event.minSquadra);

      final teamRetiredReason = memberIds
          .map((uid) => retiredReasonMap[uid])
          .where((r) => r != null)
          .firstOrNull;
      rawEntries.add(_RawEntry(
        entryId: teamId,
        teamNome: teamModel?.nome ?? teamRegs.firstOrNull?.teamName ?? teamId,
        membriNomi: membriNomi,
        passages: teamPassages,
        speedZoneViolations: teamViolations,
        ritirato: ritirato,
        ritiroCompagno: ritiroCompagno,
        pilotiMancanti: pilotiMancanti,
        isLive: isLive,
        retiredReason: teamRetiredReason,
        memberIds: memberIds,
      ));
    }

    // Solo entries (no team)
    for (final reg in soloRegs) {
      final userPassages =
          passages.where((p) => p.userId == reg.userId).toList();
      final userViolations = speedZoneViolations
          .where((v) => v.userId == reg.userId)
          .toList();
      rawEntries.add(_RawEntry(
        entryId: reg.userId,
        teamNome: reg.nomeCompleto,
        membriNomi: [reg.nomeCompleto],
        passages: userPassages,
        speedZoneViolations: userViolations,
        ritirato: withdrawals.contains(reg.userId),
        ritiroCompagno: false,
        pilotiMancanti: 0,
        isLive: liveUserIds.contains(reg.userId),
        retiredReason: retiredReasonMap[reg.userId],
        memberIds: {reg.userId},
      ));
    }

    // PASSO 1: calcola i tempi reali per tutte le entry.
    var computed = rawEntries.map((e) {
      final speciali = _computeSpeciali(event, e.passages,
          e.speedZoneViolations, penalties, e.memberIds, officialTimesByUserId);
      final cpTotale = speciali.fold(Duration.zero, (acc, s) => acc + s.tempo);
      final ritiroPenaltySeconds =
          e.ritiroCompagno ? penalties.ritiroCompagno : 0;
      final pilotiMancantiPenaltySeconds =
          e.pilotiMancanti * penalties.pilotaMancante;
      final tempoTotale = cpTotale +
          Duration(seconds: ritiroPenaltySeconds) +
          Duration(seconds: pilotiMancantiPenaltySeconds);
      return (
        entry: e,
        speciali: speciali,
        tempoTotale: tempoTotale,
        ritiroPenaltySeconds: ritiroPenaltySeconds,
        pilotiMancantiPenaltySeconds: pilotiMancantiPenaltySeconds,
      );
    }).toList();

    // PASSO 2: penalità forfettaria PS saltate = peggiore tempo registrato
    // tra tutti i piloti per quella PS + 30 minuti.
    final hasSkipped = computed.any((c) => c.speciali.any((st) => st.skipped));
    if (hasSkipped) {
      final worstBySp = <String, Duration>{};
      for (final c in computed) {
        for (final st in c.speciali) {
          if (st.skipped) continue;
          if (st.timingError == 'rilevamento_non_valido') continue;
          final prev = worstBySp[st.specialeId];
          if (prev == null || st.tempo > prev) worstBySp[st.specialeId] = st.tempo;
        }
      }
      computed = computed.map((c) {
        if (!c.speciali.any((st) => st.skipped)) return c;
        final updated = c.speciali.map((st) {
          if (!st.skipped) return st;
          final worst = worstBySp[st.specialeId] ?? const Duration(minutes: 90);
          final forfeit = worst + const Duration(minutes: 30);
          return st.copyWith(tempo: forfeit, penaltySeconds: forfeit.inSeconds);
        }).toList();
        final cpTotale2 = updated.fold(Duration.zero, (acc, s) => acc + s.tempo);
        final tempoTotale2 = cpTotale2 +
            Duration(seconds: c.ritiroPenaltySeconds) +
            Duration(seconds: c.pilotiMancantiPenaltySeconds);
        return (
          entry: c.entry,
          speciali: updated,
          tempoTotale: tempoTotale2,
          ritiroPenaltySeconds: c.ritiroPenaltySeconds,
          pilotiMancantiPenaltySeconds: c.pilotiMancantiPenaltySeconds,
        );
      }).toList();
    }

    final specialiValide =
        event.speciali.where((s) => !s.annullata).length;

    if (event.tipologiaClassifica == TipologiaClassifica.punteggioSpeciale) {
      return _rankByPoints(computed, event, penalties);
    }
    return _rankByTime(computed, specialiValide);
  }

  static List<SpecialTempo> _computeSpeciali(
      EventModel event,
      List<WaypointPassageRecord> passages,
      List<SpeedZoneViolation> speedZoneViolations,
      PenaltySettingsModel penalties,
      Set<String> memberIds,
      Map<String, Map<String, OfficialSpecialTime>> officialTimesByUserId) {
    final zoneById = {for (final z in event.speedZones) z.id: z};
    final result = <SpecialTempo>[];
    for (final special
        in event.speciali..sort((a, b) => a.ordine.compareTo(b.ordine))) {
      if (special.annullata) continue;
      final iniP = passages
          .where((p) => p.waypointId == special.waypointInizio.id)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final finP = passages
          .where((p) => p.waypointId == special.waypointFine.id)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (iniP.isEmpty || finP.isEmpty) continue;
      final start = iniP.first;
      final end = finP.firstWhere(
          (p) => p.timestamp.isAfter(start.timestamp),
          orElse: () => finP.first);
      if (!end.timestamp.isAfter(start.timestamp)) continue;

      // PS saltata volontariamente dal pilota: tempo provvisorio zero,
      // la penalità forfettaria viene applicata nel passo 2 di compute().
      if (end.timingError == 'speciale_saltata') {
        result.add(SpecialTempo(
          specialeId: special.id,
          specialeNome: special.nome,
          ordine: special.ordine,
          tempo: Duration.zero,
          controlPointsOk: false,
          skipped: true,
          timingError: 'speciale_saltata',
        ));
        continue;
      }

      final cleanTempo = end.timestamp.difference(start.timestamp);

      // FIX 3 — sanity check sui tempi PS: un tempo superiore a
      // kMaxSpecialDurationMinutes non è plausibile (es. recovery con
      // timestamp corrotto) e va segnalato come rilevamento non valido,
      // applicando la penalità massima prevista per una PS, invece di
      // mostrare un tempo assurdo (es. 795 minuti).
      if (cleanTempo.inMinutes > kMaxSpecialDurationMinutes) {
        result.add(SpecialTempo(
          specialeId: special.id,
          specialeNome: special.nome,
          ordine: special.ordine,
          tempo: Duration(seconds: penalties.cp3oPiuMancati),
          controlPointsOk: false,
          penaltySeconds: penalties.cp3oPiuMancati,
          timingError: 'rilevamento_non_valido',
          rawStartTime: start.timestamp,
          rawEndTime: end.timestamp,
          startTimingMethod: start.timingMethod,
          endTimingMethod: end.timingMethod,
        ));
        continue;
      }

      final missed = <int>[];
      for (int i = 0; i < special.controlPoints.length; i++) {
        final cp = special.controlPoints[i];
        final passed = passages.any((p) =>
            p.waypointId == cp.id &&
            p.timestamp.isAfter(start.timestamp) &&
            p.timestamp.isBefore(end.timestamp));
        if (!passed) missed.add(i + 1);
      }

      // Zone a velocità controllata: ogni violazione della zona appartenente
      // a questa PS (timestamp compreso tra inizio e fine) aggiunge
      // speedZonePenaltySeconds al tempo, come i CP mancati.
      final speedViolationsInSpecial = speedZoneViolations.where((v) {
        final zone = zoneById[v.zoneId];
        return zone != null &&
            zone.specialeId == special.id &&
            v.timestamp.isAfter(start.timestamp) &&
            v.timestamp.isBefore(end.timestamp);
      }).toList();
      final speedZonePenaltySeconds =
          speedViolationsInSpecial.length * penalties.speedZonePenaltySeconds;
      final speedZoneViolationInfos = speedViolationsInSpecial
          .map((v) => SpeedZoneViolationInfo(
                zoneNome: zoneById[v.zoneId]?.nome ?? v.zoneId,
                avgSpeedKmh: v.avgSpeedKmh,
                limitKmh: v.limitKmh,
              ))
          .toList();

      final cpPenaltySeconds = _cpPenaltySeconds(missed.length, penalties);
      final penaltySeconds = cpPenaltySeconds + speedZonePenaltySeconds;

      // Tempo ufficiale (Blocco B, ricalcolo post-gara con TrackSmoother +
      // porte virtuali): se un membro dell'entry ne ha uno per questa PS,
      // sostituisce il tempo netto live. Le penalità CP/zona velocità
      // restano sempre quelle calcolate sopra dai passaggi live — il
      // ricalcolo riguarda solo la precisione del cronometraggio inizio/
      // fine, non il rilevamento dei checkpoint (che resta a raggio, A5).
      OfficialSpecialTime? official;
      for (final uid in memberIds) {
        final o = officialTimesByUserId[uid]?[special.id];
        if (o != null) {
          official = o;
          break;
        }
      }
      final effectiveCleanTempo = official != null
          ? Duration(milliseconds: official.durationMs)
          : cleanTempo;
      final tempo = effectiveCleanTempo + Duration(seconds: penaltySeconds);

      result.add(SpecialTempo(
        specialeId: special.id,
        specialeNome: special.nome,
        ordine: special.ordine,
        tempo: tempo,
        controlPointsOk: missed.isEmpty,
        missedCpPositions: missed,
        penaltySeconds: penaltySeconds,
        speedZoneViolations: speedZoneViolationInfos,
        speedZonePenaltySeconds: speedZonePenaltySeconds,
        // GpsService può aver chiuso la PS in modo poco affidabile
        // (fine non rilevata, recovery con stima imprecisa o chiusura
        // forzata da FINE GARA): segnalato all'admin come per
        // 'rilevamento_non_valido', ma senza scartare il tempo.
        timingError: end.timingError,
        rawStartTime: end.timingError != null ? start.timestamp : null,
        rawEndTime: end.timingError != null ? end.timestamp : null,
        startTimingMethod: official?.timingMethod ?? start.timingMethod,
        endTimingMethod: official?.timingMethod ?? end.timingMethod,
        isOfficialTime: official != null,
      ));
    }
    return result;
  }

  // FIX 3 — un tempo PS superiore a questa soglia non è plausibile e viene
  // mostrato come "Rilevamento non valido" invece di un tempo numerico.
  static const int kMaxSpecialDurationMinutes = 90;

  static int _cpPenaltySeconds(int missedCount, PenaltySettingsModel p) {
    if (missedCount == 0) return 0;
    if (missedCount == 1) return p.cp1Mancato;
    if (missedCount == 2) return p.cp2Mancati;
    return p.cp3oPiuMancati;
  }

  static List<ClassificaEntry> _rankByTime(
    List<
            ({
              _RawEntry entry,
              List<SpecialTempo> speciali,
              Duration tempoTotale,
              int ritiroPenaltySeconds,
              int pilotiMancantiPenaltySeconds,
            })>
        computed,
    int totaleSpeciali,
  ) {
    final sorted = [...computed];
    sorted.sort((a, b) {
      if (a.entry.ritirato != b.entry.ritirato) {
        return a.entry.ritirato ? 1 : -1;
      }
      final aFin = a.speciali.length == totaleSpeciali;
      final bFin = b.speciali.length == totaleSpeciali;
      if (aFin != bFin) return aFin ? -1 : 1;
      if (aFin) return a.tempoTotale.compareTo(b.tempoTotale);
      // Both not finished: sort by specials completed desc, then time asc
      if (a.speciali.length != b.speciali.length) {
        return b.speciali.length.compareTo(a.speciali.length);
      }
      if (a.tempoTotale != Duration.zero && b.tempoTotale != Duration.zero) {
        return a.tempoTotale.compareTo(b.tempoTotale);
      }
      return 0;
    });

    int pos = 1;
    Duration? prevTime;
    return sorted.asMap().entries.map((e) {
      final c = e.value;
      int myPos = 0;
      if (!c.entry.ritirato) {
        if (prevTime != null && prevTime == c.tempoTotale) {
          myPos = pos - 1;
        } else {
          myPos = pos;
        }
        prevTime = c.tempoTotale;
        pos = e.key + 2; // next pos
      }
      return ClassificaEntry(
        entryId: c.entry.entryId,
        teamNome: c.entry.teamNome,
        membriNomi: c.entry.membriNomi,
        specialiCompletati: c.speciali,
        totaleSpeciali: totaleSpeciali,
        tempoTotale: c.tempoTotale,
        punteggioTotale: myPos > 0 ? pointsForPosition(myPos) : 0,
        posizione: myPos,
        ritirato: c.entry.ritirato,
        ritiroCompagno: c.entry.ritiroCompagno,
        ritiroCompagnoPenaltySeconds: c.ritiroPenaltySeconds,
        pilotiMancanti: c.entry.pilotiMancanti,
        pilotiMancantiPenaltySeconds: c.pilotiMancantiPenaltySeconds,
        isLive: c.entry.isLive,
        retiredReason: c.entry.ritirato ? c.entry.retiredReason : null,
      );
    }).toList();
  }

  /// Calcola la classifica di campionato applicando lo scarto dei 3 risultati
  /// peggiori. Ogni gara contribuisce con il punteggio per-evento del team
  /// (somma punti speciali per le gare 'a punti', punti per posizione finale
  /// per le gare 'a tempi'), normalizzando così tutto in punti.
  static ChampionshipStandings computeChampionship(
    ChampionshipModel championship,
    List<EventModel> events,
    List<EventResults> results,
  ) {
    final eventsById = {for (final e in events) e.id: e};
    final resultsById = {for (final r in results) r.eventId: r};

    // teamId -> teamNome
    final teamNames = <String, String>{};
    // teamId -> list of race scores (in championship event order)
    final teamRaces = <String, List<ChampionshipRaceScore>>{};

    for (final eventId in championship.eventIds) {
      final event = eventsById[eventId];
      final result = resultsById[eventId];
      if (event == null || result == null) continue;

      for (final entry in result.entries) {
        if (entry.ritirato) continue;
        teamNames[entry.entryId] = entry.teamNome;
        teamRaces.putIfAbsent(entry.entryId, () => []).add(
              ChampionshipRaceScore(
                eventId: event.id,
                eventNome: event.nome,
                tipologia: event.tipologiaClassifica,
                points: entry.punteggioTotale,
                dropped: false,
              ),
            );
      }
    }

    final standings = teamRaces.entries.map((kv) {
      final races = [...kv.value];
      // Indices sorted by points ascending -> the first dropCount are dropped
      final order = List<int>.generate(races.length, (i) => i)
        ..sort((a, b) => races[a].points.compareTo(races[b].points));
      final dropCount = races.length > 3 ? 3 : races.length;
      final droppedIdx = order.take(dropCount).toSet();

      var total = 0;
      final finalRaces = <ChampionshipRaceScore>[];
      for (var i = 0; i < races.length; i++) {
        final dropped = droppedIdx.contains(i);
        if (!dropped) total += races[i].points;
        finalRaces.add(ChampionshipRaceScore(
          eventId: races[i].eventId,
          eventNome: races[i].eventNome,
          tipologia: races[i].tipologia,
          points: races[i].points,
          dropped: dropped,
        ));
      }

      return (
        teamId: kv.key,
        teamNome: teamNames[kv.key] ?? kv.key,
        races: finalRaces,
        totalPoints: total,
      );
    }).toList()
      ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

    int pos = 1;
    int? prevPoints;
    final teamStandings = standings.asMap().entries.map((e) {
      final s = e.value;
      int myPos;
      if (prevPoints != null && prevPoints == s.totalPoints) {
        myPos = pos - 1;
      } else {
        myPos = pos;
      }
      prevPoints = s.totalPoints;
      pos = e.key + 2;
      return ChampionshipTeamStanding(
        teamId: s.teamId,
        teamNome: s.teamNome,
        races: s.races,
        totalPoints: s.totalPoints,
        posizione: myPos,
      );
    }).toList();

    return ChampionshipStandings(teams: teamStandings);
  }

  static List<ClassificaEntry> _rankByPoints(
    List<
            ({
              _RawEntry entry,
              List<SpecialTempo> speciali,
              Duration tempoTotale,
              int ritiroPenaltySeconds,
              int pilotiMancantiPenaltySeconds,
            })>
        computed,
    EventModel event,
    PenaltySettingsModel penalties,
  ) {
    // Assign points per special
    final pointsMap = <String, int>{};
    for (final c in computed) {
      pointsMap[c.entry.entryId] = 0;
    }

    for (final special in event.speciali) {
      if (special.annullata) continue;
      final completions = computed
          .where((c) => c.speciali.any((s) => s.specialeId == special.id))
          .map((c) => (
                id: c.entry.entryId,
                tempo: c.speciali
                    .firstWhere((s) => s.specialeId == special.id)
                    .tempo,
              ))
          .toList()
        ..sort((a, b) => a.tempo.compareTo(b.tempo));

      for (int i = 0; i < completions.length; i++) {
        pointsMap[completions[i].id] =
            (pointsMap[completions[i].id] ?? 0) + pointsForPosition(i + 1);
      }
    }

    final sorted = [...computed];
    sorted.sort((a, b) {
      if (a.entry.ritirato != b.entry.ritirato) {
        return a.entry.ritirato ? 1 : -1;
      }
      return (pointsMap[b.entry.entryId] ?? 0)
          .compareTo(pointsMap[a.entry.entryId] ?? 0);
    });

    int pos = 1;
    int? prevPoints;
    return sorted.asMap().entries.map((e) {
      final c = e.value;
      final pts = pointsMap[c.entry.entryId] ?? 0;
      int myPos = 0;
      if (!c.entry.ritirato) {
        if (prevPoints != null && prevPoints == pts) {
          myPos = pos - 1;
        } else {
          myPos = pos;
        }
        prevPoints = pts;
        pos = e.key + 2;
      }
      return ClassificaEntry(
        entryId: c.entry.entryId,
        teamNome: c.entry.teamNome,
        membriNomi: c.entry.membriNomi,
        specialiCompletati: c.speciali,
        totaleSpeciali: event.speciali.where((s) => !s.annullata).length,
        tempoTotale: c.tempoTotale,
        punteggioTotale: pts,
        posizione: myPos,
        ritirato: c.entry.ritirato,
        ritiroCompagno: c.entry.ritiroCompagno,
        ritiroCompagnoPenaltySeconds: c.ritiroPenaltySeconds,
        pilotiMancanti: c.entry.pilotiMancanti,
        pilotiMancantiPenaltySeconds: c.pilotiMancantiPenaltySeconds,
        isLive: c.entry.isLive,
        retiredReason: c.entry.ritirato ? c.entry.retiredReason : null,
      );
    }).toList();
  }
}

class _RawEntry {
  final String entryId;
  final String teamNome;
  final List<String> membriNomi;
  final List<WaypointPassageRecord> passages;
  final List<SpeedZoneViolation> speedZoneViolations;
  final bool ritirato;
  final bool ritiroCompagno;
  final int pilotiMancanti;
  final bool isLive;
  final String? retiredReason;
  final Set<String> memberIds;

  _RawEntry({
    required this.entryId,
    required this.teamNome,
    required this.membriNomi,
    required this.passages,
    this.speedZoneViolations = const [],
    required this.ritirato,
    required this.ritiroCompagno,
    required this.pilotiMancanti,
    required this.isLive,
    this.retiredReason,
    required this.memberIds,
  });
}
