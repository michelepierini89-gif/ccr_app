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
  // Percorso alternativo (10/08/2026, Parte 5) — mappa pubblica (tutti gli
  // autenticati, come 'passages') userId -> routeVariantId ('A'/'B'),
  // scritta una sola volta da GpsService.startRecording. Serve perché
  // tracking/{eventId}/pilots/{userId} resta leggibile solo da admin e dal
  // proprietario (privacy posizione live) — la classifica invece deve
  // poter risolvere la variante di OGNI pilota anche quando la guarda un
  // altro pilota, non solo l'admin.
  static const String routeVariantByUser = 'routeVariantByUser';
  // Eventi di allenamento (Step 47, Parte 2): tentativi multipli per
  // pilota, sottocollezione di tracking/{eventId}/pilots/{userId} — ogni
  // tentativo è una sessione completa e indipendente (proprio
  // fullTrackChunks/passages/speedZoneViolations annidati), la struttura
  // usata dagli eventi di gara (documento pilota singolo, passages piatto
  // sull'evento) resta invariata.
  static const String attempts = 'attempts';
}
