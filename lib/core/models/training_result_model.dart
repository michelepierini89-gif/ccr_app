import 'package:cloud_firestore/cloud_firestore.dart';
import 'classifica_model.dart';

/// Tempo di UNA prova speciale in un tentativo di allenamento concluso —
/// SOLO l'esito (tempo, CP mancati, penalità), MAI una posizione GPS.
/// Serializzato dentro [TrainingResultModel] (Step 51): a differenza di
/// `SpecialTempo` (usato in memoria dal motore classifica) questo tipo
/// esiste solo per essere scritto/letto da
/// `tracking/{eventId}/trainingResults/{attemptId}`, il riepilogo pubblico
/// che sostituisce la lettura diretta di `attempts`/`passages` per il
/// confronto fra piloti — quelle sottocollezioni restano owner+admin
/// perché il documento tentativo contiene `pilotTrack`.
class TrainingSpecialSummary {
  final String specialeId;
  final String specialeNome;
  final int ordine;
  final Duration tempo;
  final bool controlPointsOk;
  final List<int> missedCpPositions;
  final int penaltySeconds;
  final String? timingError;
  final bool skipped;
  final bool notDetected;
  final String startTimingMethod;
  final String endTimingMethod;

  const TrainingSpecialSummary({
    required this.specialeId,
    required this.specialeNome,
    required this.ordine,
    required this.tempo,
    required this.controlPointsOk,
    this.missedCpPositions = const [],
    this.penaltySeconds = 0,
    this.timingError,
    this.skipped = false,
    this.notDetected = false,
    this.startTimingMethod = 'radius',
    this.endTimingMethod = 'radius',
  });

  factory TrainingSpecialSummary.fromSpecialTempo(SpecialTempo st) =>
      TrainingSpecialSummary(
        specialeId: st.specialeId,
        specialeNome: st.specialeNome,
        ordine: st.ordine,
        tempo: st.tempo,
        controlPointsOk: st.controlPointsOk,
        missedCpPositions: st.missedCpPositions,
        penaltySeconds: st.penaltySeconds,
        timingError: st.timingError,
        skipped: st.skipped,
        notDetected: st.notDetected,
        startTimingMethod: st.startTimingMethod,
        endTimingMethod: st.endTimingMethod,
      );

  /// Ricostruisce un [SpecialTempo] (rawStartTime/rawEndTime e il dettaglio
  /// delle violazioni zona velocità restano assenti — debug admin, mai
  /// serializzati qui) per riusare la UI classifica/timing esistente senza
  /// duplicarla.
  SpecialTempo toSpecialTempo() => SpecialTempo(
        specialeId: specialeId,
        specialeNome: specialeNome,
        ordine: ordine,
        tempo: tempo,
        controlPointsOk: controlPointsOk,
        missedCpPositions: missedCpPositions,
        penaltySeconds: penaltySeconds,
        timingError: timingError,
        skipped: skipped,
        notDetected: notDetected,
        startTimingMethod: startTimingMethod,
        endTimingMethod: endTimingMethod,
      );

  Map<String, dynamic> toFirestore() => {
        'specialeId': specialeId,
        'specialeNome': specialeNome,
        'ordine': ordine,
        'tempoMs': tempo.inMilliseconds,
        'controlPointsOk': controlPointsOk,
        'missedCpPositions': missedCpPositions,
        'penaltySeconds': penaltySeconds,
        'timingError': ?timingError,
        'skipped': skipped,
        'notDetected': notDetected,
        'startTimingMethod': startTimingMethod,
        'endTimingMethod': endTimingMethod,
      };

  factory TrainingSpecialSummary.fromFirestore(Map<String, dynamic> d) =>
      TrainingSpecialSummary(
        specialeId: d['specialeId'] as String? ?? '',
        specialeNome: d['specialeNome'] as String? ?? '',
        ordine: (d['ordine'] as num?)?.toInt() ?? 0,
        tempo: Duration(milliseconds: (d['tempoMs'] as num?)?.toInt() ?? 0),
        controlPointsOk: d['controlPointsOk'] as bool? ?? true,
        missedCpPositions: (d['missedCpPositions'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        penaltySeconds: (d['penaltySeconds'] as num?)?.toInt() ?? 0,
        timingError: d['timingError'] as String?,
        skipped: d['skipped'] as bool? ?? false,
        notDetected: d['notDetected'] as bool? ?? false,
        startTimingMethod: d['startTimingMethod'] as String? ?? 'radius',
        endTimingMethod: d['endTimingMethod'] as String? ?? 'radius',
      );
}

/// Riepilogo pubblico (Step 51) di un tentativo di allenamento concluso —
/// `tracking/{eventId}/trainingResults/{attemptId}`: scritto dal
/// proprietario del tentativo ad OGNI chiusura (non solo sui record: più
/// semplice/robusto, non richiede leggere prima il record altrui per
/// decidere se scrivere — vedi PROGETTO_CCR.md), letto da tutti gli
/// autenticati per calcolare la classifica di squadra senza mai esporre
/// `pilotTrack`/`fullTrackChunks`.
class TrainingResultModel {
  final String attemptId;
  final String userId;
  final int attemptNumber;
  final String? routeVariantId;
  final DateTime completedAt;
  final List<TrainingSpecialSummary> speciali;

  const TrainingResultModel({
    required this.attemptId,
    required this.userId,
    required this.attemptNumber,
    required this.routeVariantId,
    required this.completedAt,
    required this.speciali,
  });

  factory TrainingResultModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TrainingResultModel(
      attemptId: doc.id,
      userId: d['userId'] as String? ?? '',
      attemptNumber: (d['attemptNumber'] as num?)?.toInt() ?? 1,
      routeVariantId: d['routeVariantId'] as String?,
      completedAt:
          (d['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      speciali: (d['speciali'] as List<dynamic>? ?? const [])
          .map((e) =>
              TrainingSpecialSummary.fromFirestore(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'attemptNumber': attemptNumber,
        'routeVariantId': ?routeVariantId,
        'completedAt': Timestamp.fromDate(completedAt),
        'speciali': speciali.map((s) => s.toFirestore()).toList(),
      };
}
