class PenaltySettingsModel {
  final int cp1Mancato;      // secondi penalità per 1 CP mancato
  final int cp2Mancati;      // secondi penalità per 2 CP mancati
  final int cp3oPiuMancati;  // secondi penalità per 3+ CP mancati
  final int ritiroCompagno;  // secondi penalità se un compagno si ritira

  const PenaltySettingsModel({
    this.cp1Mancato = 60,
    this.cp2Mancati = 180,
    this.cp3oPiuMancati = 360,
    this.ritiroCompagno = 600,
  });

  factory PenaltySettingsModel.fromMap(Map<String, dynamic> d) =>
      PenaltySettingsModel(
        cp1Mancato: (d['cp1Mancato'] as int?) ?? 60,
        cp2Mancati: (d['cp2Mancati'] as int?) ?? 180,
        cp3oPiuMancati: (d['cp3oPiuMancati'] as int?) ?? 360,
        ritiroCompagno: (d['ritiroCompagno'] as int?) ?? 600,
      );

  Map<String, dynamic> toMap() => {
        'cp1Mancato': cp1Mancato,
        'cp2Mancati': cp2Mancati,
        'cp3oPiuMancati': cp3oPiuMancati,
        'ritiroCompagno': ritiroCompagno,
      };

  PenaltySettingsModel copyWith({
    int? cp1Mancato,
    int? cp2Mancati,
    int? cp3oPiuMancati,
    int? ritiroCompagno,
  }) =>
      PenaltySettingsModel(
        cp1Mancato: cp1Mancato ?? this.cp1Mancato,
        cp2Mancati: cp2Mancati ?? this.cp2Mancati,
        cp3oPiuMancati: cp3oPiuMancati ?? this.cp3oPiuMancati,
        ritiroCompagno: ritiroCompagno ?? this.ritiroCompagno,
      );

  static String formatSeconds(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    if (rem == 0) return '${m}m';
    return '${m}m ${rem}s';
  }
}
