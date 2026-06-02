import 'package:cloud_firestore/cloud_firestore.dart';
import 'special_model.dart';

enum EventStatus { bozza, aperto, inCorso, concluso }

class EventModel {
  final String id;
  final String nome;
  final String luogo;
  final DateTime data;
  final String descrizione;
  final String? trackUrl;
  final List<SpecialModel> speciali;
  final EventStatus stato;
  final String createdBy;
  final DateTime createdAt;

  const EventModel({
    required this.id,
    required this.nome,
    required this.luogo,
    required this.data,
    required this.descrizione,
    this.trackUrl,
    required this.speciali,
    required this.stato,
    required this.createdBy,
    required this.createdAt,
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      nome: d['nome'] ?? '',
      luogo: d['luogo'] ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      descrizione: d['descrizione'] ?? '',
      trackUrl: d['trackUrl'],
      speciali: (d['speciali'] as List<dynamic>? ?? [])
          .map((e) => SpecialModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      stato: EventStatus.values.firstWhere(
        (e) => e.name == (d['stato'] ?? 'bozza'),
        orElse: () => EventStatus.bozza,
      ),
      createdBy: d['createdBy'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'luogo': luogo,
        'data': Timestamp.fromDate(data),
        'descrizione': descrizione,
        'trackUrl': trackUrl,
        'speciali': speciali.map((s) => s.toMap()).toList(),
        'stato': stato.name,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  EventModel copyWith({
    String? nome,
    String? luogo,
    DateTime? data,
    String? descrizione,
    String? trackUrl,
    List<SpecialModel>? speciali,
    EventStatus? stato,
  }) =>
      EventModel(
        id: id,
        nome: nome ?? this.nome,
        luogo: luogo ?? this.luogo,
        data: data ?? this.data,
        descrizione: descrizione ?? this.descrizione,
        trackUrl: trackUrl ?? this.trackUrl,
        speciali: speciali ?? this.speciali,
        stato: stato ?? this.stato,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
