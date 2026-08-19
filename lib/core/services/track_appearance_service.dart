import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

/// Impostazioni di aspetto per la traccia pilota, la freccia di posizione
/// e la traccia di riferimento (GPX evento) durante la navigazione GPS.
class TrackAppearanceSettings {
  final double trackWidth;
  final Color trackColor;
  final Color arrowColor;
  final double arrowSize;
  final Color refTrackColor;
  final double refTrackWidth;
  // Fix (pulizia schermata navigazione, bug test 18/08) — pannello debug
  // (heading/bearing/satelliti) nascondibile: default true finché siamo in
  // fase di test, come richiesto.
  final bool debugPanelVisible;
  // Step 47 (rifiniture) — opacità del tile di sfondo, regolabile dal
  // pilota: il default fisso 0.55 sbiadiva anche strade/sentieri, non solo
  // le etichette che doveva attenuare.
  final double tileOpacity;

  const TrackAppearanceSettings({
    required this.trackWidth,
    required this.trackColor,
    required this.arrowColor,
    required this.arrowSize,
    required this.refTrackColor,
    required this.refTrackWidth,
    required this.debugPanelVisible,
    required this.tileOpacity,
  });

  TrackAppearanceSettings copyWith({
    double? trackWidth,
    Color? trackColor,
    Color? arrowColor,
    double? arrowSize,
    Color? refTrackColor,
    double? refTrackWidth,
    bool? debugPanelVisible,
    double? tileOpacity,
  }) {
    return TrackAppearanceSettings(
      trackWidth: trackWidth ?? this.trackWidth,
      trackColor: trackColor ?? this.trackColor,
      arrowColor: arrowColor ?? this.arrowColor,
      arrowSize: arrowSize ?? this.arrowSize,
      refTrackColor: refTrackColor ?? this.refTrackColor,
      refTrackWidth: refTrackWidth ?? this.refTrackWidth,
      debugPanelVisible: debugPanelVisible ?? this.debugPanelVisible,
      tileOpacity: tileOpacity ?? this.tileOpacity,
    );
  }
}

/// Persiste su SharedPreferences l'aspetto della traccia pilota, della
/// freccia di posizione e della traccia di riferimento (GPX evento).
class TrackAppearanceService {
  static const double defaultWidth = 5.0;
  static const Color defaultColor = Colors.blue;
  static const double minWidth = 2.0;
  static const double maxWidth = 10.0;

  static const Color defaultArrowColor = AppColors.accent;
  static const double defaultArrowSize = 36.0;
  static const double minArrowSize = 24.0;
  static const double maxArrowSize = 48.0;

  static const Color defaultRefTrackColor = Colors.red;
  static const double defaultRefTrackWidth = 6.0;
  static const double minRefTrackWidth = 4.0;
  static const double maxRefTrackWidth = 10.0;

  // Step 47 (rifiniture) — il vecchio valore fisso era 0.55; il nuovo
  // default (0.75) sbiadisce meno strade/sentieri, il pilota può comunque
  // scendere fino a minTileOpacity se le etichette lo infastidiscono di più
  // della leggibilità del tracciato.
  static const double defaultTileOpacity = 0.75;
  static const double minTileOpacity = 0.3;
  static const double maxTileOpacity = 1.0;

  static const _widthKey = 'track_appearance_width';
  static const _colorKey = 'track_appearance_color';
  static const _arrowColorKey = 'track_appearance_arrow_color';
  static const _arrowSizeKey = 'track_appearance_arrow_size';
  static const _refTrackColorKey = 'track_appearance_ref_track_color';
  static const _refTrackWidthKey = 'track_appearance_ref_track_width';
  static const _debugPanelVisibleKey = 'track_appearance_debug_panel_visible';
  static const _tileOpacityKey = 'track_appearance_tile_opacity';

  final SharedPreferences _prefs;

  TrackAppearanceService(this._prefs);

  TrackAppearanceSettings loadSettings() {
    final width =
        (_prefs.getDouble(_widthKey) ?? defaultWidth).clamp(minWidth, maxWidth);
    final colorValue = _prefs.getInt(_colorKey);
    final arrowColorValue = _prefs.getInt(_arrowColorKey);
    final arrowSize = (_prefs.getDouble(_arrowSizeKey) ?? defaultArrowSize)
        .clamp(minArrowSize, maxArrowSize);
    final refTrackColorValue = _prefs.getInt(_refTrackColorKey);
    final refTrackWidth =
        (_prefs.getDouble(_refTrackWidthKey) ?? defaultRefTrackWidth)
            .clamp(minRefTrackWidth, maxRefTrackWidth);
    final tileOpacity =
        (_prefs.getDouble(_tileOpacityKey) ?? defaultTileOpacity)
            .clamp(minTileOpacity, maxTileOpacity);
    return TrackAppearanceSettings(
      trackWidth: width,
      trackColor: colorValue != null ? Color(colorValue) : defaultColor,
      arrowColor:
          arrowColorValue != null ? Color(arrowColorValue) : defaultArrowColor,
      arrowSize: arrowSize,
      refTrackColor: refTrackColorValue != null
          ? Color(refTrackColorValue)
          : defaultRefTrackColor,
      refTrackWidth: refTrackWidth,
      debugPanelVisible: _prefs.getBool(_debugPanelVisibleKey) ?? true,
      tileOpacity: tileOpacity,
    );
  }

  Future<void> saveDebugPanelVisible(bool visible) =>
      _prefs.setBool(_debugPanelVisibleKey, visible);

  Future<void> saveWidth(double width) =>
      _prefs.setDouble(_widthKey, width.clamp(minWidth, maxWidth));

  Future<void> saveColor(Color color) =>
      _prefs.setInt(_colorKey, color.toARGB32());

  Future<void> saveArrowColor(Color color) =>
      _prefs.setInt(_arrowColorKey, color.toARGB32());

  Future<void> saveArrowSize(double size) => _prefs.setDouble(
      _arrowSizeKey, size.clamp(minArrowSize, maxArrowSize));

  Future<void> saveRefTrackColor(Color color) =>
      _prefs.setInt(_refTrackColorKey, color.toARGB32());

  Future<void> saveRefTrackWidth(double width) => _prefs.setDouble(
      _refTrackWidthKey, width.clamp(minRefTrackWidth, maxRefTrackWidth));

  Future<void> saveTileOpacity(double opacity) => _prefs.setDouble(
      _tileOpacityKey, opacity.clamp(minTileOpacity, maxTileOpacity));
}
