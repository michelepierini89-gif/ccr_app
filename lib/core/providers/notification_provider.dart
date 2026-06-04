import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification_model.dart';
import '../../features/admin/providers/admin_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

final unreadNotificationsProvider =
    StreamProvider<List<AppNotificationModel>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(firestoreServiceProvider)
      .getUnreadNotificationsStream(user.uid);
});
