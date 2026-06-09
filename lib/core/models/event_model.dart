import 'package:cloud_firestore/cloud_firestore.dart';
import 'special_model.dart';
import 'waypoint_model.dart';

enum EventStatus { bozza, aperto, inCorso, concluso, archiviata }

class StartingSlot {
  final String teamName;
  final DateTime startTime;
  final int orderNumber;

  const StartingSlot({
    required this.teamName,
    required this.startTime,
    required this.orderNumber,
  });

  factory StartingSlot.fromMap(Map<String, dynamic> m) => StartingSlot(
        teamName: m['teamName'] ?? '',
        startTime: (m['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
        orderNumber: (m['orderNumber'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'teamName': teamName,
        'startTime': Timestamp.fromDate(startTime),
        'orderNumber': orderNumber,
      };
}

enum TipologiaClassifica { sommaTempi, punteggioSpeciale }

extension TipologiaClassificaLabel on TipologiaClassifica {
  String get label => switch (this) {
        TipologiaClassifica.sommaTempi => 'Somma dei tempi',
        TipologiaClassifica.punteggioSpeciale =>
          'Punteggio per speciale (25/20/16/13/11/10/9/8/7/6)',
      };
}

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
  final int minSquadra;
  final int maxSquadra;
  final TipologiaClassifica tipologiaClassifica;
  final WaypointModel? fuelPoint;
  final bool startEnabled;
  final List<StartingSlot> startingOrder;
  final int maxRaceTimeMinutes;

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
    this.minSquadra = 2,
    this.maxSquadra = 3,
    this.tipologiaClassifica = TipologiaClassifica.sommaTempi,
    this.fuelPoint,
    this.startEnabled = false,
    this.startingOrder = const [],
    this.maxRaceTimeMinutes = 270,
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
      minSquadra: (d['minSquadra'] as num?)?.toInt() ?? 2,
      maxSquadra: (d['maxSquadra'] as num?)?.toInt() ?? 3,
      tipologiaClassifica: TipologiaClassifica.values.firstWhere(
        (e) => e.name == (d['tipologiaClassifica'] ?? 'sommaTempi'),
        orElse: () => TipologiaClassifica.sommaTempi,
      ),
      fuelPoint: d['fuelPoint'] != null
          ? WaypointModel.fromMap(d['fuelPoint'] as Map<String, dynamic>)
          : null,
      startEnabled: d['startEnabled'] as bool? ?? false,
      startingOrder: (d['startingOrder'] as List<dynamic>? ?? [])
          .map((e) => StartingSlot.fromMap(e as Map<String, dynamic>))
          .toList(),
      maxRaceTimeMinutes: (d['maxRaceTimeMinutes'] as num?)?.toInt() ?? 270,
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
        'minSquadra': minSquadra,
        'maxSquadra': maxSquadra,
        'tipologiaClassifica': tipologiaClassifica.name,
        'fuelPoint': fuelPoint?.toMap(),
        'startEnabled': startEnabled,
        'startingOrder': startingOrder.map((s) => s.toMap()).toList(),
        'maxRaceTimeMinutes': maxRaceTimeMinutes,
      };

  EventModel copyWith({
    String? nome,
    String? luogo,
    DateTime? data,
    String? descrizione,
    String? trackUrl,
    List<SpecialModel>? speciali,
    EventStatus? stato,
    int? minSquadra,
    int? maxSquadra,
    TipologiaClassifica? tipologiaClassifica,
    WaypointModel? fuelPoint,
    bool clearFuelPoint = false,
    bool? startEnabled,
    List<StartingSlot>? startingOrder,
    int? maxRaceTimeMinutes,
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
        minSquadra: minSquadra ?? this.minSquadra,
        maxSquadra: maxSquadra ?? this.maxSquadra,
        tipologiaClassifica: tipologiaClassifica ?? this.tipologiaClassifica,
        fuelPoint: clearFuelPoint ? null : (fuelPoint ?? this.fuelPoint),
        startEnabled: startEnabled ?? this.startEnabled,
        startingOrder: startingOrder ?? this.startingOrder,
        maxRaceTimeMinutes: maxRaceTimeMinutes ?? this.maxRaceTimeMinutes,
      );
}
