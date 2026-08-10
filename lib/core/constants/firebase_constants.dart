class FirebaseConstants {
  FirebaseConstants._();
  static const String users = 'users';
  static const String events = 'events';
  static const String registrations = 'registrations';
  static const String teams = 'squadre';
  static const String tracking = 'tracking';
  static const String pilots = 'pilots';
  static const String iscritti = 'iscritti';
  static const String passages = 'passages';
  static const String notifications = 'notifications';
  static const String withdrawals = 'withdrawals';
  static const String userNotifications = 'user_notifications';
  static const String items = 'items';
  static const String fcmToken = 'fcmToken';
  static const String championships = 'championships';
  static const String penaltySettings = 'penalty_settings';
  static const String speedZoneViolations = 'speedZoneViolations';
  static const String cpDisputes = 'cp_disputes';
  static const String disputes = 'disputes';
  // Fix 5 (09/08/2026) — sottocollezione di chunk per pilotTrackFull: un
  // singolo campo array sul documento tracking/{eventId}/pilots/{userId}
  // può superare il limite Firestore di 1 MiB per documento su gare lunghe
  // (es. il test 100km del 09/08), causando un fallimento SILENZIOSO del
  // salvataggio (catturato dal catch generico attorno alla chiamata) —
  // vedi FirestoreService.saveFullPilotTrack/getFullPilotTrack.
  static const String fullTrackChunks = 'fullTrackChunks';
}
