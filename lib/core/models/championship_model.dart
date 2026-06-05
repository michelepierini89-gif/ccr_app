import 'package:cloud_firestore/cloud_firestore.dart';

class ChampionshipModel {
  final String id;
  final String nome;
  final String descrizione;
  final int stagione;
  final List<String> eventIds;
  final int colorIndex;
  final String createdBy;
  final DateTime createdAt;

  const ChampionshipModel({
    required this.id,
    required this.nome,
    required this.descrizione,
    required this.stagione,
    required this.eventIds,
    required this.colorIndex,
    required this.createdBy,
    required this.createdAt,
  });

  factory ChampionshipModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChampionshipModel(
      id: doc.id,
      nome: d['nome'] ?? '',
      descrizione: d['descrizione'] ?? '',
      stagione: d['stagione'] ?? DateTime.now().year,
      eventIds: List<String>.from(d['eventIds'] ?? []),
      colorIndex: d['colorIndex'] ?? 0,
      createdBy: d['createdBy'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'descrizione': descrizione,
        'stagione': stagione,
        'eventIds': eventIds,
        'colorIndex': colorIndex,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ChampionshipModel copyWith({
    String? nome,
    String? descrizione,
    int? stagione,
    List<String>? eventIds,
    int? colorIndex,
  }) =>
      ChampionshipModel(
        id: id,
        nome: nome ?? this.nome,
        descrizione: descrizione ?? this.descrizione,
        stagione: stagione ?? this.stagione,
        eventIds: eventIds ?? this.eventIds,
        colorIndex: colorIndex ?? this.colorIndex,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
