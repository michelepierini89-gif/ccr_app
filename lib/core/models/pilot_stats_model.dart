/// Compagno di squadra con cui il pilota ha corso più spesso nella squadra
/// preferita — vedi [PilotStatsModel.preferredTeamCompagni].
class TeammateStat {
  final String userId;
  final String nome;
  final String cognome;
  final int gareInsieme;

  const TeammateStat({
    required this.userId,
    required this.nome,
    required this.cognome,
    required this.gareInsieme,
  });

  String get nomeCompleto => '$nome $cognome'.trim();
}

/// Statistiche aggregate di un pilota, calcolate sui risultati di squadra
/// (vince/è a podio la squadra, non il singolo pilota — vedi
/// [PilotStatsModel] usage in pilot_stats_provider.dart).
class PilotStatsModel {
  final int gareDisputate;
  final int gareVinte;
  final int garePodio;
  final int specialiVinte;
  final int specialiPodio;

  /// Stesse metriche di sopra, calcolate sulle sole gare disputate con la
  /// squadra preferita del pilota (nome squadra dell'evento, case-insensitive
  /// contro `UserModel.preferredTeamName`). Vuoto/zero se il pilota non ha
  /// una squadra preferita impostata o non ha mai corso con quel nome.
  final int preferredTeamGareDisputate;
  final int preferredTeamGareVinte;
  final int preferredTeamGarePodio;
  final int preferredTeamSpecialiVinte;
  final int preferredTeamSpecialiPodio;

  /// Compagni con cui si è corso più spesso nella squadra preferita,
  /// ordinati per numero di gare condivise decrescente.
  final List<TeammateStat> preferredTeamCompagni;

  /// Nomi distinti delle squadre con cui il pilota ha già corso (qualunque
  /// gara approvata, non solo quelle con la squadra preferita), ordinati per
  /// numero di gare decrescente — usati per la scelta della squadra
  /// preferita dal profilo, senza dover essere dentro un evento specifico.
  final List<String> raceTeamNames;

  const PilotStatsModel({
    this.gareDisputate = 0,
    this.gareVinte = 0,
    this.garePodio = 0,
    this.specialiVinte = 0,
    this.specialiPodio = 0,
    this.preferredTeamGareDisputate = 0,
    this.preferredTeamGareVinte = 0,
    this.preferredTeamGarePodio = 0,
    this.preferredTeamSpecialiVinte = 0,
    this.preferredTeamSpecialiPodio = 0,
    this.preferredTeamCompagni = const [],
    this.raceTeamNames = const [],
  });

  bool get hasData => gareDisputate > 0;
  bool get hasPreferredTeamData => preferredTeamGareDisputate > 0;
}
