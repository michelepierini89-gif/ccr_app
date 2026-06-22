import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  registrationApproved,
  registrationRejected,
  newRegistration,
  pilotWithdrawal,
  specialEntry,
  cpDisputeAccepted,
  cpDisputeRejected,
}

class AppNotificationModel {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  const AppNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  factory AppNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AppNotificationModel(
      id: doc.id,
      type: NotificationType.values.firstWhere(
        (e) => e.name == d['type'],
        orElse: () => NotificationType.newRegistration,
      ),
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      read: d['read'] as bool? ?? false,
    );
  }
}
