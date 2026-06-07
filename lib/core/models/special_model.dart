import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'waypoint_model.dart';

class SpecialModel {
  final String id;
  final String nome;
  final int colorIndex;
  final WaypointModel waypointInizio;
  final WaypointModel waypointFine;
  final List<WaypointModel> controlPoints;
  final int ordine;
  final bool annullata;

  const SpecialModel({
    required this.id,
    required this.nome,
    required this.colorIndex,
    required this.waypointInizio,
    required this.waypointFine,
    this.controlPoints = const [],
    required this.ordine,
    this.annullata = false,
  });

  Color get color =>
      AppColors.specialColors[colorIndex % AppColors.specialColors.length];
  String get colorName => AppColors
      .specialColorNames[colorIndex % AppColors.specialColorNames.length];

  factory SpecialModel.fromMap(Map<String, dynamic> m) => SpecialModel(
        id: m['id'] ?? '',
        nome: m['nome'] ?? '',
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        waypointInizio:
            WaypointModel.fromMap(m['waypointInizio'] as Map<String, dynamic>),
        waypointFine:
            WaypointModel.fromMap(m['waypointFine'] as Map<String, dynamic>),
        controlPoints: (m['controlPoints'] as List<dynamic>? ?? [])
            .map((e) => WaypointModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        ordine: (m['ordine'] as num?)?.toInt() ?? 0,
        annullata: m['annullata'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'colorIndex': colorIndex,
        'waypointInizio': waypointInizio.toMap(),
        'waypointFine': waypointFine.toMap(),
        'controlPoints': controlPoints.map((cp) => cp.toMap()).toList(),
        'ordine': ordine,
        'annullata': annullata,
      };

  SpecialModel copyWith({
    String? id,
    String? nome,
    int? colorIndex,
    WaypointModel? waypointInizio,
    WaypointModel? waypointFine,
    List<WaypointModel>? controlPoints,
    int? ordine,
    bool? annullata,
  }) =>
      SpecialModel(
        id: id ?? this.id,
        nome: nome ?? this.nome,
        colorIndex: colorIndex ?? this.colorIndex,
        waypointInizio: waypointInizio ?? this.waypointInizio,
        waypointFine: waypointFine ?? this.waypointFine,
        controlPoints: controlPoints ?? this.controlPoints,
        ordine: ordine ?? this.ordine,
        annullata: annullata ?? this.annullata,
      );
}
