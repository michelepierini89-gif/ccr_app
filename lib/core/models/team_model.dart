import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String nome;
  final List<String> membriIds;
  final String createdBy;
  final String eventId;

  const TeamModel({
    required this.id,
    required this.nome,
    required this.membriIds,
    required this.createdBy,
    required this.eventId,
  });

  factory TeamModel.fromFirestore(DocumentSnapshot doc, String eventId) {
    final d = doc.data() as Map<String, dynamic>;
    return TeamModel(
      id: doc.id,
      nome: d['nome'] ?? '',
      membriIds: List<String>.from(d['membriIds'] ?? []),
      createdBy: d['createdBy'] ?? '',
      eventId: eventId,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'membriIds': membriIds,
        'createdBy': createdBy,
        'eventId': eventId,
      };
}
