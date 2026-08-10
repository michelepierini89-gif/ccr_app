import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_variant_model.dart';
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

extension DateTimeExtension on DateTime {
  DateTime toMidnight() => DateTime(year, month, day, 23, 59, 59);
}

enum TipologiaClassifica { sommaTempi, punteggioSpeciale }

extension TipologiaClassificaLabel on TipologiaClassifica {
  String get label => switch (this) {
        TipologiaClassifica.sommaTempi => 'Somma dei tempi',
        TipologiaClassifica.punteggioSpeciale =>
          'Punteggio per speciale (25/20/16/13/11/10/9/8/7/6)',
      };
}

/// Percorso alternativo (10/08/2026) — una riga del log delle attivazioni,
/// Parte 3: "chi, quando, da quale variante a quale". Sempre in ordine
/// cronologico crescente in [EventModel.routeChangeLog]; l'ultima entry è
/// anche la fonte di [EventModel.lastRouteChangeAt] usato dal banner
/// pilota/avviso pre-gara (Parte 4).
class RouteChangeLogEntry {
  final String changedByUid;
  final String changedByName;
  final DateTime timestamp;
  final String fromRouteId;
  final String toRouteId;

  const RouteChangeLogEntry({
    required this.changedByUid,
    required this.changedByName,
    required this.timestamp,
    required this.fromRouteId,
    required this.toRouteId,
  });

