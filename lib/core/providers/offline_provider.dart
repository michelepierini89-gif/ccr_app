import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_queue_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized — override in main');
});

final offlineQueueProvider =
    ChangeNotifierProvider<OfflineQueueService>((ref) {
  return OfflineQueueService(ref.watch(sharedPreferencesProvider));
});
