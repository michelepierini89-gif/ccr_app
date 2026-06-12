import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/track_appearance_service.dart';
import 'offline_provider.dart';

final trackAppearanceServiceProvider = Provider<TrackAppearanceService>((ref) {
  return TrackAppearanceService(ref.watch(sharedPreferencesProvider));
});

class TrackAppearanceNotifier extends Notifier<TrackAppearanceSettings> {
  @override
  TrackAppearanceSettings build() {
    return ref.watch(trackAppearanceServiceProvider).loadSettings();
  }

  Future<void> setWidth(double width) async {
    state = TrackAppearanceSettings(trackWidth: width, trackColor: state.trackColor);
    await ref.read(trackAppearanceServiceProvider).saveWidth(width);
  }

  Future<void> setColor(Color color) async {
    state = TrackAppearanceSettings(trackWidth: state.trackWidth, trackColor: color);
    await ref.read(trackAppearanceServiceProvider).saveColor(color);
  }
}

final trackAppearanceProvider =
    NotifierProvider<TrackAppearanceNotifier, TrackAppearanceSettings>(
        TrackAppearanceNotifier.new);
