import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification_model.dart';
import '../providers/notification_provider.dart';
import '../theme/app_colors.dart';
import '../../features/admin/providers/admin_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

class NotificationListenerWidget extends ConsumerStatefulWidget {
  const NotificationListenerWidget({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NotificationListenerWidget> createState() =>
      _NotificationListenerWidgetState();
}

class _NotificationListenerWidgetState
    extends ConsumerState<NotificationListenerWidget> {
  List<AppNotificationModel> _previous = [];

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<AppNotificationModel>>>(
      unreadNotificationsProvider,
      (prev, next) {
        final list = next.valueOrNull ?? [];
        if (list.isEmpty) {
          _previous = list;
          return;
        }
        // Show banner only for truly new notifications (not on first load)
        if (_previous.isNotEmpty) {
          final newItems = list
              .where((n) => !_previous.any((p) => p.id == n.id))
              .toList();
          for (final notif in newItems) {
            _showBanner(notif);
          }
        }
        _previous = list;
      },
    );

    return widget.child;
  }

  void _showBanner(AppNotificationModel notif) {
    final color = switch (notif.type) {
      NotificationType.registrationApproved => AppColors.success,
      NotificationType.registrationRejected => AppColors.error,
      NotificationType.newRegistration => AppColors.warning,
      NotificationType.pilotWithdrawal => AppColors.error,
      NotificationType.specialEntry => AppColors.accent,
      NotificationType.cpDisputeAccepted => AppColors.success,
      NotificationType.cpDisputeRejected => AppColors.error,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notif.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            Text(notif.body,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            final user = ref.read(authStateProvider).valueOrNull;
            if (user != null) {
              ref
                  .read(firestoreServiceProvider)
                  .markNotificationRead(user.uid, notif.id);
            }
          },
        ),
      ),
    );
  }
}
