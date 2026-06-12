import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Impostazioni di aspetto per la polyline della traccia pilota.
class TrackAppearanceSettings {
  final double trackWidth;
  final Color trackColor;

  const TrackAppearanceSettings({
    required this.trackWidth,
    required this.trackColor,
  });
}

/// Persiste su SharedPreferences larghezza e colore della traccia pilota.
class TrackAppearanceService {
  static const double defaultWidth = 5.0;
  static const Color defaultColor = Colors.blue;
  static const double minWidth = 2.0;
  static const double maxWidth = 10.0;

  static const _widthKey = 'track_appearance_width';
  static const _colorKey = 'track_appearance_color';

  final SharedPreferences _prefs;

  TrackAppearanceService(this._prefs);

  TrackAppearanceSettings loadSettings() {
    final width =
        (_prefs.getDouble(_widthKey) ?? defaultWidth).clamp(minWidth, maxWidth);
    final colorValue = _prefs.getInt(_colorKey);
    return TrackAppearanceSettings(
      trackWidth: width,
      trackColor: colorValue != null ? Color(colorValue) : defaultColor,
    );
  }

  Future<void> saveWidth(double width) =>
      _prefs.setDouble(_widthKey, width.clamp(minWidth, maxWidth));

  Future<void> saveColor(Color color) =>
      _prefs.setInt(_colorKey, color.toARGB32());
}
