import 'package:cloud_firestore/cloud_firestore.dart';

enum RegistrationStatus { inAttesa, approvato, rifiutato }

class RegistrationModel {
  final String userId;
  final String eventId;
  final String nome;
  final String cognome;
  final RegistrationStatus stato;
  final String? squadraId;
  final String? teamName;
  final DateTime createdAt;

  const RegistrationModel({
    required this.userId,
    required this.eventId,
    required this.nome,
    required this.cognome,
    required this.stato,
    this.squadraId,
    this.teamName,
    required this.createdAt,
  });

  String get nomeCompleto => '$nome $cognome';

  factory RegistrationModel.fromFirestore(
      DocumentSnapshot doc, String eventId) {
    final d = doc.data() as Map<String, dynamic>;
    return RegistrationModel(
      userId: doc.id,
      eventId: eventId,
      nome: d['nome'] ?? '',
      cognome: d['cognome'] ?? '',
      stato: RegistrationStatus.values.firstWhere(
        (e) => e.name == (d['stato'] ?? 'inAttesa'),
        orElse: () => RegistrationStatus.inAttesa,
      ),
      squadraId: d['squadraId'],
      teamName: d['teamName'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'cognome': cognome,
        'stato': stato.name,
        'squadraId': squadraId,
        if (teamName != null) 'teamName': teamName,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
