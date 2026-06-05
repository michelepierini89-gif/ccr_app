import '../models/event_model.dart';
import '../models/classifica_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';

class ClassificaEngine {
  static const _points = [25, 20, 16, 13, 11, 10, 9, 8, 7, 6];

  static List<ClassificaEntry> compute({
    required EventModel event,
    required List<WaypointPassageRecord> passages,
    required List<RegistrationModel> registrations,
    required List<TeamModel> teams,
    required Set<String> withdrawals,
    required List<GpsPointModel> liveTracking,
  }) {
    final approvedRegs =
        registrations.where((r) => r.stato == RegistrationStatus.approvato).toList();

    // Determine which userIds have a recent GPS ping (within 2 minutes)
    final now = DateTime.now();
    final liveUserIds = liveTracking
        .where((p) => now.difference(p.timestamp).inSeconds < 120)
        .map((p) => p.userId)
        .toSet();

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
      final isLive = memberIds.any(liveUserIds.contains);
      final ritirato = memberIds.any(withdrawals.contains);
      final membriNomi = teamRegs.map((r) => r.nomeCompleto).toList();

      rawEntries.add(_RawEntry(
        entryId: teamId,
        teamNome: teamModel?.nome ?? 'Squadra $teamId',
        membriNomi: membriNomi,
        passages: teamPassages,
        ritirato: ritirato,
        isLive: isLive,
      ));
    }

    // Solo entries (no team)
    for (final reg in soloRegs) {
      final userPassages =
          passages.where((p) => p.userId == reg.userId).toList();
      rawEntries.add(_RawEntry(
        entryId: reg.userId,
        teamNome: reg.nomeCompleto,
        membriNomi: [reg.nomeCompleto],
        passages: userPassages,
        ritirato: withdrawals.contains(reg.userId),
        isLive: liveUserIds.contains(reg.userId),
      ));
    }

    // Compute special times for each entry
    final computed = rawEntries.map((e) {
      final speciali = _computeSpeciali(event, e.passages);
      final tempoTotale =
          speciali.fold(Duration.zero, (acc, s) => acc + s.tempo);
      return (entry: e, speciali: speciali, tempoTotale: tempoTotale);
    }).toList();

    if (event.tipologiaClassifica == TipologiaClassifica.punteggioSpeciale) {
      return _rankByPoints(computed, event);
    }
    return _rankByTime(computed, event.speciali.length);
  }

  static List<SpecialTempo> _computeSpeciali(
      EventModel event, List<WaypointPassageRecord> passages) {
    final result = <SpecialTempo>[];
    for (final special in event.speciali..sort((a, b) => a.ordine.compareTo(b.ordine))) {
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

      final tempo = end.timestamp.difference(start.timestamp);
      final missed = <int>[];
      for (int i = 0; i < special.controlPoints.length; i++) {
        final cp = special.controlPoints[i];
        final passed = passages.any((p) =>
            p.waypointId == cp.id &&
            p.timestamp.isAfter(start.timestamp) &&
            p.timestamp.isBefore(end.timestamp));
        if (!passed) missed.add(i + 1);
      }

      result.add(SpecialTempo(
        specialeId: special.id,
        specialeNome: special.nome,
        ordine: special.ordine,
        tempo: tempo,
        controlPointsOk: missed.isEmpty,
        missedCpPositions: missed,
      ));
    }
    return result;
  }

  static List<ClassificaEntry> _rankByTime(
    List<({_RawEntry entry, List<SpecialTempo> speciali, Duration tempoTotale})>
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
        punteggioTotale: 0,
        posizione: myPos,
        ritirato: c.entry.ritirato,
        isLive: c.entry.isLive,
      );
    }).toList();
  }

  static List<ClassificaEntry> _rankByPoints(
    List<({_RawEntry entry, List<SpecialTempo> speciali, Duration tempoTotale})>
        computed,
    EventModel event,
  ) {
    // Assign points per special
    final pointsMap = <String, int>{};
    for (final c in computed) {
      pointsMap[c.entry.entryId] = 0;
    }

    for (final special in event.speciali) {
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

      for (int i = 0; i < completions.length && i < _points.length; i++) {
        pointsMap[completions[i].id] =
            (pointsMap[completions[i].id] ?? 0) + _points[i];
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
        totaleSpeciali: event.speciali.length,
        tempoTotale: c.tempoTotale,
        punteggioTotale: pts,
        posizione: myPos,
        ritirato: c.entry.ritirato,
        isLive: c.entry.isLive,
      );
    }).toList();
  }
}

class _RawEntry {
  final String entryId;
  final String teamNome;
  final List<String> membriNomi;
  final List<WaypointPassageRecord> passages;
  final bool ritirato;
  final bool isLive;

  _RawEntry({
    required this.entryId,
    required this.teamNome,
    required this.membriNomi,
    required this.passages,
    required this.ritirato,
    required this.isLive,
  });
}
