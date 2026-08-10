import '../models/event_model.dart';
import '../models/classifica_model.dart';
import '../models/championship_model.dart';
import '../models/penalty_settings_model.dart';
import '../models/registration_model.dart';
import '../models/route_variant_model.dart';
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
    // Percorso alternativo (10/08/2026, Parte 5) — userId -> 'A'/'B', letto
    // dal campo `routeVariantId` di ciascun tracking pilota (mai da
    // `event.activeRouteId`): garantisce che il cambio di percorso attivo
    // DOPO una gara, anche per errore, non alteri i tempi già corsi. Un
    // userId assente (pilota che ha corso prima dell'introduzione di
    // questo campo) ricade su 'A'.
    Map<String, String> routeVariantByUserId = const {},
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
      final teamRoute = _resolveEntryRoute(memberIds, routeVariantByUserId);
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
        routeIdUsed: teamRoute.routeId,
        mixedRouteVariants: teamRoute.mixed,
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
        routeIdUsed: routeVariantByUserId[reg.userId] ?? 'A',
        mixedRouteVariants: false,
      ));
    }

    // PASSO 1: calcola i tempi reali per tutte le entry — Parte 5: SEMPRE
    // sulla variante con cui l'entry ha corso (e.routeIdUsed, risolta sopra
    // dal tracking dei piloti), MAI su event.activeSpeciali. Se 'B' è stata
    // corsa e poi cancellata dall'admin, ricade su A (routeVariant torna
    // null) piuttosto che rompere il calcolo — caso limite, non la
    // preoccupazione principale di questa Parte.
    var computed = rawEntries.map((e) {
      final variant = event.routeVariant(e.routeIdUsed) ?? event.routeAAsVariant;
      final speciali = _computeSpeciali(variant, e.passages,
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
        totaleSpeciali: variant.specialiAttiveCount,
      );
    }).toList();

    // Riferimento per la base forfettaria (PASSO 2) — resta sul percorso
    // ATTIVO dell'evento: maxRaceTimeMinutes è un'impostazione a livello
    // evento, non per variante, quindi non ha senso renderla per-entry.
    final specialiValide = event.activeSpeciali.where((s) => !s.annullata).length;

    // PASSO 2: penalità forfettaria PS saltate O non rilevate = peggiore
    // tempo registrato tra tutti i piloti per quella PS + 30 minuti (Fix 3,
    // 09/08/2026 — unificato: [skipped] è il salto esplicito del pilota,
    // [notDetected] è l'assenza di dati GPS reali, stessa formula per
    // entrambi). Se NESSUN pilota ha un tempo reale per quella PS, la base
    // è il tempo limite gara diviso il numero di speciali (invece del
    // vecchio 90 min fisso) — e si ricalcola automaticamente ad ogni nuova
    // esecuzione di compute() (chiamata reattiva ad ogni update Firestore),
    // quando altri piloti completano la PS.
    final hasForfeit =
        computed.any((c) => c.speciali.any((st) => st.skipped || st.notDetected));
    if (hasForfeit) {
      final worstBySp = <String, Duration>{};
      for (final c in computed) {
        for (final st in c.speciali) {
          if (st.skipped || st.notDetected) continue;
          if (st.timingError == 'rilevamento_non_valido') continue;
          final prev = worstBySp[st.specialeId];
          if (prev == null || st.tempo > prev) worstBySp[st.specialeId] = st.tempo;
        }
      }
      final defaultBase = specialiValide > 0
          ? Duration(
              minutes: (event.maxRaceTimeMinutes / specialiValide).round())
          : const Duration(minutes: 90);
      computed = computed.map((c) {
        if (!c.speciali.any((st) => st.skipped || st.notDetected)) return c;
        final updated = c.speciali.map((st) {
          if (!st.skipped && !st.notDetected) return st;
          final worst = worstBySp[st.specialeId] ?? defaultBase;
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
          totaleSpeciali: c.totaleSpeciali,
        );
      }).toList();
    }

    if (event.tipologiaClassifica == TipologiaClassifica.punteggioSpeciale) {
      return _rankByPoints(computed, penalties);
    }
    return _rankByTime(computed);
  }

  static List<SpecialTempo> _computeSpeciali(
      RouteVariantModel variant,
      List<WaypointPassageRecord> passages,
      List<SpeedZoneViolation> speedZoneViolations,
      PenaltySettingsModel penalties,
      Set<String> memberIds,
      Map<String, Map<String, OfficialSpecialTime>> officialTimesByUserId) {
    final zoneById = {for (final z in variant.speedZones) z.id: z};
    final result = <SpecialTempo>[];
    for (final special
        in variant.speciali..sort((a, b) => a.ordine.compareTo(b.ordine))) {
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

      // FIX 3 (09/08/2026) — se inizio o fine non hanno un dato REALE
      // (porta o raggio) ma solo una stima a tempo fisso di GpsService
      // (timingMethod=='forfait': _closeOpenSpecial o
      // _tryRecoverSkippedSpecials senza alcun punto GPS trovato entro il
      // raggio di recovery), NON interpolare un tempo dalla differenza tra
      // due timestamp di cui almeno uno non misura nulla di reale — quel
      // numero non ha significato. Applica invece la stessa penalità
      // forfettaria del salto volontario (peggior tempo tra i piloti su
      // questa PS + 30 minuti, PASSO 2 sotto), con dicitura UI distinta.
      if (start.timingMethod == 'forfait' || end.timingMethod == 'forfait') {
        result.add(SpecialTempo(
          specialeId: special.id,
          specialeNome: special.nome,
          ordine: special.ordine,
          tempo: Duration.zero,
          controlPointsOk: false,
          notDetected: true,
          timingError: 'speciale_non_rilevata',
          startTimingMethod: start.timingMethod,
          endTimingMethod: end.timingMethod,
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
              int totaleSpeciali,
            })>
        computed,
  ) {
    final sorted = [...computed];
    sorted.sort((a, b) {
      if (a.entry.ritirato != b.entry.ritirato) {
        return a.entry.ritirato ? 1 : -1;
      }
      // Parte 5 — totaleSpeciali è per-entry (variante con cui ha corso),
      // non un unico valore condiviso da tutto l'evento.
      final aFin = a.speciali.length == a.totaleSpeciali;
      final bFin = b.speciali.length == b.totaleSpeciali;
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
        totaleSpeciali: c.totaleSpeciali,
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
        routeIdUsed: c.entry.routeIdUsed,
        mixedRouteVariants: c.entry.mixedRouteVariants,
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
              int totaleSpeciali,
            })>
        computed,
    PenaltySettingsModel penalties,
  ) {
    // Assign points per special. Parte 5 — gli id delle speciali si
    // ricavano da [computed] (già risolto per-entry sulla propria
    // variante), non più da `event.speciali`: se tutte le entry hanno
    // corso sulla stessa variante (caso normale) il risultato è identico a
    // prima; nel caso anomalo di varianti miste, ogni gruppo di speciali
    // con lo stesso id si confronta comunque solo al proprio interno,
    // senza mischiare id che non esistono per un'altra variante.
    final pointsMap = <String, int>{};
    for (final c in computed) {
      pointsMap[c.entry.entryId] = 0;
    }

    final specialeIds =
        computed.expand((c) => c.speciali.map((s) => s.specialeId)).toSet();
    for (final specialeId in specialeIds) {
      final completions = computed
          .where((c) => c.speciali.any((s) => s.specialeId == specialeId))
          .map((c) => (
                id: c.entry.entryId,
                tempo: c.speciali
                    .firstWhere((s) => s.specialeId == specialeId)
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
        totaleSpeciali: c.totaleSpeciali,
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
        routeIdUsed: c.entry.routeIdUsed,
        mixedRouteVariants: c.entry.mixedRouteVariants,
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
  final String routeIdUsed;
  final bool mixedRouteVariants;

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
    required this.routeIdUsed,
    required this.mixedRouteVariants,
  });
}

/// Percorso alternativo — risolve la variante di UNA entry (team o solo) a
/// partire dalle variant dei suoi membri: se concordano, quella; se
/// discordano (errore di gestione admin, non dovrebbe accadere), quella del
/// primo membro con [mixed] = true, così il chiamante può segnalarlo.
({String routeId, bool mixed}) _resolveEntryRoute(
    Set<String> memberIds, Map<String, String> byUser) {
  final ids = memberIds.map((m) => byUser[m] ?? 'A').toSet();
  final first = byUser[memberIds.first] ?? 'A';
  return (routeId: first, mixed: ids.length > 1);
}
