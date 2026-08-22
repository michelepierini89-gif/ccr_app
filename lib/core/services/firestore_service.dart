import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../constants/firebase_constants.dart';
import '../models/app_notification_model.dart';
import '../models/attempt_model.dart';
import '../models/championship_model.dart';
import '../models/cp_dispute_model.dart';
import '../models/event_model.dart';
import '../models/penalty_settings_model.dart';
import '../models/registration_model.dart';
import '../models/team_model.dart';
import '../models/gps_point_model.dart';
import '../models/classifica_model.dart';
import '../models/training_result_model.dart';
import '../models/user_model.dart';
import 'classifica_engine.dart';
import 'track_smoother.dart';

class FirestoreService {
  /// [firestore] è iniettabile solo per i test (es. `FakeFirebaseFirestore`
  /// da `fake_cloud_firestore` — vedi
  /// `test/core/services/firestore_track_save_test.dart`); tutti i call
  /// site di produzione usano il costruttore senza argomenti e ottengono
  /// `FirebaseFirestore.instance` come sempre.
  FirestoreService({FirebaseFirestore? firestore}) : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  /// Fix (bug test 18/08, "Carring CLO 3") — un evento reale ha mostrato
  /// `saveFullPilotTrack` fallire con `permission-denied` a fine di una
  /// sessione web/Chrome durata oltre un'ora, mentre le regole Firestore
  /// deployate (verificate via Rules API contro il file committato) erano
  /// corrette e già attive da prima dell'inizio della sessione. La causa più
  /// probabile è un ID token Firebase Auth scaduto (TTL 1h) il cui refresh
  /// automatico — su web si basa su un timer JS — può essere ritardato dal
  /// browser su un tab in background durante un test GPS lungo. Questo
  /// wrapper intercetta `permission-denied`/`unauthenticated`, forza un
  /// refresh del token e ritenta l'operazione una sola volta prima di
  /// arrendersi, usato dalle scritture del percorso traccia GPS (le uniche
  /// per cui questo pattern è stato osservato in produzione).
  Future<T> _withTokenRefreshRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'unauthenticated') {
        rethrow;
      }
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      } catch (_) {
        // Nessun utente o refresh fallito: ritenta comunque, l'errore
        // originale è più informativo di uno legato al refresh.
      }
      return await action();
    }
  }

  // Events
  Future<String> createEvent(EventModel event) async {
    final ref = await _db
        .collection(FirebaseConstants.events)
        .add(event.toFirestore());
    return ref.id;
  }

  Future<void> updateEvent(EventModel event) => _db
      .collection(FirebaseConstants.events)
      .doc(event.id)
      .update(event.toFirestore());

  Future<void> deleteEvent(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .delete();

  Stream<List<EventModel>> getEvents({String? createdBy}) {
    Query q = _db
        .collection(FirebaseConstants.events)
        .orderBy('createdAt', descending: true);
    if (createdBy != null) q = q.where('createdBy', isEqualTo: createdBy);
    return q.snapshots().map(
        (s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());
  }

  Stream<List<EventModel>> getOpenEvents() => _db
      .collection(FirebaseConstants.events)
      .where('stato', whereIn: ['aperto', 'inCorso'])
      .orderBy('data')
      .snapshots()
      .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());

  Stream<List<EventModel>> getArchivedEvents() => _db
      .collection(FirebaseConstants.events)
      .where('stato', isEqualTo: 'archiviata')
      .orderBy('data', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());

  Future<EventModel?> getEvent(String id) async {
    final doc =
        await _db.collection(FirebaseConstants.events).doc(id).get();
    if (!doc.exists) return null;
    return EventModel.fromFirestore(doc);
  }

  Stream<EventModel?> getEventById(String id) => _db
      .collection(FirebaseConstants.events)
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? EventModel.fromFirestore(doc) : null);

  // Registrations
  Future<void> registerForEvent({
    required String eventId,
    required String userId,
    required String nome,
    required String cognome,
    String? squadraId,
    String? teamName,
  }) async {
    final reg = RegistrationModel(
      userId: userId,
      eventId: eventId,
      nome: nome,
      cognome: cognome,
      stato: RegistrationStatus.inAttesa,
      squadraId: squadraId,
      teamName: teamName,
      createdAt: DateTime.now(),
    );
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .set(reg.toFirestore());
    await _createNotification(eventId, {
      'type': 'new_registration',
      'userId': userId,
      'nome': '$nome $cognome',
      'squadraId': squadraId,
    });
  }

  Stream<RegistrationModel?> streamMyRegistration(
          String eventId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.iscritti)
          .doc(userId)
          .snapshots()
          .map((doc) =>
              doc.exists ? RegistrationModel.fromFirestore(doc, eventId) : null);

  Future<void> updateRegistrationStatus(
    String eventId,
    String userId,
    RegistrationStatus stato,
  ) async {
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .update({'stato': stato.name});
    final approved = stato == RegistrationStatus.approvato;
    await _sendUserNotification(
      recipientId: userId,
      type: approved
          ? NotificationType.registrationApproved
          : NotificationType.registrationRejected,
      title: approved ? 'Iscrizione approvata' : 'Iscrizione rifiutata',
      body: approved
          ? 'La tua iscrizione all\'evento è stata approvata!'
          : 'La tua iscrizione all\'evento è stata rifiutata.',
    );
  }

  Stream<List<RegistrationModel>> getRegistrations(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.iscritti)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => RegistrationModel.fromFirestore(d, eventId))
          .toList());

  Future<RegistrationModel?> getMyRegistration(
      String eventId, String userId) async {
    final doc = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    return RegistrationModel.fromFirestore(doc, eventId);
  }

  // Teams
  /// Crea una squadra solo se non esiste già una con lo stesso nome
  /// (case-insensitive, trim) nello stesso evento.
  /// Lancia [Exception('team_name_exists')] in caso di duplicato.
  Future<String> createTeam(TeamModel team) async {
    final existing = await _db
        .collection(FirebaseConstants.events)
        .doc(team.eventId)
        .collection(FirebaseConstants.teams)
        .get();
    final nameLower = team.nome.trim().toLowerCase();
    final duplicate = existing.docs.any(
      (d) => (d.data()['nome'] as String? ?? '').trim().toLowerCase() == nameLower,
    );
    if (duplicate) throw Exception('team_name_exists');

    final ref = await _db
        .collection(FirebaseConstants.events)
        .doc(team.eventId)
        .collection(FirebaseConstants.teams)
        .add(team.toFirestore());
    return ref.id;
  }

  Stream<List<TeamModel>> getTeams(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.teams)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TeamModel.fromFirestore(d, eventId)).toList());

  Future<void> joinTeam(
          String eventId, String teamId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.teams)
          .doc(teamId)
          .update({
        'membriIds': FieldValue.arrayUnion([userId])
      });

  Future<void> leaveTeam(
          String eventId, String teamId, String userId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.teams)
          .doc(teamId)
          .update({
        'membriIds': FieldValue.arrayRemove([userId])
      });

  // GPS Tracking
  Future<void> updatePilotTracking(GpsPointModel point) => _db
      .collection(FirebaseConstants.tracking)
      .doc(point.eventId)
      .collection(FirebaseConstants.pilots)
      .doc(point.userId)
      .set(point.toFirestore(), SetOptions(merge: true));

  /// Percorso alternativo (10/08/2026, Parte 3) — true se almeno un pilota
  /// ha avviato la registrazione per questo evento (qualunque documento in
  /// `tracking/{eventId}/pilots`: il primo scritto è `raceStatus:'racing'`
  /// da `GpsService.startRecording`, PRIMA di qualunque fix GPS — quindi
  /// l'esistenza del documento è già la garanzia cercata). Usato per
  /// bloccare il cambio di percorso attivo: cambiarlo a gara iniziata
  /// renderebbe incoerenti i rilevamenti già registrati.
  Future<bool> hasAnyTrackingData(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Percorso alternativo (10/08/2026, Parte 3) — notifica in-app (lista
  /// campanella) a tutti i piloti iscritti e approvati per [eventId]. La
  /// notifica push FCM è gestita separatamente dal trigger Cloud Function
  /// `onRouteChanged`, che reagisce allo stesso scritto di
  /// `activeRouteId` su cui questo metodo non ha bisogno di intervenire
  /// (nessuna chiamata FCM diretta dal client, stesso pattern di
  /// `updateRegistrationStatus`/`onRegistrationStatusChange`).
  Future<void> notifyRouteChanged(String eventId, String newRouteLabel) async {
    final regsSnap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .where('stato', isEqualTo: 'approvato')
        .get();
    for (final reg in regsSnap.docs) {
      await _sendUserNotification(
        recipientId: reg.id,
        type: NotificationType.routeChanged,
        title: 'Percorso modificato',
        body: 'Percorso modificato: la manifestazione si svolgerà sul '
            '$newRouteLabel. Controlla la mappa aggiornata.',
      );
    }
  }

  /// Percorso alternativo (10/08/2026, Parte 5) — scritto una sola volta da
  /// GpsService.startRecording, in parallelo a [setRaceStatus]: mappa
  /// pubblica (leggibile da tutti gli autenticati, come 'passages') perché
  /// la classifica deve risolvere la variante di OGNI pilota anche quando
  /// la guarda un altro pilota, non solo l'admin (che invece può leggere
  /// direttamente il documento tracking/pilots, privato).
  Future<void> saveRouteVariantUsed(
          String eventId, String userId, String routeVariantId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.routeVariantByUser)
          .doc(userId)
          .set({'routeVariantId': routeVariantId});

  Stream<Map<String, String>> routeVariantByUserStream(String eventId) => _db
      .collection(FirebaseConstants.tracking)
      .doc(eventId)
      .collection(FirebaseConstants.routeVariantByUser)
      .snapshots()
      .map((snap) => {
            for (final d in snap.docs)
              d.id: (d.data()['routeVariantId'] as String?) ?? 'A',
          });

  Future<Map<String, String>> getRouteVariantByUserOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.routeVariantByUser)
        .get();
    return {
      for (final d in snap.docs)
        d.id: (d.data()['routeVariantId'] as String?) ?? 'A',
    };
  }

  Future<void> setRaceStatus(
          String eventId, String userId, String status,
          {String? retiredReason,
          DateTime? finishedAt,
          // Percorso alternativo (10/08/2026, Parte 5) — scritto SOLO da
          // GpsService.startRecording (status=='racing'): non sovrascrivere
          // con null sulle chiamate 'finished'/'retired', che non lo
          // passano — il campo, una volta scritto all'avvio, deve restare
          // quello con cui il pilota ha effettivamente corso.
          String? routeVariantId}) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .set({
            'raceStatus': status,
            'retiredReason': ?retiredReason,
            if (finishedAt != null)
              'finishedAt': Timestamp.fromDate(finishedAt),
            'routeVariantId': ?routeVariantId,
          }, SetOptions(merge: true));

  /// Persists the full GPS track for post-race replay.
  /// Called on FINE GARA and RITIRO so the result screen can show the
  /// polyline, e anche periodicamente durante la gara (vedi
  /// `GpsRecordingScreen`, flush incrementale) — è un unico campo array
  /// lat/lng, economico da riscrivere per intero ad ogni flush.
  Future<void> savePilotTrack(
          String eventId, String userId, List<LatLng> track,
          {String? attemptId}) =>
      _withTokenRefreshRetry(() =>
          _pilotOrAttemptDocRef(eventId, userId, attemptId: attemptId).set({
            'pilotTrack': track
                .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                .toList(),
          }, SetOptions(merge: true)));

  /// Fix 5 (09/08/2026) — campioni per chunk della sottocollezione
  /// [FirebaseConstants.fullTrackChunks]: a questa dimensione un chunk resta
  /// largamente sotto il limite Firestore di 1 MiB per documento anche nel
  /// caso peggiore (accuracy con molti decimali). Un batch write può
  /// contenere al più 500 operazioni: con gare fino a 4-5 ore a 250ms in
  /// speciale, il numero di chunk resta comunque a una piccola frazione di
  /// quel limite.
  static const int _fullTrackChunkSize = 2000;

  /// Persiste la traccia grezza completa (posizione + accuracy + timestamp
  /// per ogni fix accettato), separata dal semplice `pilotTrack` (solo
  /// lat/lng, usato per il replay della polyline): serve da input al
  /// ricalcolo post-gara con [TrackSmoother] (Blocco B).
  ///
  /// Fix 5 — PRIMA di questo fix, `samples` veniva scritto come un unico
  /// campo array sul documento `tracking/{eventId}/pilots/{userId}`: su una
  /// gara lunga (es. il test 100km del 09/08) questo campo, sommato al
  /// resto del documento, può superare il limite Firestore di 1 MiB per
  /// documento — il `.set()` fallisce, l'eccezione viene ingoiata dal
  /// `catch` generico attorno alla chiamata (in `gps_recording_screen.dart`)
  /// e la traccia risulta silenziosamente assente, mentre `pilotTrack`
  /// (molto più piccolo: solo lat/lng) continua a salvarsi correttamente —
  /// esattamente il sintomo osservato ("la mappa disegna la traccia, il
  /// ricalcolo dice che non c'è"). Ora `samples` viene spezzato in chunk in
  /// una sottocollezione dedicata, ciascuno ben sotto il limite.
  ///
  /// Cancella prima eventuali chunk di un salvataggio precedente per lo
  /// stesso pilota (idempotente: un secondo salvataggio con meno campioni
  /// non lascia chunk residui più vecchi e più lunghi).
  ///
  /// Fix (10/08/2026) — cancellazione e scrittura in DUE commit sequenziali
  /// separati, non nello stesso batch: un salvataggio successivo genera
  /// sempre chunk con lo stesso schema di id zero-padded (`00000000`,
  /// `00002000`, ...), quindi un secondo salvataggio riusa quasi sempre
  /// almeno l'id del primo chunk. `delete()` e `set()` sullo STESSO
  /// riferimento documento all'interno di un unico `WriteBatch` hanno
  /// semantica d'ordine non affidabile in pratica (verificato con un test
  /// di integrazione: il risultato osservato era che il documento restava
  /// cancellato invece di contenere il nuovo `set`) — separarli in due
  /// commit elimina l'ambiguità alla radice invece di dipendere da un
  /// comportamento non garantito.
  /// Documento pilota (`tracking/{eventId}/pilots/{userId}`, gara) o
  /// documento tentativo (`.../pilots/{userId}/attempts/{attemptId}`,
  /// allenamento — Step 47, Parte 2B) se [attemptId] è specificato. Un solo
  /// helper riusato da tutti i metodi di storage traccia sotto: nessuna
  /// logica duplicata tra i due path, la struttura usata dagli eventi di
  /// gara resta esattamente quella di sempre quando [attemptId] è null.
  DocumentReference<Map<String, dynamic>> _pilotOrAttemptDocRef(
    String eventId,
    String userId, {
    String? attemptId,
  }) {
    final pilotDoc = _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId);
    if (attemptId == null) return pilotDoc;
    return pilotDoc.collection(FirebaseConstants.attempts).doc(attemptId);
  }

  CollectionReference<Map<String, dynamic>> _fullTrackChunksRef(
          String eventId, String userId, {String? attemptId}) =>
      _pilotOrAttemptDocRef(eventId, userId, attemptId: attemptId)
          .collection(FirebaseConstants.fullTrackChunks);

  /// Cancella i chunk residui di una sessione precedente (se presenti) senza
  /// scrivere nulla di nuovo — va chiamato una volta all'avvio di una NUOVA
  /// registrazione, PRIMA del primo flush incrementale
  /// ([appendFullPilotTrackChunks]), così quest'ultimo può limitarsi ad
  /// aggiungere senza mai dover ricontrollare cosa c'era già: senza questo
  /// passo, gli id zero-padded di una sessione precedente più lunga
  /// resterebbero mescolati a quelli della sessione nuova.
  Future<void> resetFullPilotTrackForNewSession(
          String eventId, String userId, {String? attemptId}) =>
      _withTokenRefreshRetry(() async {
        final existing =
            await _fullTrackChunksRef(eventId, userId, attemptId: attemptId)
                .get();
        if (existing.docs.isEmpty) return;
        final deleteBatch = _db.batch();
        for (final doc in existing.docs) {
          deleteBatch.delete(doc.reference);
        }
        await deleteBatch.commit();
      });

  Future<void> saveFullPilotTrack(
          String eventId, String userId, List<RawTrackSample> samples,
          {String? attemptId}) =>
      _withTokenRefreshRetry(() async {
        final chunksRef =
            _fullTrackChunksRef(eventId, userId, attemptId: attemptId);

        final existing = await chunksRef.get();
        if (existing.docs.isNotEmpty) {
          final deleteBatch = _db.batch();
          for (final doc in existing.docs) {
            deleteBatch.delete(doc.reference);
          }
          await deleteBatch.commit();
        }
        if (samples.isNotEmpty) {
          final writeBatch = _db.batch();
          for (var i = 0; i < samples.length; i += _fullTrackChunkSize) {
            final end = (i + _fullTrackChunkSize < samples.length)
                ? i + _fullTrackChunkSize
                : samples.length;
            writeBatch.set(chunksRef.doc(i.toString().padLeft(8, '0')),
                {'samples': _encodeSamples(samples.sublist(i, end))});
          }
          await writeBatch.commit();
        }

        // Campo legacy sul documento pilota: mantenuto vuoto/rimosso per non
        // lasciare doppioni, ma senza toccare gli altri campi del documento
        // (raceStatus, pilotTrack, waypointPassati, ...). Solo per la
        // struttura di gara: i tentativi non hanno mai avuto il campo
        // legacy singolo, nulla da ripulire.
        if (attemptId == null) {
          await _db
              .collection(FirebaseConstants.tracking)
              .doc(eventId)
              .collection(FirebaseConstants.pilots)
              .doc(userId)
              .set({'pilotTrackFull': FieldValue.delete()},
                  SetOptions(merge: true));
        }
      });

  static List<Map<String, dynamic>> _encodeSamples(
          List<RawTrackSample> samples) =>
      samples
          .map((s) => {
                'lat': s.lat,
                'lng': s.lng,
                'accuracy': s.accuracy,
                'ts': s.timestamp.millisecondsSinceEpoch,
              })
          .toList();

  /// Fix (bug test 18/08, "Carring CLO 3") — scrittura INCREMENTALE dei
  /// chunk di [FirebaseConstants.fullTrackChunks], usata da
  /// `GpsRecordingScreen` con un flush periodico DURANTE la gara (non solo a
  /// FINE GARA/RITIRO/timeout, dove resta autorevole [saveFullPilotTrack]
  /// con il suo delete+rewrite completo). A differenza di
  /// [saveFullPilotTrack], NON cancella i chunk esistenti: scrive solo i
  /// chunk che coprono `[startIndex, startIndex + newSamples.length)`,
  /// riusando lo stesso schema di id zero-padded (indicizzato in assoluto,
  /// non relativo a questa chiamata) così i flush successivi continuano la
  /// sequenza senza sovrapporsi. Un'interruzione a metà gara (crash, chiusura
  /// app, tab web chiuso) lascia quindi leggibili tutti i campioni fino
  /// all'ultimo flush riuscito, invece di perdere l'intera traccia se solo
  /// il salvataggio finale fallisce.
  Future<void> appendFullPilotTrackChunks(
    String eventId,
    String userId,
    List<RawTrackSample> newSamples, {
    required int startIndex,
    String? attemptId,
  }) {
    if (newSamples.isEmpty) return Future.value();
    return _withTokenRefreshRetry(() async {
      final chunksRef =
          _fullTrackChunksRef(eventId, userId, attemptId: attemptId);

      final writeBatch = _db.batch();
      for (var i = 0; i < newSamples.length; i += _fullTrackChunkSize) {
        final end = (i + _fullTrackChunkSize < newSamples.length)
            ? i + _fullTrackChunkSize
            : newSamples.length;
        final absoluteIndex = startIndex + i;
        writeBatch.set(
            chunksRef.doc(absoluteIndex.toString().padLeft(8, '0')),
            {'samples': _encodeSamples(newSamples.sublist(i, end))});
      }
      await writeBatch.commit();
    });
  }

  /// Legge la traccia grezza completa salvata da [saveFullPilotTrack] per
  /// [userId] nell'evento [eventId], o lista vuota se assente (es. pilota
  /// mai concluso una sessione). Fix 5 — legge dalla sottocollezione a
  /// chunk (nome doc ordinabile lessicograficamente, zero-padded);
  /// fallback sul vecchio campo singolo `pilotTrackFull` per le tracce
  /// salvate prima di questo fix e ancora presenti (sotto 1 MiB, quindi mai
  /// state colpite dal bug).
  Future<List<RawTrackSample>> getFullPilotTrack(
      String eventId, String userId, {String? attemptId}) async {
    final pilotDocRef =
        _pilotOrAttemptDocRef(eventId, userId, attemptId: attemptId);

    final chunks = await pilotDocRef
        .collection(FirebaseConstants.fullTrackChunks)
        .orderBy(FieldPath.documentId)
        .get();
    if (chunks.docs.isNotEmpty) {
      final result = <RawTrackSample>[];
      for (final doc in chunks.docs) {
        final raw = doc.data()['samples'] as List<dynamic>? ?? const [];
        result.addAll(raw.map((e) => RawTrackSample(
              lat: (e['lat'] as num).toDouble(),
              lng: (e['lng'] as num).toDouble(),
              accuracy: (e['accuracy'] as num).toDouble(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(e['ts'] as int),
            )));
      }
      return result;
    }

    final doc = await pilotDocRef.get();
    final raw = doc.data()?['pilotTrackFull'] as List<dynamic>?;
    if (raw == null) return [];
    return raw
        .map((e) => RawTrackSample(
              lat: (e['lat'] as num).toDouble(),
              lng: (e['lng'] as num).toDouble(),
              accuracy: (e['accuracy'] as num).toDouble(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(e['ts'] as int),
            ))
        .toList();
  }

  /// Fix (10/08/2026) — best-effort: chiamato dal `catch` che avvolge i
  /// salvataggi traccia a fine sessione, quando quei salvataggi falliscono.
  /// È un `.set()` piccolo (poche decine di byte, mai vicino al limite
  /// 1 MiB che ha causato il bug originale), quindi ha buone probabilità di
  /// riuscire anche quando il salvataggio della traccia intera fallisce —
  /// ma il chiamante lo avvolge comunque nel proprio try/catch: se anche
  /// questo fallisce (es. nessuna connessione affatto), l'unica
  /// testimonianza resta il log diagnostico locale
  /// ([DiagnosticLogger.logTrackSaveError]), scritto sempre prima.
  Future<void> flagTrackSaveError(
          String eventId, String userId, String reason) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .set({
            'trackSaveError': true,
            'trackSaveErrorReason': reason,
            'trackSaveErrorAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

  /// Salva i tempi ufficiali di [userId] ricalcolati post-gara (Blocco B),
  /// uno per speciale, in campi separati dai tempi live — la classifica
  /// (ClassificaEngine) li preferisce quando presenti.
  Future<void> saveOfficialTimes(String eventId, String userId,
          Map<String, OfficialSpecialTime> bySpecialId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection('officialTimes')
          .doc(userId)
          .set({
        'specials': {
          for (final e in bySpecialId.entries) e.key: e.value.toMap(),
        },
      });

  /// Stream dei tempi ufficiali di tutti i piloti dell'evento [eventId],
  /// come userId -> specialeId -> [OfficialSpecialTime].
  Stream<Map<String, Map<String, OfficialSpecialTime>>> officialTimesStream(
          String eventId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection('officialTimes')
          .snapshots()
          .map((s) => _parseOfficialTimes(s.docs));

  Future<Map<String, Map<String, OfficialSpecialTime>>> getOfficialTimesOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection('officialTimes')
        .get();
    return _parseOfficialTimes(snap.docs);
  }

  Map<String, Map<String, OfficialSpecialTime>> _parseOfficialTimes(
      List<QueryDocumentSnapshot> docs) {
    final result = <String, Map<String, OfficialSpecialTime>>{};
    for (final doc in docs) {
      final specials =
          (doc.data() as Map<String, dynamic>)['specials'] as Map<String, dynamic>? ??
              {};
      result[doc.id] = {
        for (final e in specials.entries)
          e.key: OfficialSpecialTime.fromMap(e.value as Map<String, dynamic>),
      };
    }
    return result;
  }

  /// Stream of the current pilot's tracking doc fields (lightweight, no GPS parsing).
  Stream<Map<String, dynamic>?> myPilotStatusStream(
          String eventId, String userId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .snapshots()
          .map((doc) => doc.exists ? doc.data() as Map<String, dynamic> : null);

  /// Percorso alternativo (10/08/2026, Parte 5) — lettura one-shot (non
  /// stream) dello stesso documento di [myPilotStatusStream], usata da
  /// `RaceResultScreen` per risolvere `routeVariantId` una sola volta in
  /// `initState`, prima che i provider reattivi della build siano
  /// disponibili.
  Future<Map<String, dynamic>?> getPilotStatusOnce(
      String eventId, String userId) async {
    final doc = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.pilots)
        .doc(userId)
        .get();
    return doc.exists ? doc.data() as Map<String, dynamic> : null;
  }

  Stream<List<GpsPointModel>> getPilotTracking(String eventId) => _db
      .collection(FirebaseConstants.tracking)
      .doc(eventId)
      .collection(FirebaseConstants.pilots)
      .snapshots()
      .map((s) => s.docs
          .map((d) => GpsPointModel.fromFirestore(d, eventId))
          .toList());

  Future<void> setStartEnabled(String eventId, bool enabled) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .update({'startEnabled': enabled});

  Future<void> recordWithdrawal(String eventId, String userId,
      {List<LatLng> partialTrack = const [], String? retiredReason}) async {
    await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.withdrawals)
        .doc(userId)
        .set({
      'userId': userId,
      'timestamp': Timestamp.fromDate(DateTime.now()),
      if (partialTrack.isNotEmpty)
        'partialTrack': partialTrack
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      'retiredReason': ?retiredReason,
    });
    await _createNotification(eventId, {
      'type': 'withdrawal',
      'userId': userId,
    });
  }

  Stream<List<WaypointPassageRecord>> getPassagesStream(String eventId) => _db
      .collection(FirebaseConstants.tracking)
      .doc(eventId)
      .collection(FirebaseConstants.passages)
      .orderBy('timestamp')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => WaypointPassageRecord.fromFirestore(d)).toList());

  Stream<Set<String>> getWithdrawalsStream(String eventId) => _db
      .collection(FirebaseConstants.events)
      .doc(eventId)
      .collection(FirebaseConstants.withdrawals)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  Future<void> _createNotification(
      String eventId, Map<String, dynamic> data) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.notifications)
          .add({
        ...data,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'read': false,
      });

  Future<void> _sendUserNotification({
    required String recipientId,
    required NotificationType type,
    required String title,
    required String body,
  }) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(recipientId)
          .collection(FirebaseConstants.items)
          .add({
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'read': false,
      });

  Stream<List<AppNotificationModel>> getUnreadNotificationsStream(
          String userId) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(userId)
          .collection(FirebaseConstants.items)
          .where('read', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) => AppNotificationModel.fromFirestore(d))
              .toList());

  Future<void> markNotificationRead(String userId, String notifId) =>
      _db
          .collection(FirebaseConstants.userNotifications)
          .doc(userId)
          .collection(FirebaseConstants.items)
          .doc(notifId)
          .update({'read': true});

  // Championships

  Future<String> createChampionship(ChampionshipModel c) async {
    final ref = await _db
        .collection(FirebaseConstants.championships)
        .add(c.toFirestore());
    return ref.id;
  }

  Future<void> updateChampionship(ChampionshipModel c) => _db
      .collection(FirebaseConstants.championships)
      .doc(c.id)
      .update(c.toFirestore());

  Future<void> deleteChampionship(String id) => _db
      .collection(FirebaseConstants.championships)
      .doc(id)
      .delete();

  Stream<List<ChampionshipModel>> getChampionships({String? createdBy}) {
    // Nota: orderBy('stagione') + where('createdBy') richiede un indice composito.
    // Filtriamo solo per createdBy in Firestore e ordiniamo per stagione in Dart.
    Query q = _db.collection(FirebaseConstants.championships);
    if (createdBy != null) q = q.where('createdBy', isEqualTo: createdBy);
    return q.snapshots().map((s) {
      final list =
          s.docs.map((d) => ChampionshipModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.stagione.compareTo(a.stagione));
      return list;
    });
  }

  Future<ChampionshipModel?> getChampionshipForEvent(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.championships)
        .where('eventIds', arrayContains: eventId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ChampionshipModel.fromFirestore(snap.docs.first);
  }

  Stream<ChampionshipModel?> getChampionshipById(String id) => _db
      .collection(FirebaseConstants.championships)
      .doc(id)
      .snapshots()
      .map((doc) =>
          doc.exists ? ChampionshipModel.fromFirestore(doc) : null);

  Future<void> addEventToChampionship(
          String championshipId, String eventId) =>
      _db
          .collection(FirebaseConstants.championships)
          .doc(championshipId)
          .update({
        'eventIds': FieldValue.arrayUnion([eventId])
      });

  Future<void> removeEventFromChampionship(
          String championshipId, String eventId) =>
      _db
          .collection(FirebaseConstants.championships)
          .doc(championshipId)
          .update({
        'eventIds': FieldValue.arrayRemove([eventId])
      });

  Future<List<WaypointPassageRecord>> getPassagesOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.passages)
        .orderBy('timestamp')
        .get();
    return snap.docs
        .map((d) => WaypointPassageRecord.fromFirestore(d))
        .toList();
  }

  Future<List<RegistrationModel>> getRegistrationsOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.iscritti)
        .get();
    return snap.docs
        .map((d) => RegistrationModel.fromFirestore(d, eventId))
        .toList();
  }

  Future<List<TeamModel>> getTeamsOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.teams)
        .get();
    return snap.docs
        .map((d) => TeamModel.fromFirestore(d, eventId))
        .toList();
  }

  Future<Set<String>> getWithdrawalsOnce(String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.events)
        .doc(eventId)
        .collection(FirebaseConstants.withdrawals)
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  Future<void> saveUserFcmToken(String userId, String token) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {FirebaseConstants.fcmToken: token},
        SetOptions(merge: true),
      );

  Future<void> savePreferredTeamName(String userId, String teamName) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {'preferredTeamName': teamName},
        SetOptions(merge: true),
      );

  Future<void> saveUserPhotoUrl(String userId, String? photoUrl) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {'photoUrl': photoUrl},
        SetOptions(merge: true),
      );

  /// Tutti gli utenti registrati all'app (Step 42, elenco admin) — distinto
  /// dalle iscrizioni ai singoli eventi.
  Stream<List<UserModel>> getAllUsersStream() => _db
      .collection(FirebaseConstants.users)
      .snapshots()
      .map((s) => s.docs.map((d) => UserModel.fromFirestore(d)).toList());

  Future<void> setUserAttivo(String userId, bool attivo) =>
      _db.collection(FirebaseConstants.users).doc(userId).set(
        {'attivo': attivo},
        SetOptions(merge: true),
      );

  /// Numero di eventi a cui [userId] ha partecipato (iscrizioni approvate),
  /// usato dall'elenco utenti admin (Step 42). L'id del documento
  /// `events/{eventId}/iscritti/{userId}` È lo userId (vedi
  /// [RegistrationModel.fromFirestore]: `userId: doc.id`), quindi il filtro
  /// è su `FieldPath.documentId()` — nessun campo `userId` salvato nel
  /// documento. Filtro `stato` applicato lato client per evitare di
  /// richiedere un indice composito su una collection group query.
  Future<int> countApprovedRegistrationsForUser(String userId) async {
    final snap = await _db
        .collectionGroup(FirebaseConstants.iscritti)
        .where(FieldPath.documentId, isEqualTo: userId)
        .get();
    return snap.docs.where((d) => d.data()['stato'] == 'approvato').length;
  }

  // ── Eventi di allenamento — tentativi multipli (Step 47, Parte 2B) ─────
  // Ogni tentativo è un documento indipendente sotto
  // tracking/{eventId}/pilots/{userId}/attempts/{attemptId}, con le
  // proprie sottocollezioni fullTrackChunks/passages/speedZoneViolations —
  // stesso meccanismo a chunk della gara (vedi _pilotOrAttemptDocRef),
  // MAI passages/speedZoneViolations piatte sull'evento come in gara: qui
  // servono scoperte per tentativo, non per pilota.

  CollectionReference<Map<String, dynamic>> _attemptsRef(
          String eventId, String userId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.pilots)
          .doc(userId)
          .collection(FirebaseConstants.attempts);

  /// Crea un nuovo tentativo con `attemptNumber` = 1 + il numero di
  /// tentativi già esistenti per questo pilota su questo evento (mai
  /// riassegnato, letto una sola volta alla creazione).
  Future<AttemptModel> createAttempt(String eventId, String userId) =>
      _withTokenRefreshRetry(() async {
        final existing = await _attemptsRef(eventId, userId).count().get();
        final attemptNumber = (existing.count ?? 0) + 1;
        final attempt = AttemptModel(
          id: '',
          eventId: eventId,
          userId: userId,
          attemptNumber: attemptNumber,
          status: AttemptStatus.inProgress,
          startedAt: DateTime.now(),
        );
        final ref =
            await _attemptsRef(eventId, userId).add(attempt.toFirestoreCreate());
        return AttemptModel(
          id: ref.id,
          eventId: eventId,
          userId: userId,
          attemptNumber: attemptNumber,
          status: AttemptStatus.inProgress,
          startedAt: attempt.startedAt,
        );
      });

  /// Tutti i tentativi di [userId] su [eventId], più recente prima —
  /// elenco pilota (Parte 2E) con i rispettivi tempi/stato.
  Stream<List<AttemptModel>> attemptsStream(String eventId, String userId) =>
      _attemptsRef(eventId, userId)
          .orderBy('startedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(AttemptModel.fromFirestore).toList());

  /// Il tentativo in corso di [userId] su [eventId], se esiste — usato
  /// all'avvio di `GpsRecordingScreen` per capire se riprendere una
  /// sessione orfana (stesso pattern già in uso per la gara,
  /// `race_session_guard.dart`) o iniziarne una nuova. Al più uno per
  /// costruzione (un nuovo tentativo si crea solo dopo aver chiuso quello
  /// precedente, vedi Parte 2B/2E).
  Future<AttemptModel?> getInProgressAttempt(
      String eventId, String userId) async {
    final snap = await _attemptsRef(eventId, userId)
        .where('status', isEqualTo: AttemptStatus.inProgress.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AttemptModel.fromFirestore(snap.docs.first);
  }

  /// Il tentativo [attemptId], se esiste — usato da `_finishRace` per
  /// leggere `attemptNumber`/`routeVariantId` prima di pubblicare il
  /// riepilogo tempi (Step 51, `publishTrainingResult`).
  Future<AttemptModel?> getAttemptOnce(
      String eventId, String userId, String attemptId) async {
    final doc = await _attemptsRef(eventId, userId).doc(attemptId).get();
    if (!doc.exists) return null;
    return AttemptModel.fromFirestore(doc);
  }

  /// Chiude un tentativo (completed/abandoned) — chiamato da FINE
  /// GARA/RITIRO nella pipeline allenamento (mai per timeout: nessun
  /// tempo massimo negli eventi di allenamento, vedi Parte 2A).
  Future<void> updateAttemptStatus(
    String eventId,
    String userId,
    String attemptId, {
    required AttemptStatus status,
    DateTime? finishedAt,
    String? routeVariantId,
  }) =>
      _withTokenRefreshRetry(() {
        final finishedAtTs =
            finishedAt != null ? Timestamp.fromDate(finishedAt) : null;
        return _attemptsRef(eventId, userId).doc(attemptId).set({
          'status': status.name,
          'finishedAt': ?finishedAtTs,
          'routeVariantId': ?routeVariantId,
        }, SetOptions(merge: true));
      });

  Future<void> recordAttemptWaypointPassage({
    required String eventId,
    required String userId,
    required String attemptId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
    bool recoveredStart = false,
    bool recoveredEnd = false,
    String? timingError,
    String timingMethod = 'radius',
  }) =>
      _attemptsRef(eventId, userId).doc(attemptId).collection(FirebaseConstants.passages).add({
        'userId': userId,
        'waypointId': waypointId,
        'waypointNome': waypointNome,
        'timestamp': Timestamp.fromDate(timestamp),
        if (recoveredStart) 'recoveredStart': true,
        if (recoveredEnd) 'recoveredEnd': true,
        'timingError': ?timingError,
        'timingMethod': timingMethod,
      });

  Future<List<WaypointPassageRecord>> getAttemptPassagesOnce(
      String eventId, String userId, String attemptId) async {
    final snap = await _attemptsRef(eventId, userId)
        .doc(attemptId)
        .collection(FirebaseConstants.passages)
        .get();
    return snap.docs.map(WaypointPassageRecord.fromFirestore).toList();
  }

  Future<void> recordAttemptSpeedZoneViolation({
    required String eventId,
    required String userId,
    required String attemptId,
    required String zoneId,
    required double avgSpeedKmh,
    required double limitKmh,
    required DateTime timestamp,
  }) =>
      _attemptsRef(eventId, userId)
          .doc(attemptId)
          .collection(FirebaseConstants.speedZoneViolations)
          .add({
        'userId': userId,
        'zoneId': zoneId,
        'avgSpeedKmh': avgSpeedKmh,
        'limitKmh': limitKmh,
        'timestamp': Timestamp.fromDate(timestamp),
      });

  Future<List<SpeedZoneViolation>> getAttemptSpeedZoneViolationsOnce(
      String eventId, String userId, String attemptId) async {
    final snap = await _attemptsRef(eventId, userId)
        .doc(attemptId)
        .collection(FirebaseConstants.speedZoneViolations)
        .get();
    return snap.docs.map(SpeedZoneViolation.fromFirestore).toList();
  }

  // ── Riepilogo pubblico tempi PS di allenamento (Step 51) ───────────────
  // tracking/{eventId}/trainingResults/{attemptId} — SOSTITUISCE la vecchia
  // getCompletedAttemptsForEvent (collectionGroup query su 'attempts'): un
  // match Firestore a profondità fissa come quello di 'attempts' sopra non
  // autorizza MAI una collectionGroup query per un utente non-admin (solo
  // il bypass /{document=**} lo fa, motivo per cui la classifica falliva
  // con permission-denied per ogni pilota). Questa collezione è PIATTA
  // sull'evento (nessuna nesting sotto pilots/{userId}), quindi una query
  // di collezione normale basta — e contiene solo tempi/esiti per PS, mai
  // `pilotTrack`/posizioni.

  CollectionReference<Map<String, dynamic>> _trainingResultsRef(
          String eventId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.trainingResults);

  /// Calcola i tempi per PS del tentativo appena concluso (dalle SUE
  /// passages/speedZoneViolations — leggibili solo dal proprietario, che è
  /// esattamente chi chiama questo metodo) e pubblica il riepilogo, sempre
  /// (non solo sui record: scelta esplicita, vedi PROGETTO_CCR.md). Chiamato
  /// da `GpsRecordingScreen._finishRace()` subito dopo `updateAttemptStatus`
  /// con `status: completed`.
  Future<void> publishTrainingResult({
    required EventModel event,
    required String userId,
    required String attemptId,
    required int attemptNumber,
    String? routeVariantId,
    required DateTime completedAt,
  }) =>
      _withTokenRefreshRetry(() async {
        final variant =
            event.routeVariant(routeVariantId ?? event.activeRouteId) ??
                event.routeAAsVariant;
        final passages =
            await getAttemptPassagesOnce(event.id, userId, attemptId);
        final violations = await getAttemptSpeedZoneViolationsOnce(
            event.id, userId, attemptId);
        final penalties = await getEffectivePenaltySettings(event.id);
        final speciali = ClassificaEngine.computeSpeciali(
            variant, passages, violations, penalties, {userId}, const {});
        final result = TrainingResultModel(
          attemptId: attemptId,
          userId: userId,
          attemptNumber: attemptNumber,
          routeVariantId: routeVariantId,
          completedAt: completedAt,
          speciali:
              speciali.map(TrainingSpecialSummary.fromSpecialTempo).toList(),
        );
        await _trainingResultsRef(event.id)
            .doc(attemptId)
            .set(result.toFirestore());
      });

  /// Tutti i riepiloghi pubblicati per [eventId] — usato dal motore
  /// classifica allenamento (miglior tempo per PS fra tutti i tentativi di
  /// tutta la squadra) e dalle statistiche di squadra del pilota.
  Future<List<TrainingResultModel>> getTrainingResultsForEvent(
      String eventId) async {
    final snap = await _trainingResultsRef(eventId).get();
    return snap.docs.map(TrainingResultModel.fromFirestore).toList();
  }

  Future<void> recordWaypointPassage({
    required String eventId,
    required String userId,
    required String waypointId,
    required String waypointNome,
    required DateTime timestamp,
    bool recoveredStart = false,
    bool recoveredEnd = false,
    String? timingError,
    // Precisione del timing di questo passaggio: 'gate' (porta virtuale +
    // interpolazione), 'radius' (raggio) o 'recovery' (recovery
    // retroattivo/forfeit) — vedi Blocco A del timing di precisione.
    // Mostrato come badge discreto in TimingScreen (admin).
    String timingMethod = 'radius',
  }) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.passages)
          .add({
        'userId': userId,
        'waypointId': waypointId,
        'waypointNome': waypointNome,
        'timestamp': Timestamp.fromDate(timestamp),
        if (recoveredStart) 'recoveredStart': true,
        if (recoveredEnd) 'recoveredEnd': true,
        'timingError': ?timingError,
        'timingMethod': timingMethod,
      });

  /// Salva una violazione di zona a velocità controllata. Best-effort: a
  /// differenza dei passaggi waypoint (che determinano il tempo PS), una
  /// violazione persa non altera il risultato della gara in modo critico —
  /// solo la penalità non viene applicata — quindi non serve un fallback
  /// su coda offline.
  Future<void> recordSpeedZoneViolation({
    required String eventId,
    required String userId,
    required String zoneId,
    required double avgSpeedKmh,
    required double limitKmh,
    required DateTime timestamp,
  }) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.speedZoneViolations)
          .add({
        'userId': userId,
        'zoneId': zoneId,
        'avgSpeedKmh': avgSpeedKmh,
        'limitKmh': limitKmh,
        'timestamp': Timestamp.fromDate(timestamp),
      });

  Stream<List<SpeedZoneViolation>> getSpeedZoneViolationsStream(
          String eventId) =>
      _db
          .collection(FirebaseConstants.tracking)
          .doc(eventId)
          .collection(FirebaseConstants.speedZoneViolations)
          .snapshots()
          .map((s) => s.docs
              .map((d) => SpeedZoneViolation.fromFirestore(d))
              .toList());

  Future<List<SpeedZoneViolation>> getSpeedZoneViolationsOnce(
      String eventId) async {
    final snap = await _db
        .collection(FirebaseConstants.tracking)
        .doc(eventId)
        .collection(FirebaseConstants.speedZoneViolations)
        .get();
    return snap.docs
        .map((d) => SpeedZoneViolation.fromFirestore(d))
        .toList();
  }

  // ── Segnalazioni CP mancati (pilota → admin) ────────────────────────────

  Future<void> createCpDispute({
    required String eventId,
    required String pilotId,
    required String pilotName,
    required String teamName,
    required List<DisputedCp> missedCps,
    String? pilotNote,
  }) async {
    final now = DateTime.now();
    final disputeId = '${pilotId}_${now.millisecondsSinceEpoch}';
    await _db
        .collection(FirebaseConstants.cpDisputes)
        .doc(eventId)
        .collection(FirebaseConstants.disputes)
        .doc(disputeId)
        .set(CpDisputeModel(
          id: disputeId,
          eventId: eventId,
          pilotId: pilotId,
          pilotName: pilotName,
          teamName: teamName,
          missedCps: missedCps,
          pilotNote: pilotNote,
          timestamp: now,
        ).toFirestore());
    await _createNotification(eventId, {
      'type': 'cp_dispute',
      'pilotId': pilotId,
      'pilotName': pilotName,
    });
  }

  /// Solo admin (vedi firestore.rules — bypass globale): tutte le dispute
  /// dell'evento, per la banner/lista di gestione.
  Stream<List<CpDisputeModel>> getCpDisputesStream(String eventId) => _db
      .collection(FirebaseConstants.cpDisputes)
      .doc(eventId)
      .collection(FirebaseConstants.disputes)
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => CpDisputeModel.fromFirestore(d)).toList());

  /// Fix 4 (09/08/2026) — SOLO le dispute di [pilotId] per [eventId]: la
  /// regola Firestore per un pilota non-admin richiede una query
  /// esplicitamente ristretta al proprio `pilotId` (una lettura
  /// dell'intera collezione senza filtro verrebbe negata, non
  /// silenziosamente troncata). Usata dalla UI pilota (stato della propria
  /// segnalazione), mai dall'admin (che usa [getCpDisputesStream]).
  Stream<List<CpDisputeModel>> getMyCpDisputesStream(
          String eventId, String pilotId) =>
      _db
          .collection(FirebaseConstants.cpDisputes)
          .doc(eventId)
          .collection(FirebaseConstants.disputes)
          .where('pilotId', isEqualTo: pilotId)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => CpDisputeModel.fromFirestore(d)).toList());

  /// Risolve una segnalazione CP voce per voce (Step 42) — ogni entry di
  /// [updatedEntries] porta già il proprio [DisputedCp.status] e
  /// l'eventuale [DisputedCp.decisionReason] deciso dall'admin; le voci non
  /// toccate dalla decisione corrente vanno passate invariate (stesso
  /// status che avevano). Per ogni voce che passa a "accettata" in QUESTA
  /// chiamata (mai per quelle già accettate in precedenza, altrimenti si
  /// duplicherebbe il passaggio sintetico — `recordWaypointPassage` usa
  /// `.add()`, non è idempotente) registra un passaggio sintetico con
  /// timestamp a metà tra inizio e fine della PS (stessa risoluzione
  /// start/end usata da ClassificaEngine._computeSpeciali): da quel momento
  /// il CP risulta passato e la penalità sparisce dal calcolo senza alcuna
  /// logica speciale nel motore di classifica.
  Future<void> resolveCpDisputeEntries({
    required EventModel event,
    required String disputeId,
    required String pilotId,
    required List<DisputedCp> previousEntries,
    required List<DisputedCp> updatedEntries,
  }) async {
    final eventId = event.id;
    await _db
        .collection(FirebaseConstants.cpDisputes)
        .doc(eventId)
        .collection(FirebaseConstants.disputes)
        .doc(disputeId)
        .update({
      'missedCps': updatedEntries.map((c) => c.toMap()).toList(),
      'status': updatedEntries.every((c) => c.status == CpDisputeStatus.accepted)
          ? CpDisputeStatus.accepted.name
          : updatedEntries
                  .every((c) => c.status == CpDisputeStatus.rejected)
              ? CpDisputeStatus.rejected.name
              : CpDisputeStatus.pending.name,
    });

    final previousByCpId = {for (final c in previousEntries) c.cpId: c.status};
    final newlyAccepted = updatedEntries
        .where((c) =>
            c.status == CpDisputeStatus.accepted &&
            previousByCpId[c.cpId] != CpDisputeStatus.accepted)
        .toList();

    if (newlyAccepted.isNotEmpty) {
      final myPassages = (await getPassagesOnce(eventId))
          .where((p) => p.userId == pilotId)
          .toList();
      // Percorso alternativo, Parte 5 — le speciali della variante con cui
      // QUESTO pilota ha corso (mai quella attiva sull'evento): la
      // segnalazione CP riguarda una sua PS specifica, deve risolversi
      // sulla stessa variante con cui l'ha effettivamente corsa.
      final pilotStatus = await getPilotStatusOnce(eventId, pilotId);
      final routeId = pilotStatus?['routeVariantId'] as String? ?? 'A';
      final variant = event.routeVariant(routeId) ?? event.routeAAsVariant;
      for (final cp in newlyAccepted) {
        final special =
            variant.speciali.where((s) => s.id == cp.specialeId).firstOrNull;
        if (special == null) continue;
        final iniP = myPassages
            .where((p) => p.waypointId == special.waypointInizio.id)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final finP = myPassages
            .where((p) => p.waypointId == special.waypointFine.id)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (iniP.isEmpty || finP.isEmpty) continue;
        final start = iniP.first;
        final end = finP.firstWhere(
            (p) => p.timestamp.isAfter(start.timestamp),
            orElse: () => finP.first);
        if (!end.timestamp.isAfter(start.timestamp)) continue;
        final midTs = start.timestamp
            .add((end.timestamp.difference(start.timestamp)) ~/ 2);
        await recordWaypointPassage(
          eventId: eventId,
          userId: pilotId,
          waypointId: cp.cpId,
          waypointNome: cp.cpNome,
          timestamp: midTs,
          timingMethod: 'dispute',
        );
      }
    }

    final accepted =
        updatedEntries.where((c) => c.status == CpDisputeStatus.accepted).length;
    final rejected =
        updatedEntries.where((c) => c.status == CpDisputeStatus.rejected).length;
    await _sendUserNotification(
      recipientId: pilotId,
      type: rejected == 0
          ? NotificationType.cpDisputeAccepted
          : NotificationType.cpDisputeRejected,
      title: 'Segnalazione CP verificata',
      body: 'L\'organizzatore ha verificato la tua segnalazione: '
          '$accepted CP accolti, $rejected rifiutati.',
    );
  }

  // Penalty settings (documento unico 'default' nella collezione penalty_settings)

  static const _penaltyDocId = 'default';

  Stream<PenaltySettingsModel> penaltySettingsStream() => _db
      .collection(FirebaseConstants.penaltySettings)
      .doc(_penaltyDocId)
      .snapshots()
      .map((doc) => doc.exists
          ? PenaltySettingsModel.fromMap(
              doc.data() as Map<String, dynamic>)
          : const PenaltySettingsModel());

  Future<PenaltySettingsModel> getPenaltySettings() async {
    final doc = await _db
        .collection(FirebaseConstants.penaltySettings)
        .doc(_penaltyDocId)
        .get();
    if (!doc.exists) return const PenaltySettingsModel();
    return PenaltySettingsModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  Future<void> savePenaltySettings(PenaltySettingsModel settings) => _db
      .collection(FirebaseConstants.penaltySettings)
      .doc(_penaltyDocId)
      .set(settings.toMap());

  // Override penalità contestuale all'evento
  // (events/{eventId}/penalty_settings/override) — null se non impostato,
  // in tal caso si applicano i valori predefiniti globali

  static const _penaltyOverrideDocId = 'override';

  DocumentReference<Map<String, dynamic>> _eventPenaltyOverrideDoc(
          String eventId) =>
      _db
          .collection(FirebaseConstants.events)
          .doc(eventId)
          .collection(FirebaseConstants.penaltySettings)
          .doc(_penaltyOverrideDocId);

  Stream<PenaltySettingsModel?> eventPenaltySettingsStream(String eventId) =>
      _eventPenaltyOverrideDoc(eventId).snapshots().map((doc) =>
          doc.exists ? PenaltySettingsModel.fromMap(doc.data()!) : null);

  Future<PenaltySettingsModel?> getEventPenaltySettings(String eventId) async {
    final doc = await _eventPenaltyOverrideDoc(eventId).get();
    if (!doc.exists) return null;
    return PenaltySettingsModel.fromMap(doc.data()!);
  }

  Future<void> saveEventPenaltySettings(
          String eventId, PenaltySettingsModel settings) =>
      _eventPenaltyOverrideDoc(eventId).set(settings.toMap());

  Future<void> resetEventPenaltySettings(String eventId) =>
      _eventPenaltyOverrideDoc(eventId).delete();

  /// Penalità effettive per un evento: override contestuale se presente,
  /// altrimenti i valori predefiniti globali.
  Future<PenaltySettingsModel> getEffectivePenaltySettings(
      String eventId) async {
    final override = await getEventPenaltySettings(eventId);
    if (override != null) return override;
    return getPenaltySettings();
  }
}
