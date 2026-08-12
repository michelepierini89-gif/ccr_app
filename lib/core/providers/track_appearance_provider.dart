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
    state = state.copyWith(trackWidth: width);
    await ref.read(trackAppearanceServiceProvider).saveWidth(width);
  }

  Future<void> setColor(Color color) async {
    state = state.copyWith(trackColor: color);
    await ref.read(trackAppearanceServiceProvider).saveColor(color);
  }

  Future<void> setArrowColor(Color color) async {
    state = state.copyWith(arrowColor: color);
    await ref.read(trackAppearanceServiceProvider).saveArrowColor(color);
  }

  Future<void> setArrowSize(double size) async {
    state = state.copyWith(arrowSize: size);
    await ref.read(trackAppearanceServiceProvider).saveArrowSize(size);
  }

  Future<void> setRefTrackColor(Color color) async {
    state = state.copyWith(refTrackColor: color);
    await ref.read(trackAppearanceServiceProvider).saveRefTrackColor(color);
  }

  Future<void> setRefTrackWidth(double width) async {
    state = state.copyWith(refTrackWidth: width);
    await ref.read(trackAppearanceServiceProvider).saveRefTrackWidth(width);
  }

  Future<void> setDebugPanelVisible(bool visible) async {
    state = state.copyWith(debugPanelVisible: visible);
    await ref
        .read(trackAppearanceServiceProvider)
        .saveDebugPanelVisible(visible);
  }
}

final trackAppearanceProvider =
    NotifierProvider<TrackAppearanceNotifier, TrackAppearanceSettings>(
        TrackAppearanceNotifier.new);