  factory RouteChangeLogEntry.fromMap(Map<String, dynamic> m) =>
      RouteChangeLogEntry(
        changedByUid: m['changedByUid'] ?? '',
        changedByName: m['changedByName'] ?? '',
        timestamp: (m['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        fromRouteId: m['fromRouteId'] ?? 'A',
        toRouteId: m['toRouteId'] ?? 'A',
      );

  Map<String, dynamic> toMap() => {
        'changedByUid': changedByUid,
        'changedByName': changedByName,
        'timestamp': Timestamp.fromDate(timestamp),
        'fromRouteId': fromRouteId,
        'toRouteId': toRouteId,
      };
}

class EventModel {
  final String id;
  final String nome;
  final String luogo;
  final DateTime data;
  final String descrizione;
  final EventStatus stato;
  final String createdBy;
  final DateTime createdAt;
  final int minSquadra;
  final int maxSquadra;
  final TipologiaClassifica tipologiaClassifica;
  final bool startEnabled;
  final List<StartingSlot> startingOrder;
  final int maxRaceTimeMinutes;

  // ── Percorso alternativo (10/08/2026) ─────────────────────────────────
  // I campi grezzi del percorso A (rinominati con suffisso RouteA — vedi
  // Parte 1 della richiesta) restano accessibili SOLO dove serve davvero
  // distinguere le due varianti (editor admin, gestione percorsi): in ogni
  // altro punto del codice si usano i getter active* sotto, che risolvono
  // sempre alla variante in corso per la gara (activeRouteId). Il rename
  // (rispetto ai vecchi speciali/dangerPoints/speedZones/fuelPoint/
  // trackUrl) rompe deliberatamente la compilazione ovunque venissero letti
  // direttamente, per garantire che nessun punto resti agganciato per
  // dimenticanza al vecchio comportamento "solo percorso A".
  final String labelRouteA;
  final String? trackUrlRouteA;
  final List<SpecialModel> specialiRouteA;
  final List<DangerPointModel> dangerPointsRouteA;
  final List<SpeedZoneModel> speedZonesRouteA;
  final WaypointModel? fuelPointRouteA;

  /// Percorso alternativo — null finché l'admin non lo crea (Parte 2,
  /// "Crea percorso alternativo"). Su Firestore è il campo nested `routeB`,
  /// del tutto assente sui documenti pre-esistenti (nessuna migrazione).
  final RouteVariantModel? routeB;

  /// 'A' o 'B' — quale percorso è in vigore per la gara. Default 'A' anche
  /// per i documenti Firestore pre-esistenti che non hanno questo campo.
  final String activeRouteId;

  /// Log delle attivazioni (Parte 3: chi, quando, da quale variante a
  /// quale), in ordine cronologico crescente. Vuoto per un evento che non
  /// ha mai cambiato percorso.
  final List<RouteChangeLogEntry> routeChangeLog;

  const EventModel({
    required this.id,
    required this.nome,
    required this.luogo,
    required this.data,
    required this.descrizione,
    this.labelRouteA = 'Percorso principale',
    this.trackUrlRouteA,
    required this.specialiRouteA,
    this.routeB,
    this.activeRouteId = 'A',
    this.routeChangeLog = const [],
    required this.stato,
    required this.createdBy,
    required this.createdAt,
    this.minSquadra = 2,
    this.maxSquadra = 3,
    this.tipologiaClassifica = TipologiaClassifica.sommaTempi,
    this.fuelPointRouteA,
    this.startEnabled = false,
    this.startingOrder = const [],
    this.maxRaceTimeMinutes = 270,
    this.dangerPointsRouteA = const [],
    this.speedZonesRouteA = const [],
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      nome: d['nome'] ?? '',
      luogo: d['luogo'] ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      descrizione: d['descrizione'] ?? '',
      labelRouteA: d['routeALabel'] as String? ?? 'Percorso principale',
      trackUrlRouteA: d['trackUrl'],
      specialiRouteA: (d['speciali'] as List<dynamic>? ?? [])
          .map((e) => SpecialModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      routeB: d['routeB'] != null
          ? RouteVariantModel.fromMap('B', d['routeB'] as Map<String, dynamic>)
          : null,
      activeRouteId: d['activeRouteId'] as String? ?? 'A',
      routeChangeLog: (d['routeChangeLog'] as List<dynamic>? ?? [])
          .map((e) => RouteChangeLogEntry.fromMap(e as Map<String, dynamic>))
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
      fuelPointRouteA: d['fuelPoint'] != null
          ? WaypointModel.fromMap(d['fuelPoint'] as Map<String, dynamic>)
          : null,
      startEnabled: d['startEnabled'] as bool? ?? false,
      startingOrder: (d['startingOrder'] as List<dynamic>? ?? [])
          .map((e) => StartingSlot.fromMap(e as Map<String, dynamic>))
          .toList(),
      maxRaceTimeMinutes: (d['maxRaceTimeMinutes'] as num?)?.toInt() ?? 270,
      dangerPointsRouteA: (d['dangerPoints'] as List<dynamic>? ?? [])
          .map((e) => DangerPointModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      speedZonesRouteA: (d['speedZones'] as List<dynamic>? ?? [])
          .map((e) => SpeedZoneModel.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'nome': nome,
        'luogo': luogo,
        'data': Timestamp.fromDate(data),
        'descrizione': descrizione,
        // Chiavi invariate rispetto a prima del percorso alternativo — zero
        // migrazione per i documenti esistenti (vedi Parte 1).
        'routeALabel': labelRouteA,
        'trackUrl': trackUrlRouteA,
        'speciali': specialiRouteA.map((s) => s.toMap()).toList(),
        'fuelPoint': fuelPointRouteA?.toMap(),
        'dangerPoints': dangerPointsRouteA.map((d) => d.toMap()).toList(),
        'speedZones': speedZonesRouteA.map((z) => z.toMap()).toList(),
        'routeB': routeB?.toMap(),
        'activeRouteId': activeRouteId,
        'routeChangeLog': routeChangeLog.map((e) => e.toMap()).toList(),
        'stato': stato.name,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
        'minSquadra': minSquadra,
        'maxSquadra': maxSquadra,
        'tipologiaClassifica': tipologiaClassifica.name,
        'startEnabled': startEnabled,
        'startingOrder': startingOrder.map((s) => s.toMap()).toList(),
        'maxRaceTimeMinutes': maxRaceTimeMinutes,
      };

  // ── Percorso attivo — SEMPRE usare questi getter fuori dall'editor/
  // gestione percorsi (Parte 1, punto 2) ──────────────────────────────────
  bool get isRouteBActive => activeRouteId == 'B' && routeB != null;

  String get activeLabel => isRouteBActive ? routeB!.label : labelRouteA;
  String? get activeTrackUrl =>
      isRouteBActive ? routeB!.trackUrl : trackUrlRouteA;
  List<SpecialModel> get activeSpeciali =>
      isRouteBActive ? routeB!.speciali : specialiRouteA;
  List<DangerPointModel> get activeDangerPoints =>
      isRouteBActive ? routeB!.dangerPoints : dangerPointsRouteA;
  List<SpeedZoneModel> get activeSpeedZones =>
      isRouteBActive ? routeB!.speedZones : speedZonesRouteA;
  WaypointModel? get activeFuelPoint =>
      isRouteBActive ? routeB!.fuelPoint : fuelPointRouteA;

  /// Vista di sola lettura della variante A nella stessa forma di
  /// [routeB] — utile per riusare la UI in modo simmetrico tra A e B
  /// (riepilogo diff all'attivazione, selettore variante in editor).
  RouteVariantModel get routeAAsVariant => RouteVariantModel(
        id: 'A',
        label: labelRouteA,
        trackUrl: trackUrlRouteA,
        speciali: specialiRouteA,
        dangerPoints: dangerPointsRouteA,
        speedZones: speedZonesRouteA,
        fuelPoint: fuelPointRouteA,
      );

  /// Variante corrispondente a [routeId] ('A' o 'B'), o null se 'B' e
  /// [routeB] non è stata ancora creata.
  RouteVariantModel? routeVariant(String routeId) =>
      routeId == 'B' ? routeB : routeAAsVariant;

  DateTime? get lastRouteChangeAt =>
      routeChangeLog.isEmpty ? null : routeChangeLog.last.timestamp;

  EventModel copyWith({
    String? nome,
    String? luogo,
    DateTime? data,
    String? descrizione,
    String? labelRouteA,
    String? trackUrlRouteA,
    bool clearTrackUrlRouteA = false,
    List<SpecialModel>? specialiRouteA,
    RouteVariantModel? routeB,
    bool clearRouteB = false,
    String? activeRouteId,
    List<RouteChangeLogEntry>? routeChangeLog,
    EventStatus? stato,
    int? minSquadra,
    int? maxSquadra,
    TipologiaClassifica? tipologiaClassifica,
    WaypointModel? fuelPointRouteA,
    bool clearFuelPointRouteA = false,
    bool? startEnabled,
    List<StartingSlot>? startingOrder,
    int? maxRaceTimeMinutes,
    List<DangerPointModel>? dangerPointsRouteA,
    List<SpeedZoneModel>? speedZonesRouteA,
  }) =>
      EventModel(
        id: id,
        nome: nome ?? this.nome,
        luogo: luogo ?? this.luogo,
        data: data ?? this.data,
        descrizione: descrizione ?? this.descrizione,
        labelRouteA: labelRouteA ?? this.labelRouteA,
        trackUrlRouteA: clearTrackUrlRouteA
            ? null
            : (trackUrlRouteA ?? this.trackUrlRouteA),
        specialiRouteA: specialiRouteA ?? this.specialiRouteA,
        routeB: clearRouteB ? null : (routeB ?? this.routeB),
        activeRouteId: activeRouteId ?? this.activeRouteId,
        routeChangeLog: routeChangeLog ?? this.routeChangeLog,
        stato: stato ?? this.stato,
        createdBy: createdBy,
        createdAt: createdAt,
        minSquadra: minSquadra ?? this.minSquadra,
        maxSquadra: maxSquadra ?? this.maxSquadra,
        tipologiaClassifica: tipologiaClassifica ?? this.tipologiaClassifica,
        fuelPointRouteA: clearFuelPointRouteA
            ? null
            : (fuelPointRouteA ?? this.fuelPointRouteA),
        startEnabled: startEnabled ?? this.startEnabled,
        startingOrder: startingOrder ?? this.startingOrder,
        maxRaceTimeMinutes: maxRaceTimeMinutes ?? this.maxRaceTimeMinutes,
        dangerPointsRouteA: dangerPointsRouteA ?? this.dangerPointsRouteA,
        speedZonesRouteA: speedZonesRouteA ?? this.speedZonesRouteA,
      );
}
