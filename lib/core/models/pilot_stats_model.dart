/// Statistiche aggregate di un pilota, calcolate sui risultati di squadra
/// (vince/è a podio la squadra, non il singolo pilota — vedi
/// [PilotStatsModel] usage in pilot_stats_provider.dart).
class PilotStatsModel {
  final int gareDisputate;
  final int gareVinte;
  final int garePodio;
  final int specialiVinte;
  final int specialiPodio;

  const PilotStatsModel({
    this.gareDisputate = 0,
    this.gareVinte = 0,
    this.garePodio = 0,
    this.specialiVinte = 0,
    this.specialiPodio = 0,
  });

  bool get hasData => gareDisputate > 0;
}
