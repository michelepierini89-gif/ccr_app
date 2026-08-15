# CCR App — Riepilogo di Progetto

**Coppa Canta Rally** — App Flutter multipiattaforma per la gestione di eventi rally  
**Data aggiornamento:** 15 agosto 2026 (Step 44 completato)  
**Branch:** main  
**Versione:** 1.0.2+3

---

## Stack Tecnologico

| Layer | Tecnologia |
|---|---|
| Framework UI | Flutter 3.x (SDK ^3.12.1) |
| Linguaggio | Dart |
| Backend / Auth | Firebase (Firebase Core, Firebase Auth) |
| Database | Cloud Firestore |
| Storage file | Firebase Storage |
| State management | Riverpod (`flutter_riverpod ^2.6.1`) |
| Routing | GoRouter (`go_router ^15.1.2`) |
| Mappe | flutter_map + OpenStreetMap (tile) |
| Geolocalizzazione | geolocator + latlong2 |
| GPS background | geolocator AndroidSettings + ForegroundNotificationConfig |
| Parser tracciati | gpx + xml (parsing GPX/KML) |
| File picking | file_picker |
| Localizzazione | intl (locale it_IT) |
| Utility | uuid, path_provider, shared_preferences |

**Piattaforme supportate:** Web (principale), Android, iOS  
*(macOS e Windows esclusi da git)*

---

## Struttura Cartelle

```
ccr_app/
├── lib/
│   ├── main.dart                   # Entry point, init Firebase + locale
│   ├── app.dart                    # CcrApp widget + GoRouter config
│   ├── firebase_options.dart       # Config Firebase per piattaforma
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   └── firebase_constants.dart
│   │   ├── models/
│   │   │   ├── championship_model.dart   # Campionato: id, nome, stagione, eventIds, colorIndex
│   │   │   ├── event_model.dart
│   │   │   ├── gps_point_model.dart
│   │   │   ├── registration_model.dart   # + teamName: String? (nuovo squadra al volo)
│   │   │   ├── special_model.dart        # + controlPoints: List<WaypointModel>
│   │   │   ├── team_model.dart
│   │   │   ├── user_model.dart           # UserRole: admin / pilot
│   │   │   └── waypoint_model.dart
│   │   ├── services/
│   │   │   ├── auth_service.dart
│   │   │   ├── firestore_service.dart    # + championship CRUD, getPassagesOnce, getRegistrationsOnce
│   │   │   ├── gps_service.dart          # + positionStream (broadcast); AndroidSettings no timeLimit
│   │   │   ├── gpx_parser.dart           # Parser GPX + KML (web-safe, no dart:io)
│   │   │   ├── offline_queue_service.dart # + queueRegistration teamName, queueJoinTeam
│   │   │   ├── storage_service.dart      # downloadTrack via SDK (refFromURL+getData, autenticato)
│   │   │   └── waypoint_detector.dart
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   └── app_theme.dart            # Tema scuro (bg #0a0c12, accent #e53e1e)
│   │   ├── utils/
│   │   │   ├── color_utils.dart
│   │   │   └── location_utils.dart
│   │   └── widgets/
│   │       └── skeleton_loader.dart      # SkeletonBox animato (ColorTween 900ms)
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── providers/auth_provider.dart
│   │   │   ├── screens/login_screen.dart
│   │   │   ├── screens/register_screen.dart
│   │   │   └── widgets/ (ccr_button, ccr_text_field)
│   │   │
│   │   ├── admin/
│   │   │   ├── providers/admin_provider.dart  # + eventStreamProvider
│   │   │   ├── screens/
│   │   │   │   ├── admin_home_screen.dart         # + bottone trofeo AppBar → /admin/championships
│   │   │   │   ├── championship_screen.dart        # lista campionati + crea; gestione eventi con Switch
│   │   │   │   ├── create_event_screen.dart       # dimensione squadra + tipologia classifica
│   │   │   │   ├── event_management_screen.dart   # tab responsive, bloccate in BOZZA
│   │   │   │   ├── live_tracking_screen.dart      # mappa multi-pilota real-time + GPX evento
│   │   │   │   ├── registrations_screen.dart      # filtri, approva/rifiuta, team info
│   │   │   │   └── specials_editor_screen.dart    # slider GPS + polyline reale + control points
│   │   │   └── widgets/
│   │   │       ├── event_card_admin.dart
│   │   │       └── special_tile.dart              # mostra n. punti di controllo
│   │   │
│   │   ├── pilot/
│   │   │   ├── providers/pilot_provider.dart      # + eventProvider FutureProvider
│   │   │   ├── providers/pilot_stats_provider.dart # pilotStatsProvider (FutureProvider, ricalcola classifiche)
│   │   │   ├── screens/
│   │   │   │   ├── pilot_home_screen.dart          # 4 tab: Gare|GPS|Campionati|Profilo; PopScope; bottone "Le mie statistiche"
│   │   │   │   ├── pilot_stats_screen.dart         # statistiche pilota: gare/speciali vinte/podio
│   │   │   │   ├── event_detail_screen.dart        # skeleton, errore+retry, dialog iscrizione 2-step + suggerimento squadra preferita
│   │   │   │   ├── event_list_screen.dart          # skeleton, errore+retry, empty state CTA
│   │   │   │   ├── championship_standings_screen.dart # podio + tabella classifica campionato
│   │   │   │   ├── gps_recording_screen.dart       # START/FINE GARA, mappa live GPX+PS+ristoro, freccia bearing
│   │   │   │   └── team_screen.dart                # nomi membri da registrazioni; bottone "Imposta come squadra preferita"
│   │   │   └── widgets/ (event_card_pilot, gps_status_widget)
│   │   │
│   │   └── map/
│   │       ├── screens/track_map_screen.dart
│   │       └── widgets/ (track_layer, waypoint_marker)
│
│   │   ├── classifica/
│   │   │   ├── providers/classifica_provider.dart    # Provider.family, combina event+passages+regs+teams
│   │   │   └── screens/classifica_screen.dart        # Card espandibili, badge oro/argento/bronzo, LIVE
│   │   │
│   │   └── timing/
│   │       └── screens/timing_screen.dart             # I miei tempi (pilota) / tutti i tempi + CSV (admin)
│
├── android/                        # Config Android + google-services.json
├── ios/                            # Config iOS
├── web/                            # Config Flutter web
├── assets/icons/                   # Icone app
├── cors.json                       # Configurazione CORS Firebase Storage
├── set-storage-cors.js             # Script Node.js per applicare CORS
├── firestore.indexes.json          # Indici Firestore dichiarativi
├── firestore.rules                 # Regole sicurezza Firestore complete
├── firebase.json                   # Config deploy Firebase Hosting
└── pubspec.yaml
```

---

## Routing Applicativo

```
/login              → LoginScreen
/register           → RegisterScreen
/admin              → AdminHomeScreen
  /admin/create-event
  /admin/event/:id  → EventManagementScreen
    /admin/event/:id/registrations
    /admin/event/:id/live          → LiveTrackingScreen
    /admin/event/:id/timing        → TimingScreen (admin)
  /admin/championships             → ChampionshipScreen (lista + crea)
  /admin/championships/:id         → ChampionshipManagementScreen (toggle eventi)
  /admin/championships/:id/standings → ChampionshipStandingsScreen (admin)
/pilot              → PilotHomeScreen (4 tab: Gare|GPS|Campionati|Profilo)
  /pilot/event/:id  → EventDetailScreen
    /pilot/event/:id/team          → TeamScreen
    /pilot/event/:id/classifica    → ClassificaScreen
    /pilot/event/:id/timing        → TimingScreen (pilota)
  /pilot/gps        → GpsRecordingScreen
  /pilot/championships/:id         → ChampionshipStandingsScreen (pilota)
```

**Redirect automatico basato su ruolo:** dopo il login, `UserRole.admin` va a `/admin`, altrimenti a `/pilot`.

---

## Step Completati

### Step 1 — Struttura completa progetto Flutter ✅
- Architettura feature-first (`auth`, `admin`, `pilot`, `map`)
- Tutti i modelli, servizi, tema dark, GoRouter con redirect ruolo, Riverpod
- Supporto Firebase su web con `firebase_options.dart` (generato con `flutterfire configure`)
- Indici Firestore in `firestore.indexes.json`
- Locale `it_IT` inizializzato prima di `runApp` con `initializeDateFormatting`

### Step 2 — Feature Admin: Gestione Eventi ✅
- `CreateEventScreen`: nome, luogo, data, descrizione, dimensione squadra (min/max stepper), tipologia classifica
- `EventManagementScreen`: tab Tracciato / Iscrizioni / Live — layout responsive (wide ≥600px / mobile verticale), tab Iscrizioni e Live bloccate in stato BOZZA
- Upload GPX/KML tramite FilePicker → Storage → Firestore (`trackUrl`)
- Auto-caricamento tracciato da Storage all'apertura; parser GPX/KML web-safe (no `dart:io`)
- `RegistrationsScreen`: filtri (Tutti / Attesa / Approvati / Rifiutati), approva/rifiuta, visualizzazione squadra e copilota, warning squadre fuori range
- Anti-flickering: `EventManagementScreen` usa `eventStreamProvider` (stream su singolo doc Firestore, non su collection intera)

### Step 2b — SpecialsEditor: riscrittura completa ✅

**Modello:**
- `SpecialModel`: aggiunto campo `controlPoints: List<WaypointModel>` (serializzato/deserializzato su Firestore)
- `SpecialTile`: subtitle mostra conteggio punti di controllo (`n punti di controllo`)

**Layout responsive:**
- Wide (≥600px): controlli a sinistra 40% / mappa a destra 60%, pannello scrollabile
- Mobile: mappa in alto (altezza adattiva 220–400px), pannello scrollabile sotto

**Slider inizio/fine:**
- Slider continuo sui punti GPS della traccia (es. `1247 / 5369`), marker si aggiorna sulla mappa in tempo reale durante il drag
- Modalità click-su-mappa: bottone "Mappa" attiva la selezione (cursore `precise`), banner contestuale in cima alla mappa, click posiziona il marker sul punto più vicino della traccia
- Contatore `X / N` accanto allo slider

**Sezione tracciato:**
- Polyline colorata che evidenzia solo i punti GPS reali tra inizio e fine (non più retta)
- Badge lunghezza speciale (km, calcolo Haversine, aggiornato in tempo reale)
- Badge lunghezza totale traccia (km, calcolato una volta in `initState`)

**Punti di controllo (P1…P10):**
- Min consigliato 1, max 10 per speciale
- Ogni punto ha slider dedicato + bottone "Mappa" per posizionamento click
- Colore automatico complementare (rotazione 180° HSL sulla tinta del colore speciale): blu→giallo, verde→viola, arancio→blu, ecc.
- Marker `P1`, `P2`... sulla mappa con bordo pulsante quando in modalità selezione attiva
- Pulsante rimozione per ogni punto (icona `remove_circle_outline`)

### Step 3 — Feature Admin: Live Tracking ✅
- `LiveTrackingScreen`: mappa flutter_map con marker piloti, online/offline chip, stats bar real-time

### Step 4 — Feature Pilota: Iscrizione ed eventi ✅
- `EventListScreen`: lista eventi aperti con stato iscrizione, pulsante iscrizione rapida
- `EventDetailScreen`: header evento, mappa tracciato (caricamento da Storage, stesso flusso admin), prove speciali, stato iscrizione, link squadra
- Anti-flickering: usa `eventStreamProvider` (stream su singolo doc Firestore)
- `TeamScreen`: crea/unisciti/lascia squadra, nomi/cognomi membri risolti da registrazioni (non UID grezzi)

### Step 5 — Registrazione GPS ✅
- `GpsRecordingScreen`: pulsante START/STOP con animazione, modalità GPS (idle/trasferimento/speciale/near-waypoint), waypoint passati, nome evento in header
- I waypoint vengono caricati dai `speciali` dell'evento all'avvio della registrazione
- Inclusi i `controlPoints` di ogni speciale nel set di waypoint passati a `startRecording()`

### Step 5b — Lunghezze, punto ristoro, edit evento da gestione ✅
- `SpecialTile` dentro `EventManagementScreen`: mostra i km calcolati con Haversine sui punti reali (stesso algoritmo di SpecialsEditor)
- Badge lunghezza traccia totale accanto al contatore punti GPS
- **Punto ristoro:** dialog con `FlutterMap` tap-to-place; marker giallo `local_gas_station` salvato come `fuelPoint: WaypointModel?` in Firestore; visibile sulla mappa tramite `TrackMapScreen`; rimovibile con pulsante X
- Modifica dimensione squadra (min/max stepper) con vincoli e salvataggio debounced 800ms
- Modifica tipologia punteggio (`DropdownButton`) con salvataggio debounced 800ms
- `EventModel`: aggiunto campo `fuelPoint` con serializzazione Firestore e `copyWith(clearFuelPoint: bool)`
- `TrackMapScreen`: parametro opzionale `fuelPoint` per rendering marker ristoro
- `_TracciatoTab` convertito a `ConsumerStatefulWidget`

### Step 5c — Logica pilota completa ✅
- `EventDetailScreen`: lista squadre con posti disponibili, pulsanti Unisciti/Crea nuova squadra, squadre piene in grigio
- Flusso iscrizione con selezione squadra (join o create) e notifica admin
- Stato iscrizione in tempo reale via stream (inAttesa/approvato/rifiutato)
- Pulsante AVVIA GPS visibile solo dopo approvazione
- `GpsRecordingScreen`: START disabilitato finché admin non abilita la partenza; messaggio "In attesa del via dell'organizzatore"
- Pulsante RITIRO con doppia conferma durante il tracking attivo
- `LiveTrackingScreen` (admin): toggle Abilita/Blocca partenza in tempo reale
- `EventModel.startEnabled`, `FirestoreService.setStartEnabled()`, `FirestoreService.recordWithdrawal()`

### Step 5d — Tracking GPS attivo (mappa live) ✅
- `GpsService`: accumulo track locale (`List<LatLng>`), calcolo distanza progressiva, `remainingWaypoints` getter
- `GpsRecordingScreen`: due viste — pre-partenza (big button) e tracking attivo (mappa live)
- Mappa live: polyline traccia percorsa, marker posizione attuale con cerchio accuratezza, pin waypoint rimanenti
- Auto-follow posizione con disattivazione su drag utente e pulsante re-center (⊕)
- Strip statistiche: velocità, distanza, tempo, precisione GPS con indicatore colore accuratezza
- Banner modalità (TRASFERIMENTO / IN SPECIALE / WAYPOINT VICINO) colorato live
- Log ultimo waypoint passato con contatore totale
- Pulsanti STOP e RITIRO sempre visibili senza scroll

### Step 6 — Classifica piloti in tempo reale ✅
- `ClassificaModel`: `WaypointPassageRecord`, `SpecialTempo`, `ClassificaEntry` con tie-handling
- `ClassificaEngine`: calcolo ranking per team con due tipologie:
  - Somma dei tempi (ascending)
  - Punteggio speciale stile F1 (25/20/16/13/11/10/9/8/7/6); validazione control points; rilevamento ritirati
- `FirestoreService`: stream `passages` (`tracking/{id}/passages`) e stream `withdrawals`
- `classificaProvider`: `Provider.family`, combina event + passages + regs + teams + live tracking, ricomputa ad ogni update Firestore
- `ClassificaScreen`: card espandibili per team, badge posizione oro/argento/bronzo, indicatore LIVE, progress dots SS, breakdown per speciale con tempo formattato `mm:ss.cc`
- Integrazione admin: 4° tab "Classifica" in `EventManagementScreen`
- Integrazione pilota: pulsante CLASSIFICA in `EventDetailScreen` + route `/pilot/event/:id/classifica`

### Step 7 — Timing, GPS speciali, stato piloti, regole Firestore ✅
- `GpsService`: rilevamento entry/exit speciali (`inSpecial` mode) con beacon precisi
- `GpsRecordingScreen`: passa `specials` al servizio, banner speciale corrente colorato
- `TimingScreen`: vista dual-mode
  - **Pilota:** I miei tempi per speciale con format mm:ss.cc
  - **Admin:** Tutti i tempi per tutti i team, ordinati, con pulsante export CSV
- `EventManagementScreen`: 5° tab "Tempi"
- `EventDetailScreen`: pulsante "I miei tempi" visibile solo a piloti approvati
- `LiveTrackingScreen`: stato piloti in real-time (IN GARA / OFFLINE / RIT / N.P.)
- `AdminHomeScreen`: badge giallo con count iscrizioni in attesa per ogni evento
- `csv_export`: utility multi-piattaforma con conditional import (web/io/stub)
- **Regole Firestore complete** in `firestore.rules`: lettura/scrittura autenticati, write eventi solo admin, write tracking solo owner, write passages solo owner

### Step 7c — FCM (Notifiche Push) ✅
- Cloud Functions Gen 2, deploy su eur3, VAPID key configurata
- Notifiche push a piloti per cambio stato iscrizione e abilitazione partenza

### Step 9 — Deploy, Storage rules, UX offline ✅

**Deploy Firebase Hosting:**
- Build web release (`flutter build web --release`) deployata su https://ccr-enduro.web.app
- `firebase deploy --only hosting`

**Regole Firebase Storage (`storage.rules`):**
- Admin: legge e scrive tutto il bucket
- Piloti: leggono solo `tracks/{eventId}/*` se `firestore.exists(events/{eventId}/iscritti/{userId})`
- Deploy con `firebase deploy --only storage`; `firebase.json` aggiornato con sezione `storage`

**UX offline avanzata (`OfflineQueueService`):**
- Estende `ChangeNotifier`; provider aggiornato a `ChangeNotifierProvider` per reattività Riverpod
- `queueJoinTeam()`: nuovo metodo; in `_joinTeamAndRegister` ora mette in coda joinTeam + registrazione
- `queueTracking()`: salva solo l'ultima posizione per coppia `eventId/userId` (nessun accumulo)
- `GpsService`: `updatePilotTracking` usa `.catchError` → `queueTracking` invece di ignorare silenziosamente
- Backoff esponenziale per le sync: 30s → 60s → 120s → … → max 1 ora; ogni item conserva `retryCount` e `nextRetryAt`
- `_syncList()`: helper generico con backoff; `_syncTrackingMap()`: sync separata per il Map tracking

**Banner e badge offline (`PilotHomeScreen`):**
- Banner giallo con contatore "N elementi in attesa di sincronizzazione" visibile quando `offlineQueueProvider.totalPendingCount > 0`
- Pulsante "Sincronizza" manuale nel banner (chiama `syncPending` direttamente)
- Badge giallo (pallino 8×8px) sull'icona "Gare" nella bottom nav quando ci sono dati pending

**Pull-to-refresh:**
- `EventDetailScreen`: `RefreshIndicator` che cancella la cache del tracciato e richiama `_autoLoadTrack`; `AlwaysScrollableScrollPhysics` per garantire lo swipe anche con poco contenuto
- `TimingScreen`: convertito da `ConsumerWidget` a `ConsumerStatefulWidget`; `RefreshIndicator` su admin ListView e su pilota `SingleChildScrollView`; refresh invalida `classificaProvider(eventId)`

### Step 8 — Offline, Ottimizzazioni, Test, Documentazione ✅

**Offline support (SharedPreferences queue):**
- `OfflineQueueService`: coda locale per waypoint passages e registrazioni
- `GpsService`: cattura errori Firestore, salva passaggi offline; tracking live ignorato silenziosamente
- `EventDetailScreen`: iscrizione salvata offline con banner informativo
- Sync automatica dei dati in coda all'avvio della registrazione GPS
- `FirestoreService._db`: getter lazy (non campo final) per compatibilità test

**Ottimizzazioni:**
- `EventListScreen` → `ConsumerStatefulWidget`, loading state per quick register con `_loadingEventId`
- `EventCardPilot`: parametro `isLoading`, spinner nel pulsante Iscriviti
- `_RegistrationList` → `ConsumerStatefulWidget`: loading su Approva/Rifiuta, rimosso `ref` come parametro costruttore
- `flutter analyze` a zero warning su tutto il codebase

**Test (43 test):**
- `test/routes_test.dart`: LoginScreen, RegisterScreen, AdminHome, EventList, EventDetail, EventManagement, GpsRecording
- `test/features/pilot/pilot_flow_test.dart`: flusso completo login→evento→iscrizione→GPS→tempi
- `test/features/admin/event_management_screen_test.dart`: aggiornato con SharedPreferences

### Step 7b — Notifiche in-app e salvataggio traccia parziale ✅
- Notifiche in-app per piloti: cambio stato iscrizione, abilitazione partenza, approvazione admin
- `AppNotificationModel`: modello con tipo, testo, read/unread, timestamp
- `FirestoreService`: stream notifiche non lette per utente, mark as read
- Salvataggio traccia GPS parziale su Firestore al momento del ritiro del pilota
- `GpsService`: flush punti accumulati a Firebase al ritiro anche se la registrazione non è conclusa
- PWA manifest aggiornato: nome app, colori brand, icone per installazione su mobile

### CORS Firebase Storage ✅
CORS applicato sul bucket `ccr-enduro.firebasestorage.app` tramite `cors.json`.  
Origini abilitate: `http://localhost:8080`, `http://localhost:*`, `https://ccr-enduro.web.app`, `https://ccr-enduro.firebaseapp.com`.

Per ri-applicare se necessario (**Opzione A — Google Cloud Shell**):
```bash
cat > /tmp/cors.json << 'EOF'
[{"origin":["http://localhost:8080","http://localhost:*","https://ccr-enduro.web.app","https://ccr-enduro.firebaseapp.com"],"method":["GET","HEAD"],"responseHeader":["Content-Type","Content-Length"],"maxAgeSeconds":3600}]
EOF
gsutil cors set /tmp/cors.json gs://ccr-enduro.firebasestorage.app
gsutil cors get gs://ccr-enduro.firebasestorage.app
```

**Opzione B — Script Node.js locale (`set-storage-cors.js` nella root):**
1. Scarica service account key da Firebase Console → Project Settings → Service Accounts
2. `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json`
3. `node set-storage-cors.js`

---

## Problemi Risolti

| Problema | Causa | Soluzione |
|---|---|---|
| `LocaleDataException` al boot | `it_IT` non inizializzato prima di `runApp` | `await initializeDateFormatting('it_IT')` in `main()` |
| Build web fallita per `dart:io` | `GpxParser` usava `File` di `dart:io` | Rimosso; il parser accetta solo `String content` |
| Firebase non trovato su web | Mancava `firebase_options.dart` con config web | Generato con `flutterfire configure` e incluso |
| Query Firestore senza indice | Filtri composti senza indice dichiarato | Aggiunto `firestore.indexes.json` con gli indici richiesti |
| Sessione non persistente | Mancava persistenza auth su web | Risolta con Firebase Auth persistence |
| Flickering schermate evento | Stream su collection intera → rebuild ad ogni evento | `getEventById()` stream su singolo doc + `eventStreamProvider` |
| Track non visibile lato pilota | `EventDetailScreen` passava `trackPoints: const []` | Ora carica il tracciato da Storage come la schermata admin |
| Waypoint GPS vuoti | `startRecording()` riceveva `waypoints: const []` | Ora carica inizio/fine e control points dagli speciali |
| Nome evento GPS troncato | `GpsRecordingScreen` mostrava l'ID raw | Ora mostra il nome evento caricato da Firestore |
| SpecialsEditor solo linea retta | Tracciato speciale era una retta tra due punti arbitrari | Polyline calcolata sui punti GPS reali tra gli indici inizio/fine |
| SpecialModel senza control points | `SpecialModel` non aveva campo `controlPoints` | Aggiunto `controlPoints: List<WaypointModel>` con serializzazione Firestore |
| Nomi membri come UID | `TeamScreen` mostrava gli UID grezzi dei membri | Risolti nome/cognome tramite lookup nelle registrazioni |
| Porta 8080 occupata al riavvio | Processo Flutter precedente non terminato | `lsof -ti:8080 | xargs kill -9` poi riavvio con nohup |
| WSL2 OOM crash durante Gradle build | Nessun limite memoria su WSL2 → Ubuntu usa tutta la RAM | Creato `/mnt/c/Users/admin/.wslconfig` con `memory=4GB processors=2 swap=2GB`; riavviare WSL2 con `wsl --shutdown` |
| Test crash su FirestoreService | `FirebaseFirestore.instance` chiamato a costruzione → fallisce senza Firebase init | Cambiato da campo `final _db` a getter `FirebaseFirestore get _db` (lazy init) |
| Test crash su GpsService | GpsService crea FirestoreService che fallisce senza Firebase | Risolto dal getter lazy sopra; aggiunto override `sharedPreferencesProvider` in tutti i test |
| `LocaleDataException` nei test | `DateFormat` usato in EventDetailScreen senza locale inizializzato | Aggiunto `setUpAll(() => initializeDateFormatting('it_IT'))` |
| `unnecessary_underscores` lint nei test | GoRoute builder con `(_, __)` trigger lint Dart 3 | Sostituito con `(_, _)` (wildcard multipli validi in Dart 3) |
| `firebase_storage/unauthorized` su browser | `downloadTrack` usava `http.get` anonimo senza credenziali Auth | `FirebaseStorage.instance.refFromURL(url).getData()` porta il token automaticamente |
| Freccia pilota ferma al punto di avvio | `ref.listen` muoveva solo camera, non richiedeva `setState`; marker con `const` non si ricostruiva | `GpsService.positionStream` + `StreamBuilder` in `_buildActiveTracking`; `RotatedBox+Transform.rotate` non-const |
| Marker admin non aggiornati in real-time | `liveTrackingProvider` cacheato non triggera rebuild Riverpod su ogni emit Firestore | `StreamBuilder` diretto su `firestoreService.getPilotTracking()` bypassa la cache |
| DIST=0m e VEL=0 km/h su Android anche con GPS attivo | `LocationSettings(timeLimit: Duration(ms))` è un timeout, non un intervallo: scadeva dopo 3s senza movimento, `TimeoutException` terminava lo stream silenziosamente | Rimosso `timeLimit`; uso `AndroidSettings(intervalDuration:...)` con `ForegroundNotificationConfig` e `distanceFilter: 2`; error recovery con riavvio automatico stream |
| Marker pilota che salta da punto a punto ogni update GPS | GPS emette a intervalli discreti, il marker si teleporta senza transizione | `AnimationController` 500ms con lerp lineare `LatLng` tra `_fromPos` e `_targetPos`; `_displayPos` aggiornato a 60fps smooth |
| FINE GARA bloccato anche dopo completamento speciali se control points mancanti | Logica usava `remainingWaypoints.isEmpty` che include tutti i waypoint (anche i CP intermedi) | Nuovo metodo `_allSpecialsCompleted`: conta `specialEntries` con `exitTime != null` vs `event.speciali.length` |
| Classifica mostra solo "CP mancante" senza dettaglio | `SpecialTempo.controlPointsOk` era solo un bool senza info su quali CP | Aggiunto `missedCpPositions: List<int>` in `SpecialTempo`; motore calcola posizioni 1-based; dialog tappable in classifica |

### Step 11 — GPS real-time, mappe avanzate, fix Storage (05 giugno 2026) ✅

**Fix `firebase_storage/unauthorized`:**
- `storage_service.dart`: `downloadTrack` usa `FirebaseStorage.instance.refFromURL(url).getData()` invece di `http.get` anonimo — il SDK porta automaticamente il token Firebase Auth
- `storage.rules` + `firestore.rules`: regole permissive per sviluppo (`allow read, write: if request.auth != null`)
- ⚠️ **Prima della produzione** ripristinare regole granulari (presenti in git history commit `25ad689`)

**Mappa pilota live (`gps_recording_screen.dart`):**
- Traccia GPX evento sovrapposta in rosso (caricata da Storage in background all'avvio)
- Marcatori PS1/PS2 ▶/■ con colore per speciale e etichetta inizio/fine, da `event.speciali`
- Marker ristoro giallo `local_gas_station` da `event.fuelPoint`
- Punti di controllo nascosti dalla mappa (filtro `WaypointType.intermedio`)
- Posizione pilota: freccia `Icons.navigation` rotante via `RotatedBox(quarterTurns:0) + Transform.rotate(angle: bearing)` — **non const**, si ricostruisce ad ogni emit GPS

**Real-time freccia pilota:**
- `GpsService`: aggiunto `StreamController<Position>.broadcast()` → `positionStream` getter; emette in `_onPosition` prima di `notifyListeners()`
- `GpsRecordingScreen`: `_gpsStream` inizializzato in `initState`; `_buildActiveTracking` wrappato in `StreamBuilder<Position>` — ad ogni emit: calcola `bearing` con `atan2`, chiama `MapController.move()` via `addPostFrameCallback`, ricostruisce marker non-const

**Blocco permanente dopo ritiro:**
- `build()` guarda `withdrawalsStreamProvider(eventId)` e calcola `isWithdrawn`
- `_buildPreStart`: se `isWithdrawn == true` mostra schermata "Sei ritirato da questa gara" con `Icons.flag` rosso e disabilita permanentemente il pulsante START

**STOP → FINE GARA:**
- Pulsante rinominato `FINE GARA` con `Icons.flag_circle_outlined`
- Abilitato solo quando `gps.remainingWaypoints.isEmpty` (tutti i waypoint di tutte le speciali passati)
- `Tooltip`: "Completa tutte le speciali prima di terminare" quando disabilitato

**Live admin (`live_tracking_screen.dart`):**
- Convertito a `ConsumerStatefulWidget`; carica traccia GPX evento e la mostra in rosso sulla mappa admin
- `build()` usa `StreamBuilder<List<GpsPointModel>>` diretto su `firestoreService.getPilotTracking()` invece di `ref.watch(liveTrackingProvider)` — marker piloti si aggiornano senza cache Riverpod

**Deploy:**
- `firebase deploy --only hosting` su https://ccr-enduro.web.app
- `git push origin main` → GitHub Actions genera APK Android automaticamente

### Step 12 — Navigazione, Campionati, Iscrizione 2-step (05 giugno 2026) ✅

**Navigazione pilota migliorata:**
- `SkeletonBox` animato (`ColorTween` 900ms repeat-reverse) in `lib/core/widgets/skeleton_loader.dart`
- `EventListScreen`: 4 card skeleton durante caricamento; stato errore con `Icons.cloud_off` + pulsante Riprova; empty state con icona tonda accent + testo guida + pulsante Aggiorna
- `EventDetailScreen`: skeleton header durante caricamento; stato errore con retry; loading indica il nome evento nell'AppBar
- `PilotHomeScreen`: 4 tab (Gare | GPS | Campionati | Profilo) con icone filled/outlined per tab attivo; titolo AppBar dinamico per tab; `PopScope(canPop: false)` con dialog di conferma uscita su back Android

**Sistema Campionati:**
- `ChampionshipModel`: id, nome, descrizione, stagione (int), eventIds (List<String>), colorIndex, createdBy, createdAt; `fromFirestore`/`toFirestore`/`copyWith`
- `FirestoreService`: metodi CRUD campionati (`createChampionship`, `updateChampionship`, `deleteChampionship`, `getChampionships`, `getChampionshipById`, `addEventToChampionship`, `removeEventFromChampionship`) + `getPassagesOnce`, `getRegistrationsOnce`, `getTeamsOnce`, `getWithdrawalsOnce`
- **Admin** (`championship_screen.dart`): `ChampionshipScreen` — lista campionati + FAB crea (nome, year stepper, color picker); `ChampionshipManagementScreen` — header info, toggle eventi con `Switch` (`activeThumbColor`), link classifica, elimina con confirm
- **Classifica campionato** (`championship_standings_screen.dart`): `FutureProvider.family` aggrega `ClassificaEngine` per ogni evento del campionato, somma punti per teamNome (case-insensitive); podio a 3 colonne (altezze 80/60/50, colori oro/argento/bronzo); tabella completa con icone posizione; pulsante refresh
- **Pilota** (`PilotHomeScreen`): tab "Campionati" con `_allChampionshipsProvider` (StreamProvider, no filtro createdBy); naviga a `ChampionshipStandingsScreen` con `context.push`
- `AdminHomeScreen`: bottone trofeo `EmojiEvents` in AppBar → `/admin/championships`
- `app.dart`: 4 nuove route aggiunte (admin championships + pilot championships)

**Flusso iscrizione 2 step (`_RegistrationDialog` in `event_detail_screen.dart`):**
- `RegistrationModel.teamName: String?` aggiunto (nullable); `fromFirestore` legge `d['teamName']`; `toFirestore` scrive solo se non-null
- `OfflineQueueService.queueRegistration`: accetta `teamName` opzionale, lo propaga in `syncPending`
- `_RegistrationDialog` (ConsumerStatefulWidget): step 0 — lista squadre con posti disponibili (pulsante Scegli) + opzione "Crea nuova squadra" (TextField inline); step 1 — riepilogo evento/squadra/ruolo/pilota + banner info + pulsante "Invia richiesta"; `_StepDot` widget indicatore step
- `_doRegister()`: per squadra esistente → `joinTeam` + `registerForEvent`; per nuova squadra → `createTeam` + `registerForEvent(teamName: nome)`
- `EventListScreen`: pulsante "Iscriviti" naviga al dettaglio evento (no quick-register inline)

### Step 13 — Fix GPS stream Android (05 giugno 2026) ✅

**Root cause:**
`_startPositionStream` usava `LocationSettings(timeLimit: Duration(milliseconds: intervalMs))`. `timeLimit` in geolocator è un **timeout** (non un intervallo di polling): scadeva dopo 3 secondi senza movimento, lanciava `TimeoutException`, l'`onError` la ingoiava silenziosamente e lo stream moriva. Il mode non cambiava mai → `_startPositionStream` non veniva mai richiamato → DIST=0m, VEL=0 km/h bloccati.

**Fix applicato (`gps_service.dart`):**
- Rimosso `timeLimit` completamente
- **Android**: `AndroidSettings` con `intervalDuration: Duration(milliseconds: intervalMs)` per polling a cadenza configurabile; `ForegroundNotificationConfig(enableWakeLock: true)` per GPS attivo a schermo spento senza flutter_background_service
- **iOS/macOS**: `AppleSettings` con `activityType: ActivityType.fitness`, `pauseLocationUpdatesAutomatically: false`, `showBackgroundLocationIndicator: true`
- **Web**: `LocationSettings` base (senza piattaforma-specific)
- `distanceFilter: 2` su tutte le piattaforme (filtra rumore < 2m)
- Error recovery: `onError` ora riavvia `_startPositionStream` dopo 2s se `_isRecording == true`
- `flutter analyze`: zero warning

---

### Step 14 — GPS fluido, modalità mappa, UI migliorata (05 giugno 2026) ✅

**Traccia pilota blu:**
- Polyline percorso pilota in `#2196F3` blu per distinguerla chiaramente dalla traccia GPX evento rossa

**Pulsanti FINE GARA / RITIRO:**
- Layout flex 2:1 (FINE GARA più grande di RITIRO)
- FINE GARA si abilita quando tutte le speciali hanno exit time registrato (non solo `remainingWaypoints.isEmpty`)
- Metodo `_allSpecialsCompleted(gps, event)` con fallback su `remainingWaypoints` se l'evento non ha speciali

**Tempo speciale mm:ss.d:**
- Nella riga "ultimo passaggio", se il waypoint passato è di tipo `fine`, mostra il tempo elapsed della speciale in formato `mm:ss.d` (al decimo)
- Altrimenti mostra l'ora assoluta come prima

**Modalità mappa NORD/HEADING:**
- Pulsante `IconButton` in basso a sinistra della mappa
- NORD (icona `explore`, grigio): comportamento attuale, mappa fissa, freccia ruota
- HEADING (icona `navigation`, accent): mappa ruota con `MapController.rotate(-bearingDeg)`, freccia fissa verso l'alto (angle=0)
- Reset rotazione a 0 quando si torna in modalità NORD

**Dettaglio CP mancati in classifica:**
- `SpecialTempo`: aggiunto campo `missedCpPositions: List<int>` (posizioni 1-based dei CP non rilevati)
- `ClassificaEngine._computeSpeciali`: calcolo CP mancati per speciale
- `classifica_screen.dart`: icona warning tappabile apre `AlertDialog` con lista "P{n} non rilevato"

**Navigazione fluida:**
- `AppConstants.gpsIntervalInSpecialMs` ridotto da 1000ms a 500ms
- `AnimationController` duration 500ms con `addListener` per interpolazione lineare marker
- Tween manuale `LatLng`: lerp tra `_fromPos` e `_targetPos` su ogni tick dell'animazione
- `_displayPos` aggiornato smoothly; camera segue la posizione interpolata
- `TickerProviderStateMixin` (da `Single`) per supportare due `AnimationController`

**Deploy:**
- `firebase deploy --only hosting` su https://ccr-enduro.web.app
- `git push origin main` → GitHub Actions genera APK Android

---

### Step 15 — Sistema penalità completo (05 giugno 2026) ✅

**PenaltySettingsModel:**
- Nuovo modello `lib/core/models/penalty_settings_model.dart` con campi: `cp1Mancato` (60s), `cp2Mancati` (180s), `cp3oPiuMancati` (360s), `ritiroCompagno` (600s)
- `fromMap` / `toMap` / `copyWith` / `formatSeconds()` (es. "1m 30s")
- Collezione Firestore `penalty_settings`, documento `default`

**FirestoreService:**
- `penaltySettingsStream()` — Stream real-time delle penalità
- `getPenaltySettings()` — lettura singola (async)
- `savePenaltySettings()` — salvataggio

**ClassificaEngine (riscritta):**
- `compute()` accetta `PenaltySettingsModel penalties`
- `_cpPenaltySeconds(missedCount, p)`: 0→0s, 1→cp1Mancato, 2→cp2Mancati, 3+→cp3oPiuMancati
- `SpecialTempo.penaltySeconds` incluso nel `tempo` (tempo netto + penalità CP)
- Logica ritiro squadra: `ritirato` = TUTTI i membri ritirati; `ritiroCompagno` = ALCUNI (non tutti) ritirati → penalità `ritiroCompagno` aggiunta al `tempoTotale`
- `ClassificaEntry.ritiroCompagno` + `ritiroCompagnoPenaltySeconds`

**UI Penalità Admin (`penalty_settings_screen.dart`):**
- Schermata stepper (+/-30s per campo) accessibile da `AdminHomeScreen` via icona `tune`
- Pulsante Salva + Ripristina valori predefiniti
- Banner informativo, sezioni CP e Squadra

**Routing:**
- Route `/admin/penalty-settings` aggiunta in `app.dart`
- Icona `tune` in AppBar di `AdminHomeScreen`

**Classifica UI:**
- Badge "COMP. RIT." (arancione) su card pilota con ritiro compagno
- Indicatore "+Xs PEN" sotto il tempo totale nella card
- Indicatore "+Xs PEN" nella riga espansa di ogni speciale con penalità CP

**Campionato:**
- `ChampionshipStandingsScreen`: carica penalità da Firestore e le passa a `ClassificaEngine.compute()`

**Deploy:**
- `firebase deploy --only hosting` su https://ccr-enduro.web.app
- `git push origin main` → GitHub Actions genera APK Android

---

### Step 16 — Sicurezza, stabilità e performance (05 giugno 2026) ✅

**1 — Persistenza offline Firestore nativa:**
- `main.dart`: `FirebaseFirestore.instance.settings = Settings(persistenceEnabled: true, cacheSizeBytes: UNLIMITED)` immediatamente dopo `Firebase.initializeApp()`
- Sostituisce la gestione manuale con SharedPreferences per i dati Firestore
- Funziona su Android, iOS e Web (IndexedDB)

**2 — Regole Firestore sicure per produzione:**
- `events`: lettura tutti gli autenticati; scrittura solo admin
- `championships` / `penalty_settings`: lettura tutti; scrittura solo admin
- `tracking/{eventId}/pilots/{userId}`: scrittura solo proprio pilota; lettura solo admin (privacy GPS)
- `tracking/{eventId}/passages`: tutti gli autenticati (necessario per classifica)
- `users`: solo proprio utente o admin
- `user_notifications`: proprio utente (admin scrive per approvazioni iscrizioni)
- `events/iscritti`: crea il proprio; approva/rifiuta admin
- `events/withdrawals`: tutti leggono (classifica); crea solo proprio pilota
- Deployato su Firebase con `firebase deploy --only firestore:rules`

**3 — Chiusura listener Firestore:**
- `live_tracking_screen.dart`: `getPilotTracking()` spostato da `build()` a `initState()` → `_pilotStream` evita subscription duplicate ad ogni rebuild
- `gps_recording_screen.dart` e `event_management_screen.dart`: già corretti (Riverpod + initState)

**4 — FirebaseErrorHandler:**
- Nuovo `lib/core/utils/firebase_error_handler.dart`: switch su codici `FirebaseAuthException` e `FirebaseException`
- Traduce: `permission-denied` → "Non hai i permessi per questa operazione", `unavailable` → "Connessione assente, riprova tra poco", `not-found` → "Dato non trovato", errori auth → messaggi italiani comprensibili
- Applicato in login, register, GPS recording, event management, live tracking, penalty settings

**5 — GPS Samsung S21 (già implementato — verificato):**
- `AndroidManifest.xml` aveva già `android:foregroundServiceType="location"` su `BackgroundService`
- `uses-permission FOREGROUND_SERVICE_LOCATION` già presente
- Nessuna modifica necessaria; confermato compatibile Android 12+

**6 — RepaintBoundary GPS screen:**
- `gps_recording_screen.dart`: wrappa `FlutterMap` in `RepaintBoundary` → non repaint quando il timer stats scatta ogni secondo
- Wrappa il Container statistiche (velocità/distanza/tempo/precisione) in `RepaintBoundary` → non repaint quando arriva update GPS
- I due layer visivi si ridisegnano in modo completamente indipendente

**Deploy:**
- `firebase deploy --only hosting` su https://ccr-enduro.web.app
- `git push origin main` → GitHub Actions genera APK Android

---

### Step 17 — Recovery inizio speciale + Auto-archiviazione eventi (06-09 giugno 2026) ✅

**17a — Recovery retroattivo inizio speciale mancato (06 giugno 2026):**

Algoritmo per recuperare automaticamente un inizio speciale non registrato (es. GPS debole al momento del passaggio).

**Costanti** (`gps_constants.dart`):
- `kSpecialStartRecoveryRadiusMeters = 80.0` — distanza massima dal waypoint START per considerare il recovery valido
- `kSpecialStartRecoveryLookbackSeconds = 30` — finestra temporale in secondi da scandire nel tracciato registrato

**Logica** (`gps_service.dart` → `_trySpecialStartRecovery`):
1. Per ogni speciale non ancora iniziata e non già tentata: se la posizione GPS corrente è entro 3× raggio (240m) dal waypoint START → attiva recovery
2. Scansiona gli ultimi 30s di `_localTrack` / `_trackTimestamps` cercando il punto più vicino al waypoint START
3. Se quel punto è < 80m dal waypoint → imposta il suo timestamp come `entryTime` retroattivo
4. `_recoveryAttempted` set: un solo tentativo per speciale (evita loop infiniti)
5. Firestore: crea passage con `recoveredStart: true` via `recordWaypointPassage` (parametro opzionale)
6. Fallback offline queue se Firestore non disponibile

**UI** (`gps_recording_screen.dart`):
- Banner 26px light-blue (`Color(0xFF29B6F6)`) 18% opacity: "⚡ Inizio SP X recuperato"
- Auto-dismiss dopo 3 secondi via `Timer`
- `StreamSubscription<String>` su `recoveryStream` (StreamController nel GPS service)

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "feat: recovery retroattivo inizio speciale mancato" (0fba78e)
- `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

**17b — Auto-archiviazione automatica eventi (06-09 giugno 2026):**

**1 — Enum EventStatus aggiornato** (`event_model.dart`):
- Aggiunto `archiviata` → `enum EventStatus { bozza, aperto, inCorso, concluso, archiviata }`
- Aggiornati tutti gli switch exhaustivi: `event_card_admin.dart`, `event_card_pilot.dart`, `event_management_screen.dart`, test

**2 — Cloud Function `autoArchiveEvents`** (`functions/index.js`):
- Schedule: `"59 23 * * *"`, timezone: `Europe/Rome`, region: `europe-west1`
- Legge tutti gli eventi con `stato != 'archiviata'`
- Confronta `data` evento con la data odierna in timezone Rome via `Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome' })`
- Se `eventDateRome <= todayRome` → `batch.update(doc.ref, { stato: 'archiviata' })`
- Deploy richiede filesystem Linux nativo (vedi nota WSL2 sotto)

**3 — UI sezione "Gare passate":**
- `admin_home_screen.dart` e `event_list_screen.dart`: lista attivi + sezione "Gare passate" con `Opacity(opacity: 0.65)` per eventi archiviati
- Pulsante iscrizione non mostrato per eventi archiviati
- `event_management_screen.dart`: chip read-only "ARCHIVIATA" (con `Icons.archive_outlined`) al posto del dropdown stato

**4 — Firestore:**
- `getArchivedEvents()` in `firestore_service.dart`: query `stato == 'archiviata'` + `orderBy('data', descending: true)`
- `archivedEventsProvider` in `pilot_provider.dart`
- Index `stato ASC + data DESC` aggiunto in `firestore.indexes.json`

**Nota WSL2 — Deploy Cloud Functions:**
- Deploy da `/mnt/d/` (NTFS via WSL2) fallisce con timeout 10s: `require('firebase-admin')` impiega ~12s su NTFS vs ~0.1s su ext4
- Workaround: copiare `index.js` + `package.json` in `~/ccr_functions_deploy/`, eseguire `npm install` lì, creare `~/ccr_deploy_temp/firebase.json` con `"source": "/home/mikypierr/ccr_functions_deploy"`, fare deploy da lì
- Alternativa permanente: spostare il progetto nel filesystem nativo Linux (`~/`) oppure deployare da Windows PowerShell

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "feat: auto-archiviazione evento a 23:59 via Cloud Function scheduled" (d90a0b9)
- Functions deploy: `firebase deploy --only functions:autoArchiveEvents` ✅ (via path Linux nativo)
- `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

---

**18 — Blocco GPS gare archiviate, filtro gare passate, punti pericolo, classifiche campionato (12 giugno 2026):**

**A — Blocco GPS per gare archiviate/passate:**
- `event_model.dart`: estensione `DateTimeExtension.toMidnight()` → `DateTime(year, month, day, 23, 59, 59)`
- `gps_recording_screen.dart`: nuovo branch in `build()` (dopo `isFinished`/`isRetired`) → se `event.stato == archiviata` o `event.data` passata, mostra schermata "Gara conclusa" con icona bandiera, data svolgimento, pulsante "Vedi la mia traccia" (se il pilota ha una traccia GPS, naviga a `RaceResultScreen`) oppure testo "Non hai partecipato a questa gara"
- `event_detail_screen.dart`: per eventi archiviati, pulsante GPS sostituito da "Vedi risultati" → `RaceResultScreen`; pulsante "Iscriviti" nascosto

**B — Filtro "Gare passate" per partecipazione pilota:**
- `pilot_provider.dart`: nuovo `myArchivedRegistrationsProvider` (stream delle iscrizioni approvate del pilota sugli eventi archiviati)
- `event_list_screen.dart`: sezione "Gare passate" mostra solo eventi con iscrizione approvata del pilota; sezione (incluso header) nascosta se nessun evento corrisponde

**C — Punti pericolo su traccia:**
- `waypoint_model.dart`: nuova classe `DangerPointModel` (id, latitude, longitude, comment, createdAt) con fromMap/toMap/copyWith
- `event_model.dart`: campo `dangerPoints` (List<DangerPointModel>, default `[]`) con fromFirestore/toFirestore/copyWith
- `specials_editor_screen.dart`: modalità "Inserimento pericolo" (icona ⚠ amber in AppBar) → tap su mappa apre BottomSheet "Descrizione pericolo" con Salva/Annulla; marker amber esistenti tappabili per modifica/eliminazione (con conferma); sezione sinottica "Punti pericolo (N)" con coordinate + commento
- `waypoint_marker.dart` / `track_map_screen.dart` / `gps_recording_screen.dart` / `event_detail_screen.dart`: marker ⚠ amber (32px) sempre visibili sulla mappa pilota, tap mostra commento in SnackBar
- `app_constants.dart`: soglie `dangerWarningRadiusMeters` (150m), `dangerAlertRadiusMeters` (50m), `dangerAlertClearRadiusMeters` (60m), `dangerRemoveRadiusMeters` (100m), `gpsIntervalNearDangerMs` (500ms)
- `waypoint_detector.dart`: `dangerPointDistance()`
- `gps_service.dart`: tracking prossimità punti pericolo con isteresi (`_alertedDangerPoints`); banner giallo statico "ATTENZIONE" a 150m, banner rosso lampeggiante "PERICOLO" + bordo schermo lampeggiante a 50m (si ferma a >60m); GPS a 500ms entro 150m da un pericolo
- `gps_recording_screen.dart`: `_DangerWarningBanner`/`_DangerAlertBanner`, `AnimationController` per il lampeggio (500ms, opacity 0.3↔1.0)

**D — Classifiche campionato:**
- `classifica_model.dart`: tabella punti universale `kChampionshipPoints = [25,20,16,13,11,10,9,8,7,6,5,4,3,2,1]` + `pointsForPosition(position)`; nuovi modelli `EventResults`, `ChampionshipRaceScore`, `ChampionshipTeamStanding`, `ChampionshipStandings`
- `classifica_engine.dart`: `_rankByPoints`/`_rankByTime` ora valorizzano `punteggioTotale` per-evento usando `pointsForPosition` (somma punti speciali per gare 'a punti', punti per posizione finale per gare 'a tempi'); nuovo `computeChampionship()` che normalizza tutto in punti per-evento, scarta i 3 peggiori risultati per team e somma il resto
- `championship_model.dart`: nuovo campo `classPublished` (default `false`)
- `classifica_provider.dart`: `championshipStandingsProvider` (calcola `ChampionshipStandings` per un campionato) e `myChampionshipEntryIdProvider` (entryId del pilota corrente, per evidenziare la propria squadra)
- `championship_standings_table.dart` (nuovo widget condiviso): tabella Pos | Squadra | Punti totali con dettaglio per gara espandibile (badge "Gara a tempi"/"Gara a punti", punti scartati in grigio/barrati), podio per i primi 3
- `championship_screen.dart`: nuovo `ChampionshipAdminStandingsScreen` (route `/admin/championships/:id/standings`) con pulsante "Pubblica classifica" → imposta `classPublished = true`
- `championship_standings_screen.dart` (pilota, route `/pilot/championships/:id`, tab "Campionati" già presente in `pilot_home_screen.dart`): visibile solo se `classPublished == true`, riga della propria squadra evidenziata in accent (#e53e1e)

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "feat: blocco GPS gare archiviate + filtro gare passate pilota + punti pericolo con avviso lampeggiante + classifiche campionato"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

---

**19 — Traccia personalizzabile, marker pericolo migliorati, snap su traccia, riepiloghi completi, penalità default 10min (12 giugno 2026):**

**1 — Aspetto traccia pilota personalizzabile:**
- `track_appearance_service.dart` (nuovo): persiste su SharedPreferences larghezza (`trackWidth`, 2.0-10.0, default 5.0) e colore (`trackColor`, default blu) della polyline della traccia GPS pilota
- `track_appearance_provider.dart` (nuovo): `trackAppearanceServiceProvider` + `TrackAppearanceNotifier`/`trackAppearanceProvider` (Riverpod `Notifier`)
- `gps_recording_screen.dart`: icona ⚙ in AppBar (`_TopBar`, nuovo param `onSettingsTap`) apre BottomSheet "Aspetto traccia" con anteprima, slider larghezza (step 0.5) e 8 colori predefiniti (blu, ciano, verde, giallo, arancione, magenta, bianco, rosso), pulsante "Applica"; la polyline della traccia pilota in `_buildActiveTracking` legge `trackAppearanceProvider`

**2 — Marker pericolo più visibile:**
- `danger_marker_icon.dart` (nuovo): widget `DangerMarkerIcon` riutilizzabile — cerchio amber con bordo nero 2px, `Icons.warning_amber_rounded` nero centrato, ombra
- Sostituito il vecchio marker ⚠ amber (32px semplice) con `DangerMarkerIcon` in `waypoint_marker.dart` (mappa pilota/admin, 36px), `specials_editor_screen.dart` (marker mappa 36px, header bottom sheet 28px, lista sinottica 20px)

**3 — Pulsante "Vedi risultato traccia" post-gara:**
- `gps_recording_screen.dart`: per gare concluse (finished/retired) o archiviate, se il pilota ha dati GPS, pulsante full-width 56px (`AppColors.accent`, `Icons.map_outlined`, testo "VEDI RISULTATO TRACCIA") → `RaceResultScreen`; altrimenti testo centrato "Non hai partecipato a questa gara"; uniformato anche per `_buildRaceOver` (gare archiviate)

**4 — Snap su traccia per punti pericolo/ristoro:**
- `gpx_utils.dart` (nuovo): `GpxUtils.snapToTrack()` (proiezione perpendicolare sul segmento più vicino della traccia GPX), `distanceToTrack()`, `nearestTrackIndex()`, `countDangerPointsInSpecial()`
- `app_constants.dart`: nuova costante `trackSnapMaxDistanceMeters = 50.0`
- `specials_editor_screen.dart` (inserimento punto pericolo) e `event_management_screen.dart` (`_FuelPointDialogState`, inserimento punto ristoro): tap sulla mappa esegue lo snap sulla traccia GPX di riferimento; se la distanza dal punto toccato supera 50m, mostra SnackBar "Il punto deve essere vicino al percorso" e non inserisce il marker

**5 — Riepiloghi completi (marker PS inizio/fine, pericoli, ristoro):**
- `event_management_screen.dart` (`_mapWidget`): `TrackMapScreen` ora riceve anche i waypoint inizio/fine di tutte le speciali, `fuelPoint` e `dangerPoints`
- `event_detail_screen.dart`: aggiunto `fuelPoint: event.fuelPoint` alla `TrackMapScreen` esistente (già presenti waypoint PS e `dangerPoints`)

**6 — Conteggio punti pericolo per PS:**
- `GpxUtils.countDangerPointsInSpecial()`: determina se un punto pericolo cade tra l'inizio e la fine di una speciale tramite indice del punto più vicino sulla traccia
- `special_tile.dart`: nuovo campo `dangerCount`, riga "⚠ Pericoli: N" (con `DangerMarkerIcon` 16px) mostrata solo se N > 0
- `specials_editor_screen.dart` ed `event_management_screen.dart`: calcolano e passano `dangerCount` a `SpecialTile`
- `event_detail_screen.dart`: stessa riga "Pericoli: N" nelle card riepilogo PS lato pilota

**7 — Penalità "pilota mancante" default 10 minuti:**
- `penalty_settings_model.dart`: default `pilotaMancante` da 300s (5 min) a 600s (10 min); applicato solo alle nuove gare, le gare esistenti con valore 5 min non sono modificate retroattivamente

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "feat: traccia personalizzabile + marker pericolo migliorati + snap su traccia + riepiloghi completi + penalità default 10min"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

---

**20 — Riscrittura core GPS: Kalman 4D cinematico, velocità/bearing geometrici, filtro spostamento minimo, distanceFilter fisso (15 giugno 2026):**

Riscrittura completa del sistema di filtraggio GPS per risolvere il collasso in ambiente urbano (pattern a ventaglio, freccia ferma, bearing congelato) descritto in `GPS_AUDIT.md`. Nessuna patch incrementale: i componenti indicati sono stati sostituiti.

**1 — Kalman Filter 4D cinematico (`kalman_filter.dart`, riscritto):**
- Sostituito il vecchio filtro 1D indipendente su lat/lng con un filtro 4D a stato `[lat, lng, vLat, vLng]` (modello a velocità costante), che resiste meglio ai salti incoerenti con la velocità corrente
- `GpsKalmanFilter({sigmaAccel = 1.0})`, costante `kSigmaAccelMotorcycle = 3.0` (usata in `gps_service.dart`) per tollerare le accelerazioni/cambi direzione tipici dell'enduro
- Matrice di transizione F (moto a velocità costante con `dt`), rumore di processo Q derivato da `sigmaAccel` convertito in gradi/s², matrice di osservazione H = [[1,0,0,0],[0,1,0,0]], rumore di misura R = diag(r,r) con `r = (accuracy/111111)²`
- Reset automatico se il gap tra punti supera 10s, reset manuale via `reset()`

**2 — Velocità e bearing geometrici (`gps_service.dart`):**
- **`position.speed` non viene più usato per nessuna decisione logica** (era usato per il freeze del bearing, causa dell'incoerenza segnalata nell'audit)
- Nuovo metodo `_computeGeometricSpeedKmh()`: velocità calcolata via haversine tra gli ultimi due punti Kalman-filtrati
- `geometricSpeedKmh` ora alimenta: freeze del bearing (sotto 3 km/h il bearing resta congelato), display VEL in UI, filtro jump, logica intervallo adattivo
- Bearing aggiornato con smoothing angolare esponenziale (`_angularInterp`, alpha = 0.4) sopra i 3 km/h, invece dello scatto secco precedente

**3 — Pipeline di filtraggio posizioni a 6 step (`_onPosition`, riscritta):**
1. Filtro accuratezza adattivo: soglia normale 15m, soglia di fallback 40m se non si accetta un punto da >4s (evita il blocco totale in caso di segnale debole prolungato)
2. Filtro jump geometrico: scarta punti con velocità implicita >200 km/h (max 4 scarti consecutivi, poi reset Kalman e accettazione come "teletrasporto")
3. Kalman 4D sul punto accettato
4. **Nuovo filtro spostamento minimo (3m)**: se lo spostamento dal precedente punto filtrato è <3m, il punto non viene aggiunto alla polyline/distanza (elimina il pattern a ventaglio da fermo), ma bearing, waypoint detection e tracking live su Firestore continuano normalmente
5. Aggiornamento stato: velocità geometrica, bearing con smoothing, buffer ultimi 5 punti filtrati, traccia di recovery (per il recovery PS, separata dalla polyline display)
6. Aggiornamento polyline display e distanza totale, solo se lo spostamento ha superato il filtro del punto 4

**4 — `distanceFilter` fisso a 2 metri per tutte le modalità:**
- Rimossa la logica che impostava `distanceFilter = 0` in modalità `nearWaypoint`/`inSpecial` (causa del pattern a ventaglio: accettava ogni rumore GPS come punto valido)
- Nuova costante `kDistanceFilterMeters = 2`, applicata sempre (Android/Apple/Web); non usato `bestForNavigation` perché in ambiente urbano amplifica il multipath
- L'intervallo temporale adattivo (250ms/500ms/1000ms in base a modalità/prossimità pericoli) resta gestito da `_startPositionStream` come prima — solo il `distanceFilter` è ora costante

**5 — UI (verifica, nessuna modifica funzionale):**
- VEL principale e overlay debug (B°/M°/V) già usavano `geometricSpeedKmh`/`bearingDeg` — nessuna modifica necessaria
- Banner "Segnale GPS debole" continua a basarsi su `isAccuracyPoor` (5 scarti consecutivi), soglia interna ora 15m/40m adattiva

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "refactor: riscrittura GPS core - Kalman 4D cinematico + geometric speed + min displacement filter + distanceFilter fix"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

---

**21 — Bugfix critico GPS: ghost points 479km/h, pattern a ventaglio, freccia che torna indietro, PS da 795 minuti (15 giugno 2026):**

**1 — Filtro jump geometrico senza eccezioni (`gps_service.dart`):**
- `kMaxSpeedFilterKmh` abbassato da 200 a 120 km/h (massimo realistico per un enduro su sentiero)
- Rimossa la regola del "4° salto accettato" (e la relativa `kMaxConsecutiveJumps`/`_jumpCount`): qualsiasi punto che implichi una velocità >120 km/h viene SEMPRE scartato, senza eccezioni — era questa regola a permettere ai ghost points multipath (es. 479 km/h) di "teletrasportare" il Kalman e generare il pattern a ventaglio

**2 — Doppia conferma waypoint (`waypoint_detector.dart`, `gps_service.dart`):**
- `WaypointDetector` convertito da classe statica a istanza con stato (`_consecutiveNearCount`, `_firstNearTs`), nuovo metodo `detectPassage()` e `reset()`
- Un waypoint è confermato solo dopo `kRequiredConsecutiveDetections = 2` rilevazioni consecutive entro il raggio; il timestamp usato per inizio/fine PS è quello della PRIMA rilevazione, non della seconda — un singolo ghost point non può più triggerare l'inizio/fine di una speciale
- `GpsService` mantiene un'istanza `_waypointDetector`, resettata in `startRecording()`/`stopRecording()`

**3 — Sanity check tempi PS (`classifica_model.dart`, `classifica_engine.dart`, `timing_screen.dart`, `classifica_screen.dart`):**
- Nuova costante `kMaxSpecialDurationMinutes = 90`: un tempo PS superiore non è plausibile (es. recovery con timestamp corrotto → 795 minuti) e viene marcato `timingError = 'rilevamento_non_valido'`
- `SpecialTempo`: nuovi campi opzionali `timingError`, `rawStartTime`, `rawEndTime`
- Il tempo invalido viene escluso dal calcolo del tempo totale e sostituito dalla penalità massima prevista (`penalties.cp3oPiuMancati`)
- UI: al posto del tempo numerico viene mostrato "⚠ Rilevamento non valido" / "⚠ non valido" in arancione (`AppColors.warning`); in `timing_screen.dart` la riga è espandibile (tap) per mostrare all'admin i timestamp grezzi `rawStartTime`/`rawEndTime`

**4 — Validazione timestamp di recovery (`gps_service.dart`, `_trySpecialStartRecovery`):**
- Un timestamp di recovery viene rifiutato se: età >60s, è nel futuro, oppure precede `_recordingStart` — evita che timestamp corrotti (da inizializzazione GPS o sessione precedente) producano PS con durate assurde

**5 — Filtro spostamento minimo e sanity check post-Kalman (`gps_service.dart`):**
- `kMinDisplacementMeters` abbassato da 3.0 a 1.5 metri
- Nuovo STEP 3b: se la velocità implicita dalla stima Kalman supera `kMaxSpeedFilterKmh * 1.2`, il filtro Kalman viene resettato e il punto raw rifiltrato da zero come nuovo anchor — protegge da uno stato interno del Kalman corrotto

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "fix: ghost points filter 120kmh + doppia conferma waypoint + sanity check PS tempi + recovery timestamp validation + min displacement 1.5m"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

**21 (continua) — Fix UI navigazione GPS: traccia rossa, marker pericolo, notifica unica (15 giugno 2026):**

**6 — Traccia evento di riferimento più visibile (`gps_recording_screen.dart`):**
- La polyline rossa del tracciato GPX di riferimento durante la navigazione passa da `strokeWidth: 3.0` a `strokeWidth: 6.0`, con bordo `borderStrokeWidth: 1.5` di colore `Colors.red.shade900` per maggiore contrasto sulla mappa

**7 — Marker punti pericolo visibili in navigazione (`gps_recording_screen.dart`, `danger_marker_icon.dart`):**
- I punti pericolo durante la navigazione GPS usavano un'icona inline (`Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 32)`) invece del widget condiviso `DangerMarkerIcon` già usato nell'editor admin e nella scheda evento
- Ora il `MarkerLayer` dei punti pericolo in navigazione usa `DangerMarkerIcon`, mantenendo il tap per mostrare il commento del punto in una SnackBar

**8 — Centramento icona triangolo di avviso (`danger_marker_icon.dart`):**
- L'icona `Icons.warning_amber_rounded` dentro `DangerMarkerIcon` era posizionata in alto a sinistra del cerchio invece che al centro; ora è racchiusa in un `Center()`

**9 — Notifica "punto pericolo superato" una sola volta per sessione (`gps_service.dart`, `gps_recording_screen.dart`, `app_constants.dart`):**
- Nuova costante `dangerPassedRadiusMeters = 15.0`
- Nuovo set permanente `_passedDangerPoints` (resettato solo in `startRecording`, NON in `stopRecording`): un punto pericolo già "superato" entro 15m non genera più banner di avviso (50m) o allerta (150m) per il resto della sessione, anche se il pilota torna indietro
- Nuovo `dangerPassedStream`: alla prima volta che un punto viene superato entro 15m, emette un messaggio mostrato come SnackBar verde (`Colors.green.shade700`, 2s) — "✓ Punto pericolo superato"

**Deploy:**
- `flutter analyze`: zero warning (161.5s)
- `git commit c936acb`: "fix: ghost points 120kmh + doppia conferma waypoint + sanity PS tempi + recovery timestamp + traccia rossa 6px + marker pericolo navigazione + centramento icona + notifica pericolo una sola volta"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

---

### Step 22 — 4 fix critici sistema GPS: anchor display, doppia soglia accuracy, recovery fine PS, watchdog freeze (15 giugno 2026) ✅

**1 — Filtro display anchor-based (fix fan/zigzag) (`gps_service.dart`):**
- Il filtro spostamento minimo (1.5m) confrontava ogni punto col PRECEDENTE: scatter da 2-3m formavano catene che disegnavano il pattern "a ventaglio"
- Sostituito con un anchor `_displayAnchor` che si sposta solo con movimento reale sostenuto, soglia adattiva alla velocità geometrica (`_anchorThresholdMeters()`: 2m sopra 60km/h, 3.5m sopra 20km/h, 6m sopra 5km/h, 10m da fermo)
- L'anchor controlla SOLO la polyline blu e la distanza totale; bearing, waypoint detection, recovery track e tracking live su Firestore usano sempre `filteredPos` direttamente
- Reset di `_displayAnchor` in `startRecording()`/`stopRecording()`

**2 — Doppia soglia accuracy: display vs detection (`gps_service.dart`):**
- Soglia unica 15m sostituita da `kMaxAccuracyDisplayMeters = 10.0` (Kalman/polyline, più restrittiva: meglio gap che scatter) e `kMaxAccuracyDetectionMeters = 25.0` (waypoint timing, più permissiva: non perdere passaggi con segnale debole)
- I punti con accuracy tra 10m e 25m vengono scartati da Kalman/display ma la detection waypoint viene comunque eseguita sulla posizione raw
- Estratto `_handleWaypointDetection()` (logica di passaggio waypoint/apertura-chiusura speciale/persistenza Firestore) per essere riutilizzabile sia dal percorso normale (punto Kalman-filtrato) sia dal percorso "solo detection" (punto raw scartato dal display)
- `isAccuracyPoor` ora `true` con 3 scarti consecutivi (abbassato da 5, coerente con soglia display più stretta)

**3 — Recovery retroattivo fine PS (`gps_service.dart`):**
- Nuovo `_trySpecialEndRecovery()`, speculare a `_trySpecialStartRecovery()`: per ogni speciale avviata e non conclusa, se la posizione corrente ha superato il waypoint END (tra 1× e 4× `kSpecialEndRecoveryRadiusMeters = 80m`) senza rilevarlo, scandisce gli ultimi `kSpecialEndRecoveryLookbackSeconds = 30s` di `_recoveryTrack` cercando il punto più vicino all'END
- Stesse validazioni del recovery START: età timestamp ≤60s, non nel futuro, non precedente a `_recordingStart`, durata PS plausibile (≤90min)
- Notifica via `recoveryStream` ("⚡ Fine {speciale} recuperata"), stesso banner azzurro 3s già usato per il recovery START
- `recordWaypointPassage()` (`firestore_service.dart`): nuovo parametro opzionale `recoveredEnd`
- `_endRecoveryAttempted` set (un tentativo per speciale), reset in `startRecording()`/`stopRecording()`

**4 — Watchdog GPS freeze + riavvio automatico (`gps_service.dart`, `gps_recording_screen.dart`):**
- Il vecchio watchdog monitorava solo i punti VALIDI accettati: con accuracy sempre > soglia l'app risultava di fatto congelata senza che scattasse nulla
- Nuovo `_lastRawPositionTs`, aggiornato ad OGNI posizione ricevuta (valida o no) PRIMA di qualsiasi filtro in `_onPosition`
- `_freezeDetectionTimer` (periodico, 3s) → `_checkFreeze()`: se non arriva nulla da `kFreezeDetectionSeconds = 8s` mostra banner "GPS BLOCCATO"; da `kFreezeRestartSeconds = 15s` chiama `_attemptGpsRestart()` (cancella e ricrea la subscription dello stream, con `_currentIntervalMs` salvato ad ogni `_startPositionStream`)
- Getter pubblici `isGpsFrozen`/`isRestartingGps`; `attemptGpsRestart()` pubblico per il riavvio manuale
- UI: banner arancione "⟳ GPS in ripristino..." durante il riavvio automatico; banner rosso "GPS BLOCCATO — Tocca per ripristinare" (tap → riavvio manuale come ultima risorsa), sparisce automaticamente al primo punto raw post-riavvio
- Timer cancellato in `stopRecording()` e `dispose()`

**Deploy:**
- `flutter analyze`: zero warning
- `git commit`: "fix: anchor display filter + dual accuracy threshold + PS end recovery + GPS freeze watchdog con restart automatico"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

### Step 23 — IMU Fusion: GPS + giroscopio + accelerometro + bussola a 50Hz + sigma accel dinamico + soglia accuracy 8m (16 giugno 2026) ✅

**Architettura generale:**
- Nuovo `ImuFusionService` (ChangeNotifier) in `lib/core/services/imu_fusion_service.dart`: fonde i sensori inerziali con i fix GPS Kalman per produrre posizione, heading e velocità a ~50Hz esclusivamente per il display
- **REGOLA DI SICUREZZA INVARIANTE**: `ImuFusionService` controlla SOLO il display (freccia, posizione marker, rotazione mappa HEADING, velocità UI). MAI usato per waypoint detection, timing PS, o recovery — quelli usano sempre e solo GPS+Kalman 4D
- Pacchetti aggiunti: `sensors_plus: ^6.0.0` (gyroscopio + accelerometro; supporta Android/iOS/Web), `flutter_compass: ^0.8.0` (bussola magnetometrica; solo Android/iOS)
- Guard `kIsWeb` in `ImuFusionService.start()`: su web la fusione IMU resta disattivata (flutter_compass non ha implementazione web), la UI cade su GPS+Kalman per il display

**STEP 0 — pubspec.yaml:**
- Aggiunti `sensors_plus: ^6.0.0` e `flutter_compass: ^0.8.0`; risolti `flutter_compass 0.8.1`, `sensors_plus 6.1.2`, `sensors_plus_platform_interface 2.0.1`

**STEP 1 — ImuFusionService (`lib/core/services/imu_fusion_service.dart`):**
- Filtro complementare per heading: 98% giroscopio integrato (event.z × dt → deltaHeadingDeg) + 2% correzione bussola per campione (converge in ~2s a 50Hz); bussola usata per sola correzione deriva, non come base temporale
- Accelerometro low-pass (alpha=0.10): filtra vibrazioni motore (>20Hz); proietta sull'asse heading per `aForward`; integra velocità con decay 0.98/campione, clamp [-5, 33.3] m/s
- Dead reckoning: sposta `_fusedPosition` nella direzione heading della distanza `speedMs × dt` via formula haversine; attivato solo se distanza > 1mm
- GPS anchor correction via `updateWithGps()`: blend 80% GPS / 20% dead-reckoning IMU per evitare salti bruschi; sincronizza velocità IMU da GPS se > 3km/h; notifica listener (=> trigger 50Hz UI)
- Bussola: prima lettura inizializza heading direttamente; successive aggiornano `_lastCompassDeg` (applicato nel callback giroscopio via filtro complementare)
- `start()` / `stop()` simmetrici; `dispose()` chiama `stop()` e cancella tutte e 3 le subscription (no memory leak)
- Campionamento: `SensorInterval.gameInterval` = 20ms ≈ 50Hz

**STEP 2 — GpsService integration (`lib/core/services/gps_service.dart`):**
- `ImuFusionService _imu` come dipendenza di costruttore; getter pubblico `imu` per accesso dalla UI
- `startRecording()`: chiama `await _imu.start()` dopo `WakelockPlus.enable()`
- `stopRecording()`: chiama `_imu.stop()` prima di `WakelockPlus.disable()`
- `_onPosition()`: dopo tutti i filtri (accuracy, jump, Kalman sanity check), prima di `notifyListeners()`, chiama `_imu.updateWithGps(position: filteredPos, speedKmh: _geometricSpeedKmh, timestamp: now)` — garantisce che l'anchor IMU riceva solo punti di qualità

**STEP 3 — Riverpod (`lib/features/pilot/providers/pilot_provider.dart`):**
- `imuFusionServiceProvider = ChangeNotifierProvider<ImuFusionService>` registrato separatamente
- `gpsServiceProvider` aggiornato: inietta `ref.watch(imuFusionServiceProvider)` come terzo argomento del costruttore

**STEP 4 — UI (`lib/features/pilot/screens/gps_recording_screen.dart`):**
- `_imuPosition: LatLng?` e `_imuHeading: double` come state fields; `addListener(_onImuUpdate)` in `initState()`, `removeListener` in `dispose()`
- `_onImuUpdate()`: aggiorna `_imuPosition`/`_imuHeading` via `setState()` a ~50Hz quando `fusedPosition != null`
- `curPos = _imuPosition ?? _displayPos ?? rawPos` (priorità IMU per fluidità display)
- `displayHeadingDeg = _imuPosition != null ? _imuHeading : gps.bearingDeg` usato per `arrowAngle` e `_mapController.rotate(-displayHeadingDeg)` in HEADING mode
- Polyline blu: invariato, usa esclusivamente `gps.localTrack` (GPS+Kalman, mai IMU)
- Velocità UI: `imu.fusedSpeedKmh > 0.5 ? imu.fusedSpeedKmh : gps.geometricSpeedKmh`
- Debug overlay (kDebugMode): `'GPS B:${gps.bearingDeg}° IMU H:${imu.fusedHeadingDeg}° M:... V:${imu.fusedSpeedKmh}km/h'`

**STEP 5 — Sigma accel dinamico (`lib/core/utils/kalman_filter.dart` + `gps_service.dart`):**
- `sigmaAccel` reso non-final in `GpsKalmanFilter`; nuove costanti `kSigmaAccelWalking = 0.5` e `kSigmaAccelMedium = 1.5` (mantiene `kSigmaAccelMotorcycle = 3.0`)
- `updateSigmaAccel(double newVal)`: aggiorna solo se variazione > 0.01, per non invalidare inutilmente la covarianza
- `GpsService._onPosition()`: dopo calcolo `_geometricSpeedKmh`, imposta `targetSigma` (walking <10km/h, medium <40km/h, motorcycle ≥40km/h) e chiama `_kalmanFilter.updateSigmaAccel(targetSigma)`

**STEP 6 — Soglia accuracy ridotta (`gps_service.dart`):**
- `kMaxAccuracyDisplayMeters` abbassato da 10.0 a 8.0m: il chip MediaTek del DOOGEE dichiara accuracy ottimistica, soglia più bassa migliora qualità input Kalman
- `isAccuracyPoor`: soglia abbassata da `>= 3` a `>= 2` scarti consecutivi (coerente con soglia display più stretta che genera scarti più frequenti)

**Verifica invarianti:**
1. ✅ `fusedPosition` usato SOLO per `_imuPosition` in UI; mai in WaypointDetector, mai per timing PS
2. ✅ `_trackPoints` / `gps.localTrack` aggiornati solo da fix GPS Kalman; nessun punto IMU
3. ✅ `updateWithGps()` chiamato solo dopo che il fix ha superato tutti i filtri in `_onPosition()`
4. ✅ `imu.start()` / `imu.stop()` simmetrici con `startRecording()` / `stopRecording()`
5. ✅ `dispose()` cancella tutte le subscription (gyro, accel, compass)

**Deploy:**
- `flutter analyze`: zero warning
- `git commit 46cbeb5`: "feat: IMU fusion GPS+giroscopio+accelerometro+bussola a 50Hz + sigma accel dinamico + soglia accuracy 8m"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

### Step 24 — Pre-test fix: gyro sign configurabile + UI throttle 25Hz + APK release workflow (16 giugno 2026) ✅

**FIX 1 — Segno giroscopio configurabile (`lib/core/services/imu_fusion_service.dart`):**
- Aggiunta costante `static const double kGyroZSign = 1.0` in cima a `ImuFusionService`
- `_onGyroscope`: `deltaHeadingDeg = kGyroZSign * event.z * dt * 180.0 / pi` (era hardcoded `-event.z`)
- Se durante il test la mappa ruota nella direzione opposta al movimento reale: cambiare a `-1.0`
- Debug overlay aggiornato: label `GY:` (heading fuso IMU) vs `GPS:` (bearing geometrico) per confronto visivo immediato

**FIX 2 — UI throttle 25Hz (`lib/core/services/imu_fusion_service.dart`):**
- Aggiunti `DateTime? _lastUiNotifyTs` e `static const int kUiUpdateIntervalMs = 40` (25Hz)
- `_onAccelerometer()`: sostituito `notifyListeners()` diretto con throttle 40ms
- Calcolo interno (gyro, accel, dead reckoning) resta a 50Hz — solo la notifica UI è limitata
- `_onGyroscope()` non chiama mai `notifyListeners()` (invariante già rispettata)
- `_reset()` pulisce anche `_lastUiNotifyTs`

**FIX 3 — APK release firmato via GitHub Actions:**
- `.github/workflows/build-apk.yml`: workflow rinominato "Build APK (Debug + Release)"; genera sia `app-debug.apk` che `app-release.apk` come artifact separati (retention 30gg)
- Step `Generate test keystore` genera `test-keystore.jks` in CI (alias=testkey, pass=testpass123, 1 anno)
- `android/app/build.gradle.kts`: aggiunto `signingConfigs { create("release") { ... } }`; `buildTypes.release` usa `signingConfig release` con `isMinifyEnabled=true` e `isShrinkResources=true`
- **NOTA**: keystore di test solo per testing su device. Prima del primo evento ufficiale: sostituire con keystore reale nei GitHub Secrets

**Deploy:**
- `flutter analyze`: zero issues (confermato su dart analyze sui file modificati + flutter analyze completo)
- `git commit 595330d`: "fix: gyro sign configurabile + UI throttle 25Hz + APK release workflow"
- `git push origin main` → Actions genera entrambi gli APK
- `firebase deploy --only hosting` per aggiornare la web app

---

### Step 25 — Bugfix critico: schermata bloccata su "In attesa del segnale GPS..." dopo START (17 giugno 2026) ✅

**Causa individuata:** durante un test reale la navigazione restava bloccata
indefinitamente dopo START. Tre cause concorrenti nel core GPS (`gps_service.dart`):
1. `startRecording()` chiamava `_safeNotify()` solo DOPO `await _imu.start()`
   (che include un'attesa fissa di 2s per la bussola) — la UI non passava
   alla schermata di navigazione finché quel delay non finiva.
2. La soglia accuracy display era fissa a `kMaxAccuracyDisplayMeters = 8.0`m:
   nei primi 30-60s dall'avvio (convergenza normale del chip GPS) l'accuracy
   è quasi sempre oltre 8m, quindi OGNI punto veniva scartato e Kalman/IMU
   restavano a `null` per tutta quella finestra.
3. Il watchdog freeze impostava `_lastRawPositionTs = DateTime.now()` già
   all'avvio, prima che arrivasse il primo fix raw: se il chip impiegava più
   di 15s per il primo fix (normale in cold start/indoor), il watchdog
   cancellava e ricreava lo stream GPS, facendo ripartire l'acquisizione da
   zero — un loop di riavvio infinito che impediva per sempre la convergenza.

**Fix 1 — Navigazione immediata (`gps_service.dart`):**
- `_safeNotify()` spostato subito dopo `_isRecording = true` (prima di
  `await _imu.start()`): la schermata di navigazione appare istantaneamente
  dopo START, indipendentemente da IMU/GPS; il resto del setup procede in
  background
- `lib/features/pilot/screens/gps_recording_screen.dart`: rimosso il testo
  bloccante "In attesa del segnale GPS..." dal centro della schermata
  pre-start; nuovo widget `_GpsAcquiringBanner` (banner non bloccante, stile
  coerente con `_WaitingBanner`), mostrato sia in pre-start (`pos == null`)
  sia in navigazione attiva (`!hasPos`) — mappa e controlli restano sempre
  visibili e utilizzabili sotto il banner

**Fix 2 — Soglia accuracy progressiva (`gps_service.dart`):**
- Nuovo `_currentDisplayAccuracyThreshold()`: soglia display a step in base
  al tempo trascorso da `_recordingStart` — `kAccuracyStartupThreshold1 = 30.0`m
  nei primi 20s, `kAccuracyStartupThreshold2 = 15.0`m fino a 45s, poi il
  valore finale `kMaxAccuracyDisplayMeters = 8.0`m
- STEP 1 di `_onPosition()` usa questa soglia invece del valore fisso

**Fix 3 — Grace period watchdog (`gps_service.dart`):**
- `_lastRawPositionTs` inizializzato a `null` in `startRecording()` (non più
  a `DateTime.now()`)
- `_checkFreeze()`: se nessun fix raw è ancora arrivato, il watchdog resta
  inattivo per `kStartupGracePeriodSeconds = 60`s dall'avvio (tempo
  necessario al chip per il cold start); solo oltre questa finestra senza
  nemmeno un fix scatta il freeze reale (banner + riavvio automatico stream)

**Deploy:**
- `flutter analyze`: zero issues
- `git commit ceaee3e`: "fix: navigazione parte subito + acquisizione GPS progressiva + watchdog delay avvio"
- `flutter build web --release` + `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

### Step 26 — Zone a velocità controllata + frecce direzionali traccia (17-18 giugno 2026) ✅

**Feature 1 — Zone a velocità controllata:**

- `SpeedZoneModel` (nuovo, in `waypoint_model.dart`): id, nome, specialeId, startLat/startLng, endLat/endLng, maxSpeedKmh; getter `lengthMeters` (haversine inizio-fine), `startLatLng`/`endLatLng`; fromMap/toMap/copyWith
- `EventModel`: nuovo campo `speedZones: List<SpeedZoneModel>` con fromFirestore/toFirestore/copyWith
- `PenaltySettingsModel`: nuovo campo `speedZonePenaltySeconds` (default 60s) con fromMap/toMap/copyWith
- `SpeedZoneViolation` (nuovo, in `classifica_model.dart`): id, userId, zoneId, avgSpeedKmh, limitKmh, timestamp — persistito su `tracking/{eventId}/speedZoneViolations`; `SpeedZoneViolationInfo` per il dettaglio in `SpecialTempo` (zoneNome, avgSpeedKmh, limitKmh)
- `FirestoreService`: `recordSpeedZoneViolation` (best-effort, nessun fallback offline — una violazione persa non altera il risultato gara, solo la penalità non si applica), `getSpeedZoneViolationsStream`/`Once`
- `firestore.rules`: nuova regola `tracking/{eventId}/speedZoneViolations` — stessa visibilità di `passages` (tutti gli autenticati), perché la classifica del pilota stesso deve includere la penalità nel tempo finale; il dettaglio (nome zona, velocità) resta nascosto al pilota solo a livello di UI

**Rilevamento lato pilota (`gps_service.dart`):**
- I punti inizio/fine zona vengono iniettati in `_waypoints` come `WaypointType.intermedio` sintetici (id `{zoneId}_start`/`{zoneId}_end`), riusando la doppia conferma di `WaypointDetector` — nessuna nuova logica di detection da zero
- `_handleWaypointDetection`: nuovi branch per ingresso/uscita zona; all'uscita calcola velocità media (`lengthMeters / elapsed * 3.6`) e, se supera `maxSpeedKmh`, persiste la violazione (silenziosa, nessun feedback al pilota durante la guida)
- `startRecording()` accetta `speedZones` come nuovo parametro opzionale

**Penalità in classifica (`classifica_engine.dart`):**
- `_computeSpeciali` filtra le violazioni per zona/PS/finestra temporale (tra inizio e fine PS, come i CP mancati) e aggiunge `speedZonePenaltySeconds` per ogni violazione al tempo della PS
- `SpecialTempo`: nuovi campi `speedZoneViolations` (dettaglio) e `speedZonePenaltySeconds`; `penaltySeconds` ora è il totale CP+zone
- `classifica_provider.dart`: nuovo `speedZoneViolationsStreamProvider`, propagato a `classificaProvider` e `championshipStandingsProvider`

**UI Admin:**
- `specials_editor_screen.dart`: nuova modalità "Zona velocità" in toolbar (icona tachimetro arancione), abilitata solo quando una speciale esistente è in editing; tap-to-place con snap sulla traccia (stesso meccanismo dei punti pericolo) per inizio/fine zona, poi bottom sheet nome + stepper limite km/h; lista sinottica per speciale (nome | km/h | lunghezza stimata), tappabile per modificare/eliminare; segmento arancione + icona tachimetro sulla mappa (`SpeedZoneLayer`, nuovo widget condiviso)
- `timing_screen.dart`: badge "🐌 Zona X: Xkm/h / Xkm/h" accanto al badge CP, solo nella vista admin (`_SpecialTimingRow` con `showAdminDetails: true`)
- `penalty_settings_screen.dart`: nuova riga "Violazione zona velocità" (stepper, default 60s)

**UI Pilota:**
- `gps_recording_screen.dart`: stesso `SpeedZoneLayer` sulla mappa di navigazione (segmento arancione + icona), nessun avviso di violazione — il pilota scopre l'eventuale superamento solo dal tempo finale in classifica

**Feature 2 — Frecce direzionali sulla traccia rossa:**

- `track_layer.dart`: nuovo `TrackDirectionArrowsLayer` — campiona la polyline ogni `kArrowSpacingMeters` (150m), calcola il bearing verso il punto successivo, posiziona un `Icons.navigation` bianco 14px ruotato (non interattivo, nessun tap/tooltip)
- `TrackLayer.build()` lo include sempre sopra la traccia base (usato da `track_map_screen.dart`)
- Aggiunto anche accanto alle polyline rosse dedicate in `gps_recording_screen.dart` (navigazione pilota) e `live_tracking_screen.dart` (live admin)

**Deploy:**
- `flutter analyze`: zero issues
- `git commit 9f4496c`: "feat: zone velocità controllata con penalità + frecce direzionali traccia rossa"
- `flutter build web --release` + `firebase deploy --only hosting,firestore:rules` ✅ (rules incluse: necessarie per la nuova collezione `speedZoneViolations`)
- `git push origin main` ✅

---

---

### Step 27 — Rimozione watchdog automatico GPS, navigazione sempre aperta, restart manuale (20 giugno 2026) ✅

**Contesto:** nonostante i fix progressivi dello Step 25, l'app risultava
ancora bloccata su "In attesa del segnale GPS..." in test reali. Su
richiesta esplicita, l'intero meccanismo di watchdog/restart automatico è
stato rimosso (non patchato ulteriormente): nessun Timer periodico, nessun
controllo di freeze, nessun riavvio automatico dello stream GPS. La
navigazione si apre sempre e subito dopo START, e solo il pilota decide se
riavviare il GPS tramite un pulsante manuale.

**1 — Rimozione completa watchdog (`gps_service.dart`):**
- Eliminati: `_freezeDetectionTimer` (Timer.periodic ogni 3s), `_checkFreeze()`,
  `_attemptGpsRestart()` automatico, `_isGpsFrozen`, `isGpsFrozen` getter,
  `kFreezeDetectionSeconds`, `kFreezeRestartSeconds`, `kStartupGracePeriodSeconds`
- `startRecording()`/`stopRecording()`/`dispose()`: rimossa ogni creazione/cancellazione del timer di freeze
- Nessun controllo periodico residuo: il servizio non prende più nessuna decisione autonoma sullo stato del GPS

**2 — Navigazione sempre aperta (verifica, nessuna modifica necessaria):**
- Confermato che `startRecording()` chiama già `_safeNotify()` immediatamente dopo `_isRecording = true`, prima di `_imu.start()` e dello stream GPS (introdotto allo Step 25)
- `build()` in `gps_recording_screen.dart`: `if (isRecording) → _buildActiveTracking()` è già il primo ramo controllato, indipendente da `pos == null`
- Banner "Acquisizione GPS in corso..." (`_GpsAcquiringBanner`) resta non bloccante: mappa e controlli sempre visibili e utilizzabili sotto

**3 — Pulsante manuale "Ripristina GPS" (`gps_service.dart` + `gps_recording_screen.dart`):**
- Nuovo getter `GpsService.isGpsStale`: true solo se `_isRecording` e sono passati ≥30s (`kGpsStaleSeconds`) dall'ultima posizione raw ricevuta (`_lastRawPositionTs`, o da `_recordingStart` se non è mai arrivato nessun fix) — usato ESCLUSIVAMENTE per decidere la visibilità del pulsante, nessuna azione automatica
- `_attemptGpsRestart()`/`attemptGpsRestart()` rinominati in `restartGps()` (pubblico), invocato solo dal tap del pilota; cancella e ricrea la subscription dello stream GPS, stesso comportamento di basso livello di prima ma trigger esclusivamente manuale
- UI: nuovo widget `_GpsRestoreBanner` (banner rosso con testo "Nessuna posizione GPS da oltre 30s" + pulsante "Ripristina GPS"), mostrato in `_buildActiveTracking` quando `gps.isGpsStale == true`; durante il riavvio (`gps.isRestartingGps`) banner arancione con spinner come prima
- Il ticker già esistente `_elapsedTimer` (1s, già usato per il cronometro gara) guida la rivalutazione di `isGpsStale` ad ogni tick — nessun nuovo timer introdotto in UI

**Deploy:**
- `flutter analyze`: zero issues (194s)
- `git commit 1dc9754`: "fix: rimozione watchdog automatico GPS + navigazione sempre aperta + restart manuale 30s"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 28 — Bugfix critico definitivo: navigazione che torna alla pre-avvio dopo il primo fix GPS (20 giugno 2026) ✅

**Sintomo:** dopo START la schermata di navigazione si apriva correttamente,
ma tornava alla schermata pre-avvio non appena arrivava il primo fix GPS
valido — un bug diverso e indipendente da quello risolto allo Step 27
(quello riguardava il *ritardo* nell'apertura della navigazione; questo
riguardava un *ritorno indietro automatico* dopo che la navigazione era già
aperta).

**Causa reale (Riverpod, non GPS):** in `lib/features/pilot/providers/pilot_provider.dart`,
`gpsServiceProvider` costruiva `GpsService` con `ref.watch(offlineQueueProvider)`
e `ref.watch(imuFusionServiceProvider)` — entrambi `ChangeNotifierProvider`.
In Riverpod, quando un provider (non un widget) fa `ref.watch` su un
`ChangeNotifierProvider`, OGNI `notifyListeners()` di quel notifier invalida
e fa RICOSTRUIRE DA ZERO il provider osservante, distruggendo la vecchia
istanza e creandone una nuova.

`ImuFusionService.updateWithGps()` (chiamato da `GpsService._onPosition()`
ad ogni fix GPS accettato) chiama `notifyListeners()` — ed è proprio questa
la prima notifica utile del servizio IMU, perché `_onAccelerometer` resta
in early-return finché `_fusedPosition` non viene inizializzato da
`updateWithGps()` stesso. Risultato: al primo fix GPS valido,
`gpsServiceProvider` veniva ricreato da capo con un **nuovo** `GpsService`
la cui `_isRecording` parte sempre `false` di default → `build()` in
`gps_recording_screen.dart` (gate `if (isRecording) ... else _buildPreStart()`)
ricadeva sulla schermata pre-avvio, anche se l'utente non aveva premuto
né FINE GARA né RITIRO. Nessuno degli step precedenti (25/26/27) toccava
questo livello: agivano tutti dentro `GpsService`, mai sul cablaggio dei
provider Riverpod che lo istanzia.

**Fix (`pilot_provider.dart`):**
- `gpsServiceProvider`: `ref.watch` → `ref.read` per `firestoreServiceProvider`,
  `offlineQueueProvider`, `imuFusionServiceProvider`. `GpsService` li usa
  come dipendenze fisse iniettate una sola volta nel costruttore — non deve
  reagire né essere ricreato quando questi notificano i propri listener
  (quella reattività resta corretta per i widget che li osservano
  direttamente, es. banner offline in `pilot_home_screen.dart`).
- Nessuna modifica a `gps_service.dart`/`gps_recording_screen.dart`: il
  comportamento "navigazione sempre aperta dopo START, nessuna uscita
  automatica" era già corretto a livello di logica GPS/UI (Step 25/27); il
  bug era esclusivamente nel layer Riverpod che ricreava il servizio sotto
  i piedi della UI.

**Deploy:**
- `flutter analyze`: zero issues (215s)
- `git commit b27717b`: "fix: navigazione bloccata dopo START nessun ritorno automatico alla pre-avvio"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 29 — 6 fix/feature dal test reale: heading, aspetto traccia, lag, recovery PS, FINE GARA (21 giugno 2026) ✅

**FIX 1 — Heading modalità HEADING (`imu_fusion_service.dart`, `gps_service.dart`):**
- Verificata la logica di rotazione mappa/freccia (`gps_recording_screen.dart`): `rotate:_headingMode` + `arrowAngle=0` in HEADING e `MapController.rotate()` in gradi (non radianti) erano già corretti — nessuna doppia rotazione residua.
- **Causa reale individuata**: lo Step 28 ha smesso di far ricreare `GpsService` ad ogni notifica IMU — prima questo bug "mascherava" il problema fermando l'IMU pochi istanti dopo il primo fix GPS (via `GpsService.dispose()`); ora che l'IMU resta attivo per tutta la sessione, la deriva non corretta del filtro complementare giroscopio+bussola è risultata evidente ("freccia che punta a caso").
- `_filtGyroZ` + `kGyroLowPassAlpha=0.35`: low-pass sul giroscopio (le vibrazioni motore, mai isolate su un mezzo a motore, si integravano dirette nello heading) — stesso principio già applicato all'accelerometro.
- `kMaxCompassJumpDeg=60.0`: scarta letture bussola con salto angolare implausibile (interferenza magnetica vicino al motore/telaio).
- Nuovo parametro `gpsBearingDeg` in `ImuFusionService.updateWithGps()`: ancora lo heading al bearing geometrico GPS (`kHeadingGpsAnchorWeight=0.15`, sotto `kHeadingGpsAnchorMinSpeedKmh=3.0` non corregge) — senza questa ancora, gyro+bussola non avevano alcun limite superiore alla deriva nel corso di un'intera sessione.
- `kGyroZSign` resta a `1.0`, costante singola facilmente invertibile se il test su strada mostra rotazione invertita.

**FIX 2 — Impostazioni aspetto estese (`track_appearance_service.dart`, `track_appearance_provider.dart`, `gps_recording_screen.dart`):**
- `TrackAppearanceSettings`: nuovi campi `arrowColor`/`arrowSize`/`refTrackColor`/`refTrackWidth` + `copyWith`; persistiti in SharedPreferences con chiavi dedicate.
- BottomSheet impostazioni: nuove sezioni "Freccia pilota" (colore tra 5 predefiniti, dimensione slider 24-48px default 36) e "Traccia da seguire" (colore tra 4 predefiniti, larghezza slider 4-10px default 6); helper `_colorSwatchRow` condiviso tra le 3 sezioni colore.
- Marker posizione e polyline GPX di riferimento ora leggono `trackAppearanceProvider` invece di valori hardcoded.

**FIX 3 — Frecce direzionali traccia (`track_layer.dart`):**
- `kArrowSpacingMeters` 150m→60m; nuovo `_ArrowTriangle`/`_ArrowTrianglePainter` (CustomPainter, triangolo bianco pieno 10px, nessun bordo/ombra) al posto dell'icona `Icons.navigation` con `Shadow`.
- Import `latlong2` con `hide Path` (conflitto col `Path<T>` di latlong2 che shadowava `dart:ui.Path` usato dal CustomPainter).

**FIX 4 — Riduzione lag GPS/IMU (`imu_fusion_service.dart`, `gps_service.dart`):**
- GPS anchor blend posizione 80/20→90/10; `kComplementaryAlpha` 0.98→0.96 (bussola corregge il giroscopio più rapidamente); `kUiUpdateIntervalMs` 40ms→20ms (50Hz, il DOOGEE ha retto bene nel test).
- `_anchorThresholdMeters()`: fermo 10→6m, lento 6→4m, medio 3.5→2.5m, veloce 2→1.5m.

**FIX 5 — Recovery fine speciale da PS successiva (`gps_service.dart`, `classifica_model.dart`, `firestore_service.dart`, `classifica_engine.dart`, `timing_screen.dart`, `classifica_screen.dart`):**
- Bug reale: fine PS non rilevata → `_currentSpecialId` mai liberato → l'inizio della PS successiva veniva ignorato (condizione `_currentSpecialId == null` mai vera) → nessuna nuova `SpecialEntry`, FINE GARA bloccato per sempre.
- Nuovo `GpsService._closeOpenSpecial()`: quando si rileva l'inizio di una speciale diversa da quella ancora aperta, cerca nel buffer `_recoveryTrack` il punto più vicino al waypoint di fine della PS aperta in una finestra AMPIA (dall'`entryTime` della PS fino ad ora, non solo gli ultimi 30s come `_trySpecialEndRecovery`); se trovato entro 80m chiude con quel timestamp (`recoveredEnd:true`), altrimenti chiude con l'istante di ingresso della PS successiva e `timingError:'recovery_impreciso'`.
- `WaypointPassageRecord`/`recordWaypointPassage`: nuovo campo opzionale `timingError` persistito sul passaggio di fine.
- `ClassificaEngine`: propaga `end.timingError` in `SpecialTempo.timingError`; nuovi getter `isInvalidTiming` (solo per `'rilevamento_non_valido'`, tempo nascosto come da Step 21) e `hasTimingWarning` (tempo mostrato normalmente + badge "VERIFICA" lato admin in `timing_screen.dart`; lato pilota in `classifica_screen.dart` il tempo è semplicemente visibile, nessun allarme).

**FIX 6 — FINE GARA vicino al punto di partenza (`gps_recording_screen.dart`, `gps_service.dart`):**
- Nuova condizione di sblocco `_canFinishNearStart`: tutte le PS avviate (`_allSpecialsStarted`, non necessariamente chiuse) E il pilota entro 100m dal primo punto della traccia GPX o dal waypoint inizio PS1 (`_isNearStartPoint`).
- `GpsService.closeAllOpenSpecialsForFineGara()`: alla pressione di FINE GARA, chiude tutte le PS ancora aperte con lo stesso algoritmo del FIX 5, marcando `timingError:'chiusa_da_FINE_GARA'` per quelle senza recovery preciso — chiamato sempre (no-op se già tutte chiuse), prima di `blockFurtherWrites()`/`stopRecording()`.

**Deploy:**
- `flutter analyze`: zero issues (2 problemi intermedi corretti: conflitto `Path` latlong2/dart:ui in `track_layer.dart`, lint `use_null_aware_elements` in `firestore_service.dart`)
- `git commit fcde1d6`: "fix: heading modalità HEADING + impostazioni freccia e traccia + frecce direzionali stile + lag GPS ridotto + recovery PS da speciale successiva + FINE GARA vicino partenza"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 30 — Nero colori navigazione + statistiche pilota + squadra preferita (21 giugno 2026) ✅

**1 — Nero tra i colori delle impostazioni traccia (`gps_recording_screen.dart`):**
- `Colors.black` aggiunto come ultima opzione in `_trackColorOptions`, `_arrowColorOptions`, `_refTrackColorOptions` (BottomSheet "Aspetto traccia")
- `_colorSwatchRow`: bordo bianco sottile (1.5px) sempre visibile sul campione nero, anche da non selezionato, per renderlo distinguibile sul `cardBackground` scuro dell'app

**2 — Pagina statistiche pilota (`pilot_stats_screen.dart`, `pilot_stats_provider.dart`, `pilot_stats_model.dart`):**
- `PilotStatsModel`: gareDisputate, gareVinte, garePodio, specialiVinte, specialiPodio
- `pilotStatsProvider` (FutureProvider): stesso pattern N+1 di `championshipStandingsProvider` — itera tutti gli eventi (`getEvents()`), per ogni iscrizione approvata del pilota ricalcola `ClassificaEngine.compute()` (passages/registrations/teams/withdrawals/penalties/speedZoneViolations) e determina l'entry di squadra del pilota (`reg.squadraId ?? reg.userId`)
- Gare vinte/podio: dalla `posizione` finale dell'entry di squadra (1 = vinta, 1-3 = podio) — **le statistiche sono di squadra**: una vittoria di squadra conta per tutti i membri
- Speciali vinte/podio: per ogni `SpecialTempo` completato (escludendo `isInvalidTiming`), il rank è calcolato confrontando il tempo con quello di tutte le altre entry per la stessa speciale (pari merito = stesso rank)
- UI: card con icona per voce statistica, skeleton loading (`SkeletonBox`), placeholder "Nessuna gara disputata ancora" se `gareDisputate == 0`, banner informativo "vince la squadra non l'individuo"
- Route `/pilot/stats`; bottone "Le mie statistiche" nel tab Profilo (`pilot_home_screen.dart`, `_ProfilePage`)

**3 — Squadra preferita del pilota (`user_model.dart`, `firestore_service.dart`, `team_screen.dart`, `event_detail_screen.dart`):**
- `UserModel.preferredTeamName` (String?, nullable) con `fromFirestore`/`toFirestore`/`copyWith`
- `FirestoreService.savePreferredTeamName()`: scrittura merge su `users/{uid}` (stesso pattern di `saveUserFcmToken`)
- `team_screen.dart`: bottone "Imposta come squadra preferita" accanto al nome squadra del pilota; badge "★ Squadra preferita" se già impostata; `ref.invalidate(currentUserModelProvider)` dopo il salvataggio
- `event_detail_screen.dart` (`_RegistrationDialog`): `ref.listenManual(teamsProvider(eventId), ...)` in `initState` applica il suggerimento una sola volta (`_suggestionApplied`) non appena arrivano le squadre dell'evento — se la squadra preferita esiste già tra quelle iscritte (e non è piena) la pre-seleziona e mostra il badge "⭐ Preferita" con bordo evidenziato nella lista; se non esiste, precompila il campo "Crea nuova squadra" con il nome preferito e mostra il sotto-testo "Nome dalla tua squadra preferita"; il pilota resta libero di scegliere qualsiasi altra squadra

**Deploy:**
- `flutter analyze`: zero issues (186.7s)
- `git commit ff6d01d`: "feat: nero colori navigazione + statistiche pilota + squadra preferita con suggerimento iscrizione"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 31 — 8 fix dal test reale + intervento critico su prestazioni IMU/GPS (21 giugno 2026) ✅

**PRIORITÀ ASSOLUTA — Lag rotazione/posizione (`imu_fusion_service.dart`, `gps_service.dart`):**
- `kComplementaryAlpha` 0.96→0.85 + nuovo `_currentAlpha()` velocità-dipendente (0.50 da fermo, 0.70 lento, 0.85 medio, 0.92 veloce) usato in `_onGyroscope()` invece della costante fissa: la bussola corregge il giroscopio molto più rapidamente da fermo/in curva lenta, resta dominante il giroscopio solo ad alta velocità
- `kUiUpdateIntervalMs` 20ms→16ms (60Hz)
- GPS anchor blend posizione 90/10→95/5 (`ImuFusionService.updateWithGps`)
- `GpsService._anchorThresholdMeters()`: soglia da fermo 6m→3m
- Verificata `gps_recording_screen.dart`: la rotazione mappa in modalità HEADING era già priva di soglia/deadband — si propaga ad ogni rebuild guidato da `ImuFusionService` (ora 60Hz), nessuna modifica necessaria

**FIX CRITICO — Recovery PS potenziato (`gps_service.dart`):**
- `kSpecialStartRecoveryRadiusMeters`/`kSpecialEndRecoveryRadiusMeters` 80m→120m
- Nuovo `_tryRecoverSkippedSpecials()`: quando si rileva l'inizio di una PS, scandisce le PS precedenti (per `ordine`) senza ALCUN passaggio registrato (non solo "fine non rilevata", già gestito da `_closeOpenSpecial`) — cerca nell'INTERA traccia di recovery della sessione il punto più vicino al waypoint START, poi (da quel timestamp) il punto più vicino al waypoint FINE; se non trovati entro 120m usa fallback stimato (`inizio = start PS successiva - 2min`, `fine = start PS successiva - 1s`) con `timingError:'speciale_non_rilevata'` — mai più FINE GARA bloccato per una PS saltata per intero
- Chiamato PRIMA di aprire l'ingresso della PS successiva, così l'ordine resta sempre corretto; gestisce anche PS non adiacenti saltate contemporaneamente
- Nessuna waypoint detection né recovery nei primi 10s dall'avvio registrazione (`_onPosition`): il buffer GPS si sta ancora stabilizzando, un punto corrotto in questa fase generava falsi "IN SPECIALE" subito dopo START (bug Fix 7)

**FIX 1 — Zone velocità: slider + simbolo cartello (`specials_editor_screen.dart`, `speed_zone_marker.dart` nuovo, `speed_zone_layer.dart`):**
- Editing inline con slider INIZIO/FINE (stesso componente di inizio/fine speciale, range vincolato alla PS) al posto del tap-su-mappa; campo numerico limite km/h; preview della sezione evidenziata in arancione sulla mappa durante l'editing
- `SpeedZoneMarkerIcon` (nuovo widget condiviso): cartello stradale realistico, cerchio bianco bordo rosso 3px, numero limite nero al centro, 40px — usato in editor admin, navigazione pilota e riepilogo gara
- Linea zona su mappa: giallo/lime (`0xFFCCFF00`) opacity 0.7, strokeWidth 8, sopra la traccia rossa (flutter_map non supporta dash pattern nativo)

**FIX 2 — Riepilogo gara pilota (`race_result_screen.dart`):**
- Mappa con `interactionOptions: InteractionOptions(flags: InteractiveFlag.all)` esplicito (pan/zoom/doppio-tap)
- `SpeedZoneLayer` aggiunto alla mappa di riepilogo
- Card speciali: righe "⚠ Pericoli: N" (via `GpxUtils.countDangerPointsInSpecial`) e "🐌 Zone velocità: N" (via `speedZones.where(specialeId==s.id)`), entrambe solo se N>0

**FIX 3 — Waypoint vicino specifico (`waypoint_detector.dart`, `gps_service.dart`, `gps_recording_screen.dart`):**
- Nuovo `WaypointDetector.nearestWaypoint()` + `GpsService.nearestWaypointLabel` (es. "Inizio PS1", "Fine PS3", "Checkpoint PS2", risolti tramite le mappe inizio/fine/control-point esistenti)
- `_modeLabel()` mostra `"<label> vicino/vicina"` al posto del generico "WAYPOINT VICINO" quando disponibile

**FIX 4 — Doppia icona pericolo (`gps_recording_screen.dart`):**
- Rimosso il prefisso `⚠ ` dal testo dei banner avviso (giallo) e allerta (rosso) — resta solo l'icona del banner, non più duplicata nel testo

**FIX 5 — Banner zona velocità + simboli fissi (`gps_service.dart`, `gps_recording_screen.dart`, `speed_zone_layer.dart`):**
- Nuovo `GpsService.activeSpeedZone` (basato su `_zoneEntryTimestamps`); banner `_SpeedZoneBanner` con limite e velocità attuale colorata verde/rosso, visibile per tutta la permanenza in zona
- `rotate: false` esplicito su tutti i Marker non-freccia (PS, ristoro, pericolo, waypoint, zone velocità) — comportamento di default già corretto, reso esplicito

**FIX 6 — Squadra preferita più prominente (`team_screen.dart`):**
- Verificato: la feature (bottone + persistenza + suggerimento iscrizione, Step 30) era già implementata e funzionante — solo poco visibile nel test
- Bottone "⭐ Imposta come squadra preferita" reso full-width/`ElevatedButton` (era `OutlinedButton` compatto); badge "⭐ Squadra preferita" anch'esso più evidente; dialog di conferma prima di sovrascrivere una preferita diversa già impostata

**Deploy:**
- `flutter analyze`: zero issues
- `flutter test`: stesso esito del baseline pre-modifica (5 test pre-esistenti già falliti su `main`, nessuna nuova regressione introdotta)
- `git commit 630501f`: "fix: lag rotazione IMU + recovery PS potenziato + zone velocità slider e simbolo + waypoint label specifico + doppia icona pericolo + banner zona velocità + simboli fissi + squadra preferita + bug speciale avvio"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 32 — 9 fix dal test reale + indagine root-cause "PS0" (22 giugno 2026) ✅

**INDAGINE PRIORITARIA — PS0:**

Causa reale individuata (diversa dall'ipotesi iniziale di un bug nel
recovery GPS): in `specials_editor_screen.dart` il campo `ordine` di
`SpecialModel` è **0-based** (`copyWith(ordine: i)` sull'indice di lista),
mentre `nome` è un campo testuale indipendente scelto dall'admin.
`classifica_screen.dart` e `special_tile.dart` convertivano già
correttamente a 1-based (`ordine + 1`) per la UI, ma **tre punti in
`race_result_screen.dart`** (marker inizio/fine PS sulla mappa di
riepilogo e badge numerico nella card speciale) usavano `ordine` grezzo:
la prima speciale veniva quindi etichettata "PS0" — nessuna `SpecialEntry`
fantasma, nessun bug nel recovery. Verificati tutti i punti di creazione
di `SpecialEntry` (`_trySpecialStartRecovery`, `_tryRecoverSkippedSpecials`,
`_handleWaypointDetection`): ognuno popola sempre `specialeId`/`specialeNome`
da uno `SpecialModel` reale di `_specials`, nessun percorso genera un
id/nome arbitrario.

- **Fix display**: `ordine` → `ordine + 1` nei 3 punti di
  `race_result_screen.dart`
- **Hardening difensivo aggiunto comunque** (`gps_service.dart`): nuovo
  `_addSpecialEntry()` centralizzato con assert + controllo
  `_specials.any((s) => s.id == specialeId)` prima di ogni creazione;
  in `_handleWaypointDetection`, se un waypoint inizio è mappato a uno
  specialeId non (più) presente in `_specials` (es. speciale cancellata
  lato admin dopo il caricamento), non crea nulla e logga solo un warning
  di debug invece di usare `specialId` grezzo come fallback nome

**FIX 1 — Bussola diretta per display heading (`imu_fusion_service.dart`,
`gps_recording_screen.dart`):**
- Nuovo `_displayHeadingDeg` con low-pass leggero (`kDisplayAlpha = 0.3`)
  pilotato direttamente dalla bussola grezza in `_onCompass()`, indipendente
  dal filtro complementare giroscopio+bussola — risponde in ~3 campioni
  invece dei secondi di inerzia del filtro esistente
- `gps_recording_screen.dart`: `_imuHeading` ora legge
  `imu.displayHeadingDeg` (rotazione mappa/freccia); `fusedHeadingDeg`
  (filtro complementare) resta usato solo internamente per il dead
  reckoning della posizione

**FIX 2 — Densità frecce proporzionale allo zoom (`track_layer.dart`):**
- `TrackDirectionArrowsLayer` legge `MapCamera.of(context).zoom` (la
  zoom-dipendenza funziona perché il layer è un discendente di
  `FlutterMap`, si ricostruisce automaticamente ad ogni cambio camera) e
  calcola lo spacing dinamicamente: 40m (≥17), 80m (≥15), 200m (≥13),
  500m (≥11), 1500m altrimenti

**FIX 3 — Simboli mappa sempre dritti (`gps_recording_screen.dart`,
`waypoint_marker.dart`, `speed_zone_layer.dart`, `track_map_screen.dart`,
`race_result_screen.dart`):**
- **Scoperta importante**: la semantica di `Marker.rotate` in flutter_map
  è l'opposto di quanto annotato allo Step 31 — `rotate: true` = il
  marker resta sempre dritto a schermo (counter-rotate rispetto alla
  mappa), `rotate: false`/default = il marker ruota CON la mappa. Lo
  Step 31 aveva impostato `rotate: false` "esplicito" pensando fosse
  l'opzione corretta per restare dritti: era invece un no-op che lasciava
  il bug presente
- Corretto a `rotate: true` su tutti i marker non-direzionali raggiungibili
  da pinch-rotate (pericolo, zona velocità, ristoro, waypoint, PS
  inizio/fine, CP) in `gps_recording_screen.dart`, `waypoint_marker.dart`
  (`WaypointMarkersLayer`), `speed_zone_layer.dart`, `track_map_screen.dart`,
  `race_result_screen.dart`; la freccia pilota resta `rotate: _headingMode`
  (comportamento Step 22/23 invariato, è l'unico marker con orientamento
  legato all'heading)

**FIX 4 — Banner "PS completata" post-speciale (`gps_recording_screen.dart`):**
- Nuovo banner verde dedicato "PS completata: mm:ss.d" mostrato quando
  l'ultima speciale chiusa (`gps.specialEntries`, `exitTime != null`) è
  recente (≤30s) e nessuna nuova speciale è ancora iniziata; ha priorità
  sulla riga generica di passaggio waypoint esistente (che restava
  comunque corretta per i CP/ristoro, solo meno esplicita per il caso PS)

**FIX 5 — Zona velocità: raggio uscita ampliato (`app_constants.dart`,
`waypoint_detector.dart`, `gps_service.dart`):**
- Nuova costante `speedZoneRadiusMeters = 35.0` (vs 20m dei checkpoint
  normali): `WaypointDetector.detectPassage()` accetta un `radiusOverrides`
  opzionale per id waypoint, popolato da `GpsService` per inizio/fine zona
  — un mancato rilevamento dell'uscita blocca il banner live per il resto
  della sessione, un rischio peggiore di una precisione minore sul punto
  esatto (qui senza impatto su timing PS)
- Verificato il banner `_SpeedZoneBanner`: nessun testo "Zona velocità"
  duplicato trovato nell'implementazione attuale (una sola occorrenza
  "Zona {nome} — limite Xkm/h") — nessuna modifica necessaria

**FIX 6 — Segnalazione CP mancati pilota↔admin (nuovo
`cp_dispute_model.dart`, `firestore_service.dart`, `race_result_screen.dart`,
`timing_screen.dart`, `firestore.rules`, `functions/index.js`):**
- `CpDisputeModel`/`DisputedCp`: collezione `cp_disputes/{eventId}/disputes/{pilotId}_{timestamp}`
- Pilota (`race_result_screen.dart`): banner se ci sono CP mancati nelle
  proprie speciali completate, dialog con lista CP + nota opzionale,
  `createCpDispute()`; stato (pending/accepted/rejected) mostrato in
  tempo reale via `cpDisputesStreamProvider`
- Admin (`timing_screen.dart`): badge "N segnalazioni CP da verificare" +
  dialog Accetta/Rifiuta; `resolveCpDispute()` — se accolta, registra un
  passaggio sintetico per il CP (stesso schema start/end di
  `ClassificaEngine._computeSpeciali`, timestamp a metà PS) così la
  penalità sparisce dal calcolo senza logica speciale nel motore di
  classifica
- `firestore.rules`: nuova regola `cp_disputes/{eventId}/disputes/{disputeId}`
  (create autenticato, update solo admin)
- `functions/index.js`: nuovo trigger `onCpDisputeResolved` (FCM al
  pilota) — **codice pronto ma non deployato in questa sessione** (solo
  hosting deploy richiesto); serve `firebase deploy --only functions:onCpDisputeResolved,firestore:rules`
  separatamente (su WSL2 da path Linux nativo, vedi nota Step 17b)

**FIX 7 — Penalità con motivo esplicito (`classifica_screen.dart`,
`race_result_screen.dart`):**
- Sostituito il generico "+Xm PEN" con righe separate per componente:
  "⚠ +Xm: N CP mancati", "🐌 +Xm: limite zona superato", "⚡ stima
  recovery" (per `hasTimingWarning`); a livello squadra anche "👥 +Xm:
  ritiro compagno" e "👤 +Xm: pilota mancante"

**FIX 8 — Icone PS più grandi + anti-sovrapposizione (`gps_recording_screen.dart`):**
- `_psMarker`: da badge testo 9px sopra icona 18px (stack verticale,
  58×52) a pillola orizzontale icona+testo 13px (60×30) — più leggibile
  in navigazione
- Nuovo `_buildPsMarkers()`: calcola un offset verticale alternato (±16px)
  quando due punti PS sono geograficamente abbastanza vicini da
  sovrapporsi a schermo all'attuale zoom (soglia in metri derivata da
  metri/pixel Web Mercator standard, niente dipendenza da `MapCamera`
  qui perché il calcolo avviene a livello schermo, non dentro un
  discendente di `FlutterMap`)

**Deploy:**
- `flutter analyze`: zero issues (3 errori null-safety intermedi corretti
  in `race_result_screen.dart`)
- `git commit 64ade6f`: "fix: bussola diretta rotazione mappa + frecce
  zoom proporzionale + marker sempre dritti + tempo post-speciale + zona
  velocità raggio uscita + CP dispute pilota-admin + penalità motivo
  esplicito + icone PS più grandi + fix display PS0"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su
  https://ccr-enduro.web.app
- `git push origin main` ✅
- ⚠️ **Da fare separatamente**: `firebase deploy --only firestore:rules`
  (nuova regola `cp_disputes`) e `firebase deploy --only functions:onCpDisputeResolved`
  (FCM segnalazioni CP) — non eseguiti in questa sessione, solo hosting
  come richiesto

---

### Step 33 — Keystore release reale, hardening predizione IMU, throttle Firestore live tracking (23 giugno 2026) ✅

**1 — Keystore Android reale (sicurezza APK):**
- Generato un keystore PKCS12 reale e permanente (`ccr-release`, validità 10000 giorni, password random 256-bit) **fuori dal repository** (`~/ccr_keystore/`, non in `/mnt/d/ccr_app`) — non è mai esistito un commit con questo file
- `.github/workflows/build-apk.yml`: rimosso lo step che generava `test-keystore.jks` con credenziali in chiaro (`testpass123`); nuovo step "Decode release keystore" che decodifica `secrets.KEYSTORE_BASE64` in `android/app/ccr-release-key.jks`; lo step build release riceve `KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD` come env da `secrets.*`
- `android/app/build.gradle.kts`: `signingConfigs.release` legge `System.getenv("KEY_ALIAS"|"KEY_PASSWORD"|"KEYSTORE_PASSWORD")`, nessuna password hardcoded (solo l'alias ha un default non sensibile); `storeFile` punta a `ccr-release-key.jks`
- `.gitignore`: aggiunto `android/app/*.jks` e `*.keystore`
- ⚠️ **Azione manuale richiesta**: aggiungere su GitHub (Settings → Secrets and variables → Actions) i 4 secret `KEYSTORE_BASE64`/`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD` — valori in `~/ccr_keystore/credenziali_github_secrets.txt` (password) e `~/ccr_keystore/keystore_base64.txt` (base64, da copiare integralmente). **Nota PKCS12**: keytool ha imposto store password = key password (i due secret hanno lo stesso valore). Dopo aver aggiunto i secret, triggerare manualmente il workflow per verificare la build release firmata. Conservare `~/ccr_keystore/ccr-release-key.jks` in un posto sicuro (es. password manager/backup): se perso, non si potrà più aggiornare l'APK con la stessa identità di firma.

**2 — Hardening predizione posizione GPS/IMU:**
- Analisi del codice reale: un sistema di posizione predittiva GPS+IMU esiste già da 5 step dedicati (23/24/29/31/32) — `ImuFusionService._fusedPosition`, dead reckoning accelerometro+heading con GPS anchor, usato come `_imuPosition` in `gps_recording_screen.dart` per freccia/marker. Implementare una struttura "predictedPosition" parallela (come da bozza iniziale) avrebbe duplicato questa logica già esistente e tunata sul campo — scartato in favore di un hardening del meccanismo esistente
- `ImuFusionService`: nuovo `_gpsAnchorTs` (timestamp dell'ultimo anchor GPS, aggiornato in `updateWithGps`); nuove costanti `kMinPredictionSpeedKmh = 5.0` (sotto questa velocità il dead reckoning non sposta più `_fusedPosition` — a velocità così basse lo spostamento stimato è jitter dell'accelerometro, non movimento reale) e `kMaxPredictionWindowMs = 800` (oltre questo tempo dall'ultimo fix GPS, il dead reckoning si ferma invece di continuare a estrapolare senza correzione)
- `_onAccelerometer()`: il movimento di `_fusedPosition` avviene solo se entrambe le condizioni sono soddisfatte (`canPredict`); l'integrazione di velocità/heading prosegue comunque, solo lo spostamento di posizione è gated
- `_reset()`: azzera anche `_gpsAnchorTs` tra una sessione e l'altra

**3 — Audit memoria/performance IMU+GPS:**
- **Lifecycle subscription (verificato, nessuna modifica necessaria)**: `ImuFusionService.dispose()→stop()` cancella le 3 subscription (gyro/accel/compass); `GpsService.stopRecording()`/`dispose()` cancellano `_positionSub` e chiudono tutti gli `StreamController`; `startRecording()`/`stopRecording()` chiamano `_imu.start()`/`_imu.stop()` simmetricamente in tutti i path di uscita (FINE GARA, RITIRO, timeout). Nessun listener orfano.
- **Buffer circolari (analizzato, cap letterale scartato)**: `_recoveryTrack`/`_recoveryTimestamps` sono intenzionalmente full-session — `_tryRecoverSkippedSpecials` (Step 31) scandisce l'INTERA traccia per recuperare PS saltate anche a fine gara; un cap FIFO a dimensione fissa avrebbe rotto questa funzionalità già esistente. `_trackPoints` (polyline blu) alimenta distanza totale e viene salvato su Firestore/risultati gara — troncarlo avrebbe perso dati di gara reali. Stima memoria per una gara di 4.5h a 250ms: ~65k punti ≈ 5-10MB, trascurabile su device reali. Nessuna modifica.
- **Throttle Firestore live tracking (implementato)**: `GpsService._onPosition()` chiamava `updatePilotTracking()` ad ogni fix accettato (fino a 4Hz in modalità inSpecial/nearWaypoint — non 60Hz, quella è solo la cadenza locale IMU che non scrive mai su Firestore). Nuovo `_lastFirestoreUpdateTs` + `kFirestoreUpdateIntervalMs = 2000`: la scrittura del documento di tracking live è throttlata a 1 ogni 2s, indipendentemente dalla cadenza GPS che resta piena per Kalman/waypoint detection/polyline locale (mai toccati dal throttle); i passaggi waypoint/timing PS (`_handleWaypointDetection`) restano immediati, non passano da questo throttle. Reset di `_lastFirestoreUpdateTs` in `startRecording()`/`stopRecording()`.

**Deploy:**
- `flutter analyze`: zero issues (187s)
- `git commit`: "fix: keystore Android reale + hardening predizione IMU + throttle Firestore live tracking"
- `flutter build web --release` + `firebase deploy --only hosting` ✅ su https://ccr-enduro.web.app
- `git push origin main` ✅ → Actions builda debug APK regolarmente; la build release fallirà finché i 4 secret GitHub non vengono aggiunti manualmente (vedi punto 1)

---

### Step 34 — 10 interventi post-test moto: GPS background, IMU anti-shake, nomi squadra unici, mappe offline, salta PS con penalità forfettaria, GPS stale fix, mappa interattiva, ZUPT (1 luglio 2026) ✅

**1 — GPS in background (BLOCCANTE):**
- `android/app/src/main/AndroidManifest.xml`: aggiunto `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
- `MainActivity.kt`: riscritta con MethodChannel `ccr/battery` — due metodi: `isIgnoringBatteryOptimizations` e `requestIgnoreBatteryOptimization` (intent `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`)
- `lib/core/services/battery_service.dart` (nuovo): `BatteryOptimizationService` con guard `kIsWeb`/`TargetPlatform.android`
- `gps_recording_screen.dart`: `_batteryOptOk` state + check in `initState`, `_BatteryOptBanner` (arancio, cliccabile) in `_buildPreStart`

**2 — IMU anti-shake moto:**
- `imu_fusion_service.dart`: `_displayAlpha()` adattivo per velocità (0.12 fermi → 0.20 lento → 0.28 veloce), `kMaxHeadingDeltaPerSample = 8.0°/sample`, `_updateDisplayHeading()` con diff clamp

**3 — Nomi squadra unici:**
- `firestore_service.dart` `createTeam()`: fetch tutti i team dell'evento, check case-insensitive, throw `'team_name_exists'` se duplicato
- `event_detail_screen.dart` `_doRegister()`: catch dedicato con SnackBar esplicativa (5s, colore error)

**4/5 — Offline tile (grey-screen + traccia sempre visibile):**
- `gps_recording_screen.dart`: `rawPos` usa `_eventTrackPoints.first` come fallback quando nessun fix GPS — la mappa si centra sulla traccia al primo avvio anche offline; la `PolylineLayer` GPX era già separata dal `TileLayer`, traccia sempre visibile indipendentemente dalla connettività

**6 — Download mappe offline per area evento:**
- `lib/core/services/offline_tile_service.dart` (nuovo): singleton `OfflineTileService`, calcolo slippy-map tile box, download `https://tile.openstreetmap.org/`, progress callback
- `lib/core/services/offline_tile_service_io.dart` (nuovo): implementazione `dart:io` (cache in `ApplicationDocuments/osm_tiles/`)
- `lib/core/services/offline_tile_service_web.dart` (nuovo): stub no-op per web
- `lib/features/map/screens/offline_maps_screen.dart` (nuovo): lista eventi con pulsante download (zoom 10–16), barra progresso, info dimensione cache, pulsante svuota cache
- `app.dart`: rotta `/pilot/offline-maps`, import `OfflineMapsScreen`
- `pilot_home_screen.dart`: pulsante "Mappe offline" → `/pilot/offline-maps`

**7 — Salta PS con penalità forfettaria:**
- `gps_service.dart` `skipCurrentSpecial()`: trova la prossima PS non saltata, marca tutti i waypoint come passati (WaypointPassageRecord con `timingError: 'speciale_saltata'`), crea/chiude `SpecialEntry`, scrive su Firestore con retry offline
- `gps_recording_screen.dart`: bottone `SALTA SPECIALE` (OutlinedButton arancio) sotto FINE GARA/RITIRO, visibile quando ci sono speciali non completate; doppia dialog di conferma; `_confirmSkipSpecial()`
- `classifica_model.dart`: `SpecialTempo.skipped` (default false), `copyWith(tempo, penaltySeconds)`
- `classifica_engine.dart` `_computeSpeciali()`: check anticipato `end.timingError == 'speciale_saltata'` → `SpecialTempo(skipped: true, tempo: zero)`; `compute()` passo 2: raccoglie `worstBySp` (miglior tempo peggiore tra tutti i piloti per quella PS), applica forfeit = worst+30min alle speciali saltate, ricalcola `tempoTotale`

**8 — GPS stale fix (no falso allarme da fermo):**
- `gps_service.dart` `isGpsStale`: return false se `_geometricSpeedKmh < 2.0` — il pilota fermo non riceve aggiornamenti per design (distanceFilter), quindi lo stale non è un errore GPS ma comportamento atteso

**9 — Mappa pilota interattiva:**
- `event_detail_screen.dart`: rimosso `interactive: false` dalla chiamata `TrackMapScreen` (il default è `true`)

**10 — ZUPT (Zero Velocity Update) + latenza IMU:**
- `imu_fusion_service.dart`: reset `_speedMs = 0.0` quando velocità < 0.3 m/s e accel filtrata < 0.1 m/s² su entrambi gli assi — previene deriva dell'integrale da fermo

**Deploy:**
- `flutter analyze`: 0 issues
- commit: `e9b62e8` — "Step 32 — 10 interventi post-test moto: ..."
- `firebase deploy --only hosting` ✅ → https://ccr-enduro.web.app
- `git push origin main` ✅

### Step 35 — Porte virtuali timing, smoother RTS post-gara, diagnostica GNSS, alert vocali (05 agosto 2026) ✅

**Blocco 0 — chiusura gap:**
- Deploy `functions:onCpDisputeResolved` (mancava dallo Step 33): causa root della difficoltà di deploy — `functions/functions.yaml` (cache locale ignorata da git, generata da un CLI più vecchio) veniva letta al posto di rianalizzare `index.js`, nascondendo la funzione nuova al comando di deploy filtrato. Rimossa la cache e usato `FUNCTIONS_DISCOVERY_TIMEOUT=60` (il progetto è su `/mnt/d`, filesystem 9p via WSL2, il discovery a freddo supera i 10s di default) — deploy riuscito, funzione confermata in `firebase functions:list`
- Redeploy hosting di conferma incluso nel deploy finale di questo step

**Blocco A — porte virtuali con interpolazione (precisione timing):**
- `waypoint_model.dart`: nuovo `WaypointGate` (gateA/gateB/bearingDeg), campo transiente `WaypointModel.gate` (mai serializzato, ricalcolato ogni sessione)
- `location_utils.dart`: `bearingDegrees`, `destinationPoint`, `toLocalMeters` (proiezione equirettangolare locale)
- `waypoint_detector.dart`: `buildGate()` (bearing locale dai punti GPX adiacenti al waypoint, segmento perpendicolare ±25m), `attachGates()`, `detectGateCrossing()` (intersezione segmento traiettoria/porta in coordinate locali + verifica verso via prodotto scalare + interpolazione lineare del timestamp al ms)
- `gps_service.dart`: `startRecording(referenceTrack:)` costruisce le porte per inizio/fine PS e ingresso/uscita zona velocità (non per i checkpoint, che restano a raggio); `_onPosition` prova prima la porta poi ricade sul raggio esistente (mai rimosso); precedenza salvata come `timingMethod: 'gate'|'radius'|'recovery'` su ogni passaggio Firestore
- `timing_screen.dart`: badge discreto colorato (PORTA/RAGGIO/RECOVERY) su ogni tempo PS lato admin

**Blocco B — ricalcolo post-gara con smoother RTS:**
- `track_smoother.dart` (nuovo): forward Kalman 4D (stesso modello di `GpsKalmanFilter`, sigma adattivo alla velocità) + backward Rauch-Tung-Striebel; richiede traccia grezza con accuracy+timestamp per punto
- `gps_service.dart`: `_recoveryAccuracies` (accuracy raw parallela a `_recoveryTrack`), getter `fullTrackSamples`; `firestore_service.dart`: `saveFullPilotTrack`/`getFullPilotTrack` (campo separato `pilotTrackFull`, non tocca il `pilotTrack` esistente)
- `timing_screen.dart`: pulsante "Tempi ufficiali" (admin, con conferma) → smussa la traccia di ogni pilota, riesegue le porte virtuali, salva `officialTimes/{userId}` (separato dai tempi live), mostra confronto live/ufficiale con differenza in ms
- `classifica_engine.dart`/`classifica_model.dart`: `ClassificaEngine.compute(officialTimesByUserId:)` — se presente un tempo ufficiale per un membro dell'entry, sostituisce il tempo netto live (penalità CP/zona velocità restano sempre quelle live)

**Blocco C — diagnostica GNSS:**
- `MainActivity.kt`: `EventChannel('ccr/gnss_status')` con `GnssStatus.Callback` → satelliti usati/visibili, C/N0 medio, costellazioni, dual-frequency (L5/E5a via `hasCarrierFrequencyHz`)
- `gnss_status_service.dart` (nuovo): stream + qualità sintetica ECCELLENTE/BUONA/SCARSA/CRITICA; avviato/fermato da `GpsService` in startRecording/stopRecording (GnssStatus non riceve nulla senza una richiesta di posizione attiva, quindi non ha senso avviarlo prima)
- `gps_recording_screen.dart`: overlay debug "SAT: N/M" + qualità; banner qualità GNSS in schermata pre-gara
- `gps_service.dart`: fattore di diffidenza ×2 sull'accuracy effettiva (Kalman + filtri) quando la qualità è CRITICA, anche se il chip dichiara accuracy bassa
- `kUseRawLocationManager = false`: provider attuale confermato **FusedLocationProviderClient** (Google Play Services) — costante pronta per test comparativo con `LocationManager` grezzo

**Blocco D — alert vocali navigazione:**
- `flutter_tts` aggiunto; `AndroidManifest.xml` con `<queries>` per `TTS_SERVICE` (richiesto Android 11+)
- `voice_alert_service.dart` (nuovo): coda a 3 priorità (ALTA interrompe MEDIA/BASSA in corso, BASSA più vecchia scartata oltre 3 in coda), soglie fisse 1000/500/100m con Set dedupe per elemento+soglia (azzerato solo in `start()`), `setAudioAttributesForNavigation()` per instradamento corretto su interfono Bluetooth, impostazioni per categoria + velocità lettura persistite in SharedPreferences
- `gps_service.dart`: hook di tutti gli annunci (pericoli, inizio/fine PS con tempo, zona velocità, checkpoint, punto ristoro) nei punti dove GpsService già calcola le distanze/rileva i passaggi
- `gps_recording_screen.dart`: sezione "Avvisi vocali" nel BottomSheet impostazioni navigazione (toggle per categoria, slider velocità 0.4–1.0 default 0.55, pulsante "Prova audio" utilizzabile anche pre-gara)

**Fix collaterale:**
- `gps_recording_screen.dart`: `dispose()` chiamava `ref.read(imuFusionServiceProvider)` — non supportato dalla versione di Riverpod in uso (`ref` già invalidato quando `State.dispose()` gira), causava "Timer is still pending"/animazioni mai fermate nei test `GpsRecordingScreen`. Fix: `ImuFusionService` catturato in un campo durante `initState`, mai più letto da `ref` dentro `dispose()`. Risolve 2 dei 5 test falliti pre-esistenti (vedi "Prossimi Step" sotto per i 3 rimanenti, indipendenti da questo step)

**Note tecniche riportate all'utente:**
- Location provider: **FusedLocationProviderClient** (default geolocator su Android, `forceLocationManager` mai impostato finora)
- Errore di timing stimato: a 60 km/h (~16.7 m/s) con GPS a 250ms i punti distano ~4.2m — il metodo a raggio (15m) può introdurre fino a ~0.9s di errore sistematico (il punto può essere ovunque nel raggio prima della linea reale); a 30 km/h (~8.3 m/s) l'errore scende a ~1.8m/campione, quindi fino a ~0.45s. La porta virtuale con interpolazione riduce l'errore alla sola risoluzione del fix GPS (interpolato linearmente tra due campioni, quindi tipicamente <50ms se il segmento attraversa pulitamente la porta)
- Il metodo a raggio resta necessario come fallback quando: il gap GPS cade esattamente sulla porta (nessun segmento la attraversa), il pilota entra nella PS lateralmente fuori dai ±25m della porta, o `referenceTrack` non è disponibile (nessun GPX caricato) — in questi casi il waypoint non ottiene mai un `gate` e la detection ricade automaticamente sul raggio esistente

**Deploy:**
- `flutter analyze`: 0 issues
- `firebase deploy --only functions:onCpDisputeResolved` ✅
- `flutter build web --release` + `firebase deploy --only hosting` ✅ → https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 36 — Fix 3 test pre-gara, setup guidato batteria, provider GPS configurabile, log diagnostico, notifica con contatore (05 agosto 2026) ✅

**Blocco 0 — fix dei 3 test pre-esistenti (`pilot_provider.dart`):**
- Causa reale: **bug nel codice**, non nel test. `myPilotStatusProvider` ritornava `const Stream.empty()` quando l'utente non è loggato (`user == null`) — uno `Stream` vuoto non emette mai un valore, quindi il `StreamProvider` restava bloccato in `AsyncLoading` per sempre. `gps_recording_screen.dart` interpreta `myStatusAsync?.isLoading == true` come "ancora in caricamento" e mostra uno spinner permanente al posto della schermata pre-gara con START — in produzione il bug si "auto-ripara" non appena `authStateProvider` risolve a un utente reale (il provider osserva anche quello e si ricostruisce), ma resta un vero difetto di robustezza per l'edge-case "nessun utente".
- Fix: `Stream.value(null)` al posto di `Stream.empty()` — risolve subito a "nessuno stato" invece di restare bloccato.
- Sistemata anche la causa concomitante nei test: `myPilotStatusProvider` dipende da `authStateProvider` (2 hop asincroni in catena), un solo `tester.pump()` risolve solo il primo hop — aggiunto un secondo `pump()` nei 3 test in `routes_test.dart`/`pilot_flow_test.dart`.
- Suite: 43/43 verdi.

**Parte 2 — Setup guidato ottimizzazione batteria:**
- `MainActivity.kt`: nuovi metodi sul canale `ccr/battery` — `getManufacturer`/`getDeviceModel` (Build.MANUFACTURER/MODEL), `isForegroundServiceActive` (via `ActivityManager.getRunningServices`, consentito per il proprio processo anche su API 26+), `openBatterySettings` (fallback `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`), `openManufacturerBatterySettings` (tenta componenti noti Xiaomi/Oppo/Realme/Vivo/Huawei/OnePlus/Samsung, fallback `ACTION_APPLICATION_DETAILS_SETTINGS` se nessuno esiste su quella ROM — ogni tentativo in try/catch, questi intent non sono standard)
- `lib/core/services/battery_setup_service.dart` (nuovo, sostituisce `battery_service.dart`): API completa + lista produttori aggressivi + testi guida specifici per produttore (percorso esatto nelle impostazioni)
- `gps_recording_screen.dart`: nuova card "Preparazione gara" (`_PrepChecklistCard`) sopra il pulsante START — righe permesso posizione/batteria/segnale GPS (✅/⚠, tappabili) + riga "Avvisi vocali" (▶, prova audio); tap su batteria non ok mostra anche il bottom sheet con istruzioni produttore se aggressivo. START non è mai bloccato: se batteria o permesso posizione non sono ok, un dialog di conferma avvisa e lascia partire comunque su "PARTI LO STESSO"
- `lib/features/onboarding/screens/onboarding_screen.dart` (nuovo): mostrata una sola volta al primo accesso di un pilota (flag `onboarding_completed_v1` in SharedPreferences, admin esclusi), richiede posizione "sempre" e disattivazione ottimizzazione batteria in sequenza; `app.dart` redirige a `/onboarding` dopo il login se il flag non è impostato

**Parte 3 — Provider GPS grezzo configurabile (`gps_service.dart`):**
- `kUseRawLocationManager` (costante di compilazione) → `_useRawLocationManager` (campo istanza, caricato da SharedPreferences chiave `gps_use_raw_location_manager`, default `false`)
- `GpsService.setUseRawLocationManager(bool)`: persiste e, se la registrazione è attiva, riavvia subito `_startPositionStream` con le nuove `AndroidSettings(forceLocationManager:)`; altrimenti si applica al prossimo `startRecording()`
- BottomSheet impostazioni navigazione, nuova sezione "Avanzate": switch "Provider GPS grezzo (sperimentale)" con sottotitolo esplicativo, applica al volo
- Il valore (`fused`/`raw`) è scritto anche nel log diagnostico ad ogni avvio sessione

**Parte 4 — Log diagnostico di sessione (`lib/core/services/diagnostic_logger.dart`, nuovo):**
- CSV colonne fisse (`timestamp_ms,categoria,evento,campo1..campo12`), buffer in memoria + flush asincrono ogni 30s su file locale (`path_provider`), cap 20MB con rotazione (scarta la metà più vecchia delle righe, header sempre mantenuto) — mai sul percorso critico
- Registra: ciclo di vita app (`didChangeAppLifecycleState` in `gps_recording_screen.dart`, `paused` come proxy di "schermo spento" — nessun hook nativo dedicato), avvio/stop foreground service, riavvii manuali GPS, stato batteria e provider GPS a inizio sessione, modello/produttore device; fix GPS con esito filtro (accettato/scartato-accuracy/scartato-jump + valore), posizione Kalman, velocità, satelliti/C-N0 (campionati 1 su 4 in trasferimento, tutti in speciale); gap GPS >5s; eventi di timing (porta con frazione t e distanza, fallback a raggio con motivo, recovery con metodo, ingresso/uscita PS con `timingMethod`); heading IMU vs GPS ogni 5s; annunci vocali con priorità e testo
- `WaypointPassageResult` esteso con `fractionT`/`distanceMeters` (popolati solo da `detectGateCrossing`) per loggare la porta virtuale con precisione
- `VoiceAlertService`/`GpsService` accettano un `DiagnosticLogger?` opzionale (stesso pattern di `GnssStatusService`/`VoiceAlertService`); provider singleton `diagnosticLoggerProvider`
- `kDiagnosticLoggingEnabled = true` (costante su `DiagnosticLogger`, da portare a `false` a sistema validato)
- Pulsante "Esporta log tecnico" in `race_result_screen.dart` (AppBar) → condivide il CSV via `share_plus` (nuova dipendenza)

**Parte 5 — Notifica background con contatore (`gps_recording_screen.dart`, `MainActivity.kt`):**
- `MainActivity.kt`: canale `ccr/notification` → `updateForegroundNotification`, aggiorna testo/notifica riusando lo stesso notification ID (75415) e channel ID (`geolocator_channel_01`) del foreground service di geolocator_android (valori hardcoded nel plugin, nessuna API pubblica per farlo) — `notify()` con lo stesso ID sostituisce solo il contenuto, non tocca il ciclo di vita del service
- `gps_recording_screen.dart`: ogni 30s (riusa il timer esistente `_elapsedTimer`, nessun nuovo Timer) invia "CCR — registrazione attiva · N punti · HH:MM:SS" (N = `gps.fullTrackSamples.length`, orario = `gps.lastAcceptedFixTime`, nuovo getter)

**Fix collaterale (overflow):** la nuova card "Preparazione gara" faceva traboccare la Column di `_buildPreStart` su schermi/finestre di test più piccoli — contenuto centrale (badge modalità + pulsante START + info GPS) avvolto in `SingleChildScrollView`.

**Deploy:**
- `flutter analyze`: 0 issues
- `flutter test`: 43/43 verdi
- `flutter build web --release` + `firebase deploy --only hosting` ✅ → https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 37 — Banco di replay tracce, analizzatore log diagnostici, duplicazione evento (07 agosto 2026) ✅

**Obiettivo:** strumenti per validare la logica GPS/timing senza uscire sul campo, riusando le tracce già registrate. Nessuna modifica alla logica di gara esistente — solo estrazione/riuso.

**Parte 1 — Banco di replay (`gps_service.dart`, `waypoint_detector.dart`, `track_replay_service.dart` nuovo, `track_replay_screen.dart` nuovo):**
- Estrazione minimale e comportamentalmente neutra da `GpsService`: `_onPosition` accetta ora un `nowOverride` opzionale (`null` in diretta → `DateTime.now()` come sempre, identico comportamento live); reset di sessione estratto in `_resetSessionState()` condiviso da `startRecording()` e dal nuovo `startReplaySession()`; nuovo flag `_replayMode` che disattiva SOLO la chiamata reale a `Geolocator.getPositionStream` dentro `_startPositionStream` (mai toccata durante il replay). Nuova API pubblica `startReplaySession()`/`ingestReplaySample()`/`closeAllOpenSpecialsAt()`/`endReplaySession()` — stesso identico codice STEP 1-6 di `_onPosition` (filtro accuracy, jump, Kalman 4D, anchor, porte virtuali, fallback a raggio, recovery), nessuna duplicazione. `_activeEventId`/`_activeUserId` restano sempre null durante il replay: ogni scrittura Firestore nella pipeline era già condizionata su questi due campi (verificato uno per uno), quindi tutte no-op automaticamente senza guardie aggiuntive.
- `DiagnosticLogger`: nuova modalità `captureOnly` (in-memory, nessun file, attiva anche su web) — riusa esattamente gli hook di log già cablati in `GpsService` per il log diagnostico (Parte 4 dello Step 36) per catturare metodo/frazione/distanza di ogni attraversamento durante il replay, senza nessuna nuova strumentazione nel codice di gara.
- `WaypointDetector.rerunGateRadiusDetection()` (nuovo, pubblico): estratto da `timing_screen.dart` (era `_rerunDetectionOnSmoothedTrack`, privato) — riesegue solo porta/raggio su una traccia già pulita (es. smussata RTS), usato sia da "Tempi ufficiali" sia dal replay, un solo posto per la logica.
- `GpxParser.parseGpxSamples()` (nuovo): GPX con timestamp per punto (a differenza di `parseGpx`, che li scarta perché serve solo alla polyline di riferimento).
- `TrackReplayService`: 3 sorgenti (Firestore `pilotTrackFull`, CSV diagnostico via nuovo `diagnostic_log_parser.dart`, GPX), esecuzione fast/2×/5×/10×, 3 configurazioni minime (solo raggio: `referenceTrack` vuota forza fallback raggio ovunque; porta+raggio: comportamento attuale; porta+RTS: `TrackSmoother.smooth` + `rerunGateRadiusDetection`), export CSV.
- Schermata admin "Replay traccia" (menu Strumenti diagnostici in `AdminHomeScreen`): selezione sorgente/evento/pilota, velocità, mappa con traccia+porte+marker di attraversamento, tabella risultati con Δ ms, export.

**Parte 1E — Validazione su dati reali:** nessun evento pre-esistente ha `pilotTrackFull` (esiste solo dallo Step 35, mai popolato prima). Validato su "Enduro test 01" (il test in moto, 6022 punti GPS reali) con timestamp sintetici 1s costanti — geometria reale, tempistica sintetica. Risultato: **raggio da solo 0/5 PS agganciate** (a velocità reali un raggio di 10m è troppo stretto per 2 rilevazioni consecutive a 1s di cadenza), **porta+raggio 3/5 complete** (PS1/PS5 intere, mai raggiunte dal solo raggio), **porta+RTS 3/5** con differenze di poche centinaia di ms ma perdita di 2 PS recuperate parzialmente da porta+raggio. Confronto qualitativo valido, valori assoluti di durata da validare su una gara futura con `pilotTrackFull` reale.

**Parte 2 — Analizzatore log diagnostici (`diagnostic_log_analyzer_service.dart`, `diagnostic_log_parser.dart`, `diagnostic_log_analyzer_screen.dart`, tutti nuovi):**
- Parser CSV condiviso con la Parte 1 (`diagnostic_log_parser.dart`, quote-aware per i testi degli annunci vocali).
- Report: qualità segnale (durata, fix totali/accettati/scartati per motivo con %, accuracy min/mediana/max, satelliti min/mediano/max, distribuzione qualità GNSS riusando le soglie di `GnssStatusSnapshot.quality`), continuità (gap >5s con correlazione all'evento di ciclo vita app più vicino entro 5s — la verifica chiave per il GPS in background), timing (metodo/distanza/frazione per PS, recovery con motivo), configurazione device.
- Schermata admin con import CSV, report a schermo, export testo/CSV.

**Parte 3 — Duplica evento (`event_management_screen.dart`):**
- Pulsante in AppBar → dialog con selezione data (obbligatoria, non c'è altro editor data/luogo nell'app) → copia tracciato (ri-caricato su Storage sotto il nuovo eventId, non lo stesso URL — resta indipendente da regole Storage future o cancellazione dell'originale), speciali con checkpoint, punti pericolo, punto ristoro, zone velocità, dimensione squadra, tipologia punteggio, tempo massimo gara. Nome "[originale] (copia)", stato bozza. NON copia iscrizioni/ordine di partenza/tracce GPS/tempi/classifiche — automaticamente, perché tutte legate all'id del vecchio evento e il nuovo nasce con un id proprio.

**Nota metodologica sessione:** per la Parte 1E, senza credenziali admin lato client per leggere `tracking/{eventId}/pilots` (lettura riservata ad admin via Firestore rules) e senza ADC locali per `firebase-admin`, sono state deployate temporaneamente 2 Cloud Functions di sola lettura protette da secret per esportare i dati necessari, poi rimosse (codice e deploy) prima del commit — non fanno parte dell'app.

**Deploy:**
- `flutter analyze`: 0 issues
- `flutter test`: 43/43 verdi
- `flutter build web --release` + `firebase deploy --only hosting` ✅ → https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 38 — Diagnosi e correzione porte virtuali non agganciate, test di regressione su dati reali (09 agosto 2026) ✅

**Obiettivo:** capire perché 2 delle 5 PS del test in moto (6022 punti GPS reali, evento "Enduro test 01") non agganciavano completamente via porta virtuale, e correggere solo le cause reali trovate. Analisi prima, fix dopo — nessuna modifica speculativa.

**Parte 1 — Diagnosi (dati reali, non sintetici come lo Step 37):** recuperati da Firestore/Storage (via token OAuth del CLI Firebase già autenticato, nessuna Cloud Function temporanea questa volta) l'evento, la traccia pilota (`pilotTrack`, 6022 punti) e la traccia di riferimento KML (1280 punti). Rieseguito il replay con la pipeline live reale (`GpsService.startReplaySession`/`ingestReplaySample`) e un banco diagnostico ad-hoc (rimosso a fine analisi). Tabella completa delle 10 porte riportata all'utente prima di ogni correzione. Cause reali identificate:
- **PS2 FINE**: cluster di 7 fix consecutivi scartati dal filtro jump (multipath sostenuto, posizione sistematicamente 65-100m fuori corridoio) a ridosso della porta — nessun bridging può recuperare un dato mai misurato correttamente (Causa B).
- **PS3 FINE**: **non un difetto** — confermato dall'utente che la squadra ha volutamente tagliato il percorso per un problema in gara. La traiettoria reale (anche grezza, nessun gap nelle vicinanze) non passa mai a meno di ~386m dal waypoint: comportamento corretto del sistema, non va "risolto".
- **PS4 INIZIO**: nessuna intersezione geometrica pur passando a 26-28m (offset laterale 15m, entro la semi-larghezza) — bearing locale della porta calcolato da un solo punto GPX adiacente, instabile su curva (Causa A).
- **PS4 FINE — bug reale**: la porta aveva agganciato correttamente (22m, verso giusto) ma il risultato veniva scartato perché `_currentSpecialId` non valeva "PS4" in quell'istante (conseguenza a catena del fallimento di PS3 FINE) — una recovery generica ricalcolava da zero 4s dopo, trovava un punto peggiore (44m) e sovrascriveva silenziosamente il dato migliore (Causa E).
- Causa C (verso rifiutato) e D (porta non costruita) **non riscontrate**: il controllo di verso esistente è già equivalente a ±90°, e `buildGate` aveva sempre una `referenceTrack` valida per tutte le 10 porte.

**Parte 2 — Correzioni (`waypoint_detector.dart`, `gps_service.dart`, `diagnostic_logger.dart`, `waypoint_model.dart`, `track_replay_service.dart`, `timing_screen.dart`, `specials_editor_screen.dart`):**

*Fix 1 — precedenza esplicita tra metodi di timing:* nuovo ordine `gate` > `gate_gap` > `radius` > `recovery` > `forfait` (`timingMethodRank`, esteso). `GpsService._registerPassage()`: punto unico di scrittura in un nuovo registro `_bestPassageByWaypoint` — un passaggio già noto di precedenza pari o superiore non viene mai sovrascritto; la sovrascrittura evitata viene loggata (`DiagnosticLogger.logOverwriteAvoided`) con entrambi i metodi/distanze. Applicato a tutti i punti di scrittura: rilevamento diretto, recovery start/end, recovery di speciale saltata, chiusura da FINE GARA. Nuovi getter pubblici `GpsService.timingMethodFor`/`passageDistanceFor` per ispezionare il metodo vincente (usati anche dal banco di replay admin, che aveva lo stesso limite).

*Fix 2 — porta di fine disaccoppiata dallo stato della speciale:* `_handleWaypointDetection` non richiede più `_currentSpecialId == specialId` per registrare un attraversamento di porta di fine — cerca la `SpecialEntry` per id esplicito. Se la speciale non è ancora aperta, il passaggio resta comunque nel registro di precedenza (Fix 1) come "orfano": la prossima recovery che tenta di chiudere quella speciale lo trova e lo usa al posto di un ricalcolo impreciso, segnalando `timingError: 'chiusura_da_porta_orfana'` per la verifica admin.

*Fix 3 — bearing locale della porta su finestra ±30m (non più un solo punto adiacente), media vettoriale dei bearing dei segmenti; oltre 60° di variazione nella finestra la porta viene comunque costruita ma segnalata come "poco affidabile" (`logUnreliableGateBearing`) per diagnostica, SENZA disabilitarla — verificato empiricamente che disabilitarla (prima versione del fix) perdeva PS1 FINE, che aggancia correttamente nonostante l'alta curvatura locale, senza risolvere PS4 INIZIO (il bearing a finestra larga è identico entro 1° a quello a punto singolo: il mismatch lì non è di orientamento). `kGateHalfWidthMeters` di default alzato a 30m e reso configurabile per singolo waypoint (`WaypointModel.gateHalfWidthMeters`, persistito), editabile dall'admin nell'editor speciali (slider 15-80m con tooltip sul compromesso larghezza/attraversamenti spuri) per inizio/fine di ogni PS.

*Fix 4 — tracciabilità gap:* nuovo `timingMethod: 'gate_gap'` quando una porta scatta con gap >2s tra i fix che la delimitano (badge distinto "PORTA (GAP)" in giallo su `timing_screen.dart`, badge "FORFAIT" in rosso per il nuovo metodo). Cluster di jump consecutivi riassunti nel log diagnostico (`logJumpCluster`: numero, posizione media, distanza dalla traccia di riferimento) invece di righe isolate, per riconoscere il multipath sostenuto.

**Parte 3 — Verifica dopo i fix:** 7 porte su 10 con metodo gate/gate_gap (era 6/10) — invariate le 6 originali (PS1 in/fine, PS2 in, PS3 in, PS5 in/fine) più **PS4 FINE recuperata dal Fix 1/2** (gate_gap, 22.2m, timestamp preciso invece della stima grezza a 44m). PS2 FINE e PS3 FINE restano a fallback per le ragioni reali sopra (non risolvibili né da risolvere). PS4 INIZIO resta a recovery: limite noto, non risolto dal Fix 3 su questi dati.

**Parte 4 — Test di regressione (`test/features/gps/gate_replay_test.dart`, nuovo):** traccia pilota (6022 punti), traccia di riferimento (1280 punti) e le 5 speciali salvate in forma compatta in `test/fixtures/`. Il test rigioca la traccia con `TrackReplayService.runFullPipeline` (stessa pipeline di produzione, nessuna logica duplicata) e verifica: le 7 porte gate/gate_gap attese, PS3 FINE esplicitamente documentato come comportamento atteso (taglio di percorso volontario, non un difetto — commento in cima al file per non farlo scambiare per un bug in futuro), PS4 FINE non sovrascritta da una recovery meno precisa. Rete di sicurezza contro regressioni future nella pipeline GPS/timing.

**Deploy:**
- `flutter analyze`: 0 issues
- `flutter test`: 52/52 verdi (43 preesistenti + 9 nuovi)
- `flutter build web --release` + `firebase deploy --only hosting` ✅ → https://ccr-enduro.web.app
- `git push origin main` ✅

---

### Step 39 — Checkpoint su traiettoria, chunking pilotTrackFull, 7 fix dal test 100km (09 agosto 2026) ✅

**Contesto:** sessione interrotta prima del commit/deploy — recuperata e completata il 10/08/2026 (vedi Step 40) insieme alle verifiche promesse e mai riportate. Commit `ae57475`.

**Fix 1 — Checkpoint su traiettoria (`waypoint_detector.dart`, `gps_service.dart`, `waypoint_model.dart`):** i checkpoint (`SpecialModel.controlPoints`) usano ora `WaypointDetector.detectCheckpointPassage` — segmento punto-precedente→punto-corrente Kalman-filtrato, soglia 35m (era raggio puntuale 20m + doppia conferma), soglia configurabile per singolo CP (`WaypointModel.checkpointRadiusMeters`). Inizio/fine PS e zone velocità restano sul percorso porta+raggio esistente. Log diagnostico di fine sessione per ogni CP configurato (distanza minima raggiunta, agganciato o meno, metodo).

**Fix 2 — Formattazione tempo unificata (`time_format_utils.dart`, nuovo):** unica funzione condivisa per `mm:ss.cc`, usata da classifica/timing/riepilogo gara; nuova colonna "Tempo (ms)" nell'export CSV per l'elaborazione a valle.

**Fix 3 — Dicitura salto volontario vs speciale non rilevata (`classifica_model.dart`, `classifica_engine.dart`, `classifica_screen.dart`):** distingue esplicitamente in UI/classifica il caso "PS saltata dal pilota" (bottone SALTA SPECIALE) dal caso "PS non rilevata dal GPS" (recovery/forfait) — prima usavano la stessa dicitura generica.

**Fix 4 — Query dispute CP filtrata per pilota (`firestore_service.dart`):** `myCpDisputesStreamProvider`/query dedicata SOLO alle dispute del pilota corrente per l'evento (prima leggeva tutte le dispute dell'evento lato client).

**Fix 5 — Chunking `pilotTrackFull` (`firestore_service.dart`, `firebase_constants.dart`) — root cause della perdita dati del test 100km:** `saveFullPilotTrack` scriveva `samples` come un unico campo array sul documento pilota; su una gara lunga questo può superare il limite Firestore di 1 MiB, il `.set()` falliva e l'eccezione veniva ingoiata da un `catch` generico — la traccia risultava silenziosamente assente. Riscritto per spezzare `samples` in chunk da 2000 campioni nella sottocollezione `fullTrackChunks`; `getFullPilotTrack` legge prima i chunk, fallback sul vecchio campo singolo per le tracce salvate prima del fix. **Scritto ma non verificato end-to-end in questa sessione — vedi Step 40.**

**Fix 6 — `HeadingDisplayUtils` (`heading_display_utils.dart`, nuovo):** le due rotazioni (angolo freccia, rotazione mappa) estratte da `gps_recording_screen.dart` a funzioni pure testabili in isolamento. Overlay debug reso sempre visibile (prima solo `kDebugMode`).

**Fix 7 — Annuncio vocale di uscita zona velocità (`voice_alert_service.dart`, `gps_service.dart`):** mancava il simmetrico dell'annuncio di ingresso in zona a velocità controllata.

**Nuovi test:** `checkpoint_trajectory_test.dart` (confronto Fix 1 legacy/nuovo su traccia reale sintetica), `classifica_engine_forfait_test.dart`, `voice_alert_thresholds_test.dart`, `heading_display_utils_test.dart`.

**Deploy (completato il 10/08, vedi Step 40):**
- `flutter analyze`: 0 issues
- `flutter test`: 68/68 verdi
- `flutter build web --release` + `firebase deploy --only hosting,firestore` ✅
- `git push origin main` ✅

---

### Step 40 — Verifiche mancanti dallo Step 39, salvataggio traccia verificato end-to-end, audit sorgenti posizione (10 agosto 2026) ✅

**Obiettivo:** completare le 3 verifiche promesse e mai riportate dello Step 39, poi mettere alla prova il fix del limite 1 MiB (mai testato end-to-end) prima di fidarsene, poi rispondere alla domanda di fondo sulla degradazione della traccia in curva: quale sorgente di posizione alimenta cosa. Il resto della Parte 2 (modello di moto adattivo, griglia parametrica) è stato **deliberatamente sospeso**: la traccia del test 100km del 09/08 non ha timestamp reali utilizzabili (uno dei due piloti senza traccia affatto, l'altro solo con `pilotTrack` senza timestamp) — una griglia costruita su quei dati avrebbe prodotto numeri privi di significato. Resta in sospeso finché non ci sarà una traccia reale con timestamp veri da un nuovo test, ora garantiti dal fix verificato in questa sessione.

**Verifiche Step 39 (su dati reali dell'evento "Carring Clo 2 HB", 09/08/2026, tramite nuovo `tools/firestore-cli.js`):**
- **Checkpoint:** replay `TrackReplayService.runFullPipeline` sul pilota con traccia disponibile (11237 punti, timestamp sintetici 1s — l'altro pilota non ha alcuna traccia salvata, vedi sotto): **18/28 CP col vecchio metodo → 26/28 col Fix 1**, +8 recuperati. I 2 residui: uno a 490m (taglio di percorso reale), uno a 37m (appena oltre la soglia 35m).
- **pilotTrackFull:** assente per ENTRAMBI i piloti (né chunk né campo legacy) — confermato che il bug pre-Fix-5 ha effettivamente inghiottito la traccia grezza di quel test. Il ricalcolo "Tempi ufficiali" salterebbe entrambi i piloti con "nessuna traccia GPS completa salvata".
- **HeadingDisplayUtils:** le funzioni estratte sono matematicamente identiche al codice inline sostituito — nessuna doppia rotazione trovata, il codice era già corretto prima e dopo.

**1 — Salvataggio traccia a chunk verificato end-to-end (`test/core/services/firestore_track_save_test.dart`, nuovo, con `fake_cloud_firestore`):**
- Test con tracce da 13000 e 18000 punti (ordine di grandezza/estremo del test 100km): scrittura in più chunk confermata, nessun chunk sopra 1 MiB, rilettura identica (ordine + timestamp) al campione originale.
- **Bug reale trovato dal test, non del fake:** `saveFullPilotTrack` cancellava i chunk del salvataggio precedente e scriveva i nuovi nello STESSO `WriteBatch` — un secondo salvataggio genera quasi sempre chunk con lo stesso schema di id (`00000000`, `00002000`, ...), quindi `delete()` e `set()` sullo stesso riferimento documento finivano nello stesso batch. Verificato che il risultato osservabile è "documento cancellato" invece di "nuovo contenuto" — semantica d'ordine non affidabile per scritture duplicate sullo stesso doc in un unico batch. Fix: cancellazione e scrittura separate in due commit sequenziali, che elimina l'ambiguità alla radice.
- `FirestoreService` ora accetta un `FirebaseFirestore` iniettabile nel costruttore (default `FirebaseFirestore.instance`, nessun impatto sui call site di produzione) per rendere possibile questo genere di test.

**2 — Salvaguardia runtime su fallimento (`diagnostic_logger.dart`, `firestore_service.dart`, `gps_recording_screen.dart`, `race_result_screen.dart`):** i 3 punti che salvano la traccia a fine sessione (FINE GARA, RITIRO, timeout) avevano `catch (_) {}` — esattamente il pattern che ha causato la perdita silenziosa dei dati del test 100km. Ora: `DiagnosticLogger.logTrackSaveError` (locale, sempre scritto per primo, unica garanzia se anche il resto fallisce) + tentativo best-effort di scrivere un flag `trackSaveError`/`trackSaveErrorReason` su Firestore (`FirestoreService.flagTrackSaveError`, un `.set()` piccolo, difficilmente colpito dallo stesso limite) + banner rosso nel riepilogo post-gara (`race_result_screen.dart`) se il flag è presente.

**3 — Timestamp reali (chiarimento, nessun bug trovato):** `pilotTrack` (il campo semplice usato per la polyline) non ha MAI portato timestamp per punto, per design — non è un difetto, non è mai stato pensato per il replay. I timestamp reali per fix sono catturati correttamente in memoria durante la sessione (`GpsService._recoveryTimestamps`, un `DateTime.now()` per ogni fix accettato) e destinati a `pilotTrackFull`/`fullTrackChunks` — per il test del 09/08 sono andati persi insieme al resto per il bug del Fix 5, non per un problema di design nella cattura. Il test del punto 1 conferma che, col fix verificato, il round-trip dei timestamp è esatto al millisecondo.

**Parte 2A — Audit sorgenti posizione (nessuna modifica necessaria, separazione già corretta):**
- Traccia salvata su Firestore (`pilotTrack`): `GpsService._trackPoints`, popolato con `filteredPos` (Kalman) — `gps_service.dart:2371`.
- `pilotTrackFull`/chunk: `_recoveryTrack`, stesso `filteredPos` — `gps_service.dart:2146`.
- Polyline blu in navigazione: `gps.localTrack` (= `_trackPoints`) — `gps_recording_screen.dart:1586-1589`.
- Porte: `WaypointDetector.detectGateCrossing` su `filteredPos` — `gps_service.dart:2170-2177`.
- Checkpoint: `WaypointDetector.detectCheckpointPassage` su segmento `filteredPos` — `gps_service.dart:2208-2216`.
- Recovery (inizio/fine PS saltate): `_trySpecialStartRecovery`/`_trySpecialEndRecovery` su `filteredPos` — `gps_service.dart:2224-2226`.
- Distanza totale: accumulata da `_trackPoints` (`filteredPos`) — `gps_service.dart:2367-2371`.
- Freccia/rotazione mappa: `curPos = _imuPosition ?? _displayPos ?? rawPos` (IMU con dead reckoning ammesso) — `gps_recording_screen.dart:1348`. Collegamento IMU↔GPS verificato **a senso unico**: `GpsService` chiama solo `_imu.start()/stop()/updateWithGps(filteredPos, ...)` (`gps_service.dart:2406`, GPS ancora l'IMU), non legge mai nulla da `ImuFusionService` per la propria logica — commento già presente nel codice conferma l'invariante.
- **Nota minore (fuori dall'elenco richiesto):** `_canFinishNearStart`/`_isNearStartPoint` (`gps_recording_screen.dart:2538-2563`, gate del bottone FINE GARA "sei tornato vicino alla partenza") usa `curPos`, quindi può essere IMU-influenzato — non tocca dati registrati/timing, solo l'abilitazione di un bottone con soglia già ampia per tolleranza. Segnalato, non corretto: non rientra nell'elenco traccia/polyline/porte/checkpoint/recovery/distanza.

**Conclusione per la Parte 2 sospesa:** la separazione dei dati è già corretta — se la degradazione in curva osservata nel test 100km è reale, la causa è nel modello di moto rettilineo uniforme del Kalman (o nei suoi filtri di accuracy/jump), non in una contaminazione da IMU/dead reckoning. Resta da confermare con dati veri (timestamp reali) da un nuovo test.

**Deploy:**
- `flutter analyze`: 0 issues
- `flutter test`: 72/72 verdi
- `firebase deploy --only hosting` ✅
- `git push origin main` ✅

---

### Step 41 — Percorso alternativo per evento (10 agosto 2026) ✅

**Obiettivo:** un evento può avere un secondo percorso ("variante B", es. accorciato per maltempo), attivabile dall'admin al posto di quello principale ("variante A"). Refactoring del modello dati, non una semplice aggiunta — eseguito in ordine (modello → admin → attivazione → pilota → tracciabilità → duplicazione).

**Parte 1 — Modello (`route_variant_model.dart` nuovo, `event_model.dart`):**
- `RouteVariantModel`: id ('A'/'B'), label, trackUrl, speciali (con checkpoint), dangerPoints, speedZones, fuelPoint, `totalLengthKm(trackPoints)` calcolato (mai persistito, come già per tutta la traccia).
- `EventModel`: i vecchi campi diretti rinominati con suffisso `RouteA` (`speciali`→`specialiRouteA`, `dangerPoints`→`dangerPointsRouteA`, `speedZones`→`speedZonesRouteA`, `fuelPoint`→`fuelPointRouteA`, `trackUrl`→`trackUrlRouteA`, + nuovo `labelRouteA`) — rename deliberato per rompere la compilazione in ogni punto che leggeva i vecchi campi, garanzia che nessuno restasse agganciato per dimenticanza al solo percorso A. Nuovi campi: `routeB` (`RouteVariantModel?`, null finché non creata), `activeRouteId` (default `'A'`), `routeChangeLog` (`List<RouteChangeLogEntry>`: chi/quando/da-a).
- Getter `active*` (`activeSpeciali`/`activeDangerPoints`/`activeSpeedZones`/`activeFuelPoint`/`activeTrackUrl`/`activeLabel`) risolvono sempre sulla variante in `activeRouteId` — unico punto da usare fuori da editor/gestione percorsi. `routeAAsVariant`/`routeVariant(id)` per trattare A e B in modo simmetrico nella UI.
- **Retrocompatibilità totale, zero migrazione:** le chiavi Firestore della variante A restano quelle di sempre (`speciali`, `trackUrl`, ecc. — invariati); `routeB`/`activeRouteId`/`routeALabel` sono nuovi campi opzionali, assenti sui documenti esistenti e gestiti con default in `fromFirestore`.

**Parte 2 — Admin (`event_management_screen.dart`, `specials_editor_screen.dart`):**
- Tab Tracciato: pannello sempre visibile con selettore A/B **per l'editing** (`editingRouteId`, stato locale nello screen, indipendente da `activeRouteId`) + riga separata "Attivo per la gara: Percorso X — label". I due concetti non si toccano mai nello stesso controllo, per non confonderli.
- "Crea percorso alternativo" (vuoto o "Copia dal percorso A come base") quando B non esiste; una volta creata si edita con lo stesso editor di A (stessi strumenti: tracciato, speciali, checkpoint, punti pericolo, zone velocità, punto ristoro). Eliminazione B con doppia conferma, bloccata se B è la variante attiva.
- `SpecialsEditorScreen` riceve `routeId` esplicito e scrive SEMPRE su quella variante (mai su `event.activeRouteId`).

**Parte 3 — Attivazione (`event_management_screen.dart`, `firestore_service.dart`, `functions/index.js`):**
- `FirestoreService.hasAnyTrackingData(eventId)`: true se esiste anche un solo documento in `tracking/{eventId}/pilots` (il primo scritto è `raceStatus:'racing'`, prima di qualunque fix GPS — esistenza del doc = registrazione avviata). Se true, il cambio è bloccato con spiegazione ("resetta prima i dati gara" se sono tracce di test).
- Doppia conferma con riepilogo (speciali attive, lunghezza se il tracciato è già stato caricato in sessione, punti pericolo, zone velocità) prima di attivare.
- All'attivazione: `activeRouteId` aggiornato + nuova `RouteChangeLogEntry` (chi/quando/da-a, con nome admin da `currentUserModelProvider`) in un solo `updateEvent`; notifica in-app a tutti gli iscritti approvati (`notifyRouteChanged`); nuovo trigger Cloud Function `onRouteChanged` (stesso pattern di `onStartEnabled`) invia il push FCM — il client non chiama mai FCM direttamente. Log visibile in un dialog dedicato ("Storico cambi percorso") nel pannello.

**Parte 4 — Lato pilota (`event_detail_screen.dart`, `gps_recording_screen.dart`, `offline_maps_screen.dart`):**
- Banner rosso ben visibile in cima a `EventDetailScreen` se B è attiva, con label e data/ora dell'ultimo cambio.
- Mappa, marker, elenco speciali, punto ristoro: sempre `event.active*`.
- `GpsRecordingScreen`: se il percorso è cambiato nelle ultime 24h, banner d'allerta nella schermata pre-gara a ricontrollare la mappa.
- `OfflineMapsScreen._eventBbox`: unione delle waypoint di ENTRAMBE le varianti (non solo quella attiva) — il cambio può avvenire quando il pilota è già offline.

**Parte 5 — Tracciabilità (punto critico, `gps_service.dart`, `firestore_service.dart`, `classifica_engine.dart`, `classifica_provider.dart`, `timing_screen.dart`, `track_replay_screen.dart`):**
- `GpsService.startRecording` riceve `routeVariantId` obbligatorio (la variante attiva nel momento in cui il pilota preme START) e lo scrive su `tracking/{eventId}/pilots/{userId}.routeVariantId` (via `setRaceStatus`) **e** su una nuova mappa pubblica `tracking/{eventId}/routeVariantByUser/{userId}` — necessaria perché il documento pilota resta leggibile solo da admin/proprietario (privacy posizione live), ma la classifica deve risolvere la variante di OGNI pilota anche quando la guarda un altro pilota.
- `ClassificaEngine.compute(routeVariantByUserId:)`: ogni entry (team o solo) risolve la propria variante dai membri (concorde → quella; discorde → `mixedRouteVariants=true`, segnalato) e calcola tempi/checkpoint/`totaleSpeciali` SEMPRE su quella — mai su `event.activeRouteId`. Se l'admin cambia percorso dopo la gara (anche per errore), i tempi già corsi non cambiano.
- Ricalcolo "Tempi ufficiali" (`timing_screen.dart`) e banco di replay admin (`track_replay_screen.dart`): stessa regola, porte/speciali/tracciato di riferimento risolti per-pilota (cache per variante, non per ogni pilota, dato che normalmente condividono la stessa).
- `timing_screen.dart`: banner rosso se coesistono registrazioni su varianti diverse nello stesso evento (caso anomalo, classifiche non confrontabili).
- **Bug pre-esistente scoperto e corretto in `firestore.rules`:** `tracking/{eventId}/pilots/{userId}` permetteva lettura solo ad admin, bloccando anche il proprietario — `RaceResultScreen`/`myPilotStatusStream` (già esistenti) erano quindi già silenziosamente non funzionanti per i piloti prima di questo fix. Corretto in `isAdmin() || isOwner(userId)`.

**Parte 6 — Duplica evento (`event_management_screen.dart`):** copia entrambe le varianti (tracciato ricaricato su Storage sotto il nuovo eventId per ciascuna, se presente), sempre con `activeRouteId:'A'` sul nuovo evento indipendentemente da quale fosse attiva nell'originale.

**Test nuovi:** `event_model_route_variant_test.dart` (retrocompatibilità fromFirestore su documento nel vecchio formato, getter active* per A/B, fallback se B cancellata), `route_activation_guard_test.dart` (`hasAnyTrackingData` con `fake_cloud_firestore`), `classifica_engine_route_variant_test.dart` (stesso pilota calcolato su speciali diverse a seconda della variante registrata, indipendente da `event.activeRouteId`).

**Deploy:**
- `flutter analyze`: 0 issues
- `flutter test`: 83/83 verdi (72 preesistenti + 11 nuovi)
- `firebase deploy --only hosting` ✅
- `git push origin main` ✅
- `firebase deploy --only functions:onRouteChanged,firestore:rules` ✅ — eseguito e verificato end-to-end nella sessione successiva (10 agosto 2026), vedi sotto.

**Verifica end-to-end del deploy separato (10 agosto 2026, sessione successiva):**

Deploy lanciato e poi verificato con 3 controlli mirati, usando l'account pilota di test reale (`test.pilota.audit@ccr-enduro-test.com`, non admin) e un evento temporaneo isolato (creato, usato, ripulito):

1. **Lettura del proprio tracking (bug regole pre-esistente, Step 41):** autenticato come pilota via REST, letto il proprio documento `tracking/{eventId}/pilots/{uid}` → `200 OK` (prima del fix sarebbe stato `403`). Controllo negativo: lettura del tracking di un ALTRO pilota reale → `403`, la regola resta corretta (`isAdmin() || isOwner(userId)`), non è stata aperta a tutti.
2. **Notifica FCM su attivazione percorso:** aggiunti temporaneamente dei log diagnostici a `onRouteChanged`, ridispiegato, triggerato un cambio `activeRouteId` reale su un evento di test con un'iscrizione approvata e un token FCM fittizio. Log confermano l'intera pipeline: trigger rilevato → 1 iscritto approvato trovato → 1 token FCM risolto → chiamata `sendEachForMulticast` eseguita (fallita con `messaging/invalid-argument` perché il token era fittizio, non un device reale — atteso). Log diagnostici rimossi e versione pulita (`git diff` vuoto) ridispiegata subito dopo.
3. **Lettura di `routeVariantByUser` da un pilota non admin:** stesso pilota di test, lettura dell'intera collezione (propria voce + una di un altro pilota fittizio, scritta via admin) → `200 OK`, entrambe le voci visibili — conferma che la classifica lato pilota può risolvere le varianti di ogni pilota, non solo la propria.

**Incidente durante la pulizia (segnalato per trasparenza):** un comando di pulizia con `updateMask` mal formato ha azzerato per errore tutti i campi del documento utente del pilota di test (non solo il campo da rimuovere). Rilevato subito confrontando con la lettura iniziale, ripristinato (`nome`/`cognome`/`email`/`role`/`createdAt`) allo stato esatto precedente. Tutti i dati di test (evento, tracking, iscrizione) eliminati al termine — il progetto Firestore è tornato esattamente allo stato precedente (15 eventi, nessun residuo).

### Step 42 — Profilo, elenco utenti, safe area, etichette PS, dispute CP granulari (11 agosto 2026) ✅

**Obiettivo:** 6 interventi indipendenti dal profilo pilota alla gestione dispute CP, richiesti come commit unico.

**Parte 1 — Regolamento e guida nel profilo:**
- `REGOLAMENTO_CCR.md` (testo esistente, non riscritto) copiato in `assets/docs/regolamento_ccr.md`, dichiarato come asset — disponibile offline. `assets/docs/guida_app_ccr.md` nuovo, contenuto originale derivato dalle funzionalità reali dell'app.
- `lib/core/utils/markdown_sections.dart`: parser minimale per documenti "a sezioni" (H1, `## ` sezioni, paragrafi, elenchi puntati `- ` con `**grassetto**` inline) — niente dipendenza markdown esterna, controllo tipografico preciso.
- `lib/core/widgets/markdown_sections_view.dart`: rendering a sezioni espandibili (`ExpansionTile`, prima aperta di default), titoli in accent color, paragrafi distanziati, elenco puntato ben spaziato.
- `RegolamentoScreen` (`lib/features/pilot/screens/regolamento_screen.dart`) e `GuidaScreen` nuove, raggiungibili da voci nel profilo pilota (icona documento/guida) insieme a Statistiche e Mappe offline. Route `/pilot/regolamento`, `/pilot/guida`, e contestuale `/pilot/event/:id/regolamento`.
- Accesso contestuale da `EventDetailScreen` (pulsante REGOLAMENTO sotto CLASSIFICA): con `eventId`, mostra in cima una card "Dati evento" (dimensione squadra, numero e lunghezza PS calcolata dal tracciato, tempo massimo, tipologia classifica, tabella punti se a punteggio da `kChampionshipPoints`, penalità effettive via `getEffectivePenaltySettings`, numero punti pericolo e zone velocità — righe omesse se il dato non è configurato).
- `EventModel.disposizioniParticolari` (String? nuovo campo): testo libero multilinea per ritrovo/orari/pranzo/rinvio maltempo, editor in `event_management_screen.dart` (`_TracciatoTab`, stesso pattern debounce 800ms di squadra/tipologia). Lato pilota compare come sezione in cima al Regolamento contestuale, prima del regolamento generale, omessa se vuota.

**Parte 2 — Immagine profilo:**
- `image_picker`, `image`, `cached_network_image` aggiunti a `pubspec.yaml`. Permessi: `CAMERA` + `uses-feature` opzionale su Android, `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` su iOS.
- `lib/core/services/profile_image_service.dart`: pick (galleria/fotocamera) → ritaglio quadrato centrato + resize a 512px (`package:image`, puro Dart, funziona anche su web) → upload JPEG su Storage `profile_images/{uid}/{timestamp}.jpg` (nome con timestamp: l'URL cambia sempre, niente immagine vecchia mostrata dalla cache) → eliminazione esplicita del file precedente.
- `UserModel.photoUrl` (String? nuovo campo). `lib/core/widgets/ccr_avatar.dart` (avatar condiviso, cache + placeholder iniziali) e `lib/core/widgets/user_avatar_by_id.dart` (avatar per uno userId qualunque via nuovo `userByIdProvider`, per liste che conoscono solo l'id).
- Avatar mostrato in: profilo pilota (tap per cambiare, bottom sheet galleria/fotocamera/rimuovi), elenco iscrizioni admin (`registrations_screen.dart`), membri squadra (`team_screen.dart`), classifica (`ClassificaEntry.membriIds` nuovo campo, `_MemberAvatarsStack` con overlap e badge "+N").
- `storage.rules`: `profile_images/{userId}/{fileName}` scrivibile solo dal proprietario, leggibile da autenticati; il resto del bucket esplicitamente escluso da quel prefisso nella regola generica (`allPaths[0] != 'profile_images'` — le regole Storage si sommano, non vince la più specifica). `firestore.rules`: lettura di `users/{userId}` estesa a qualunque autenticato (era solo proprietario) per poter risolvere l'avatar di altri.

**Parte 3 — Elenco utenti registrati (admin):**
- `UsersListScreen` (`lib/features/admin/screens/users_list_screen.dart`), route `/admin/users`, bottone nella home admin. Ricerca nome/email, filtro stato (Tutti/Attivi/Disabilitati), ordinamento (data registrazione/nome). Per riga: avatar, nome, email, ruolo, stato, data registrazione, numero eventi (`countApprovedRegistrationsForUser`, collection group query su `iscritti` filtrata per `FieldPath.documentId` — l'id del documento È lo userId, nessun campo `userId` salvato).
- Non esisteva un flusso di approvazione account nell'app (solo approvazione per-iscrizione-evento, già in `RegistrationsScreen`): `UserModel.attivo` (bool, default true) è l'unica nozione di "stato account" introdotta, non un'approvazione a due stati. Toggle attivo/disabilitato dall'elenco; `AuthService.signIn` blocca l'accesso (sign-out immediato + eccezione) se l'account è disabilitato.

**Parte 4 — Safe area / barra di sistema:** passata su ~24 schermate (non solo le due segnalate) con contenuti/pulsanti ancorati in basso — pagina evento pilota, classifica, tempi (entrambe le viste), navigazione GPS (incluse le due `showModalBottomSheet` di batteria e aspetto traccia), risultati, squadra, statistiche, campionati, mappe offline, e diversi screen admin (home, crea evento, iscrizioni, live tracking, campionati, replay traccia, log diagnostico, ordine di partenza, penalità, gestione evento). `SafeArea(bottom: true)` dove il contenuto non è altrimenti scrollabile fino in fondo; `MediaQuery.paddingOf(context).bottom` aggiunto al padding inferiore di `ListView`/`SingleChildScrollView` altrove.

**Parte 5 — Correzioni etichette PS:**
- "SS" → "PS" (le uniche 2 occorrenze rimaste in tutto il codebase, entrambe in `classifica_screen.dart` — CSV export e annunci vocali già usavano "PS"/"prova speciale" correttamente).
- Causa radice del nome PS non visibile per le speciali a tempo forfettario in `ClassificaScreen._SpecialRow`: non un dato mancante (`specialeNome` è sempre popolato da `classifica_engine.dart`), ma un layout che schiacciava il `Text` del nome (`Expanded`) contro una colonna di note/penalità a larghezza libera nello stesso `Row` — con una nota lunga ("Tempo forfettario applicato — speciale non rilevata") il nome finiva quasi a larghezza zero. Risolto separando la riga principale (badge PS + nome sempre leggibile + tempo) dalla riga di anomalie (sotto, larghezza piena).
- Triangoli di segnalazione multipli sulla stessa riga per la stessa anomalia (icona `warning_amber_rounded` + testo con proprio "⚠" ripetuto in `classifica_screen.dart`; icona + badge "CP!" ridondante in `timing_screen.dart`): consolidati a un solo triangolo per riga, note multiple unite da " · ".

**Parte 6 — Dispute CP granulari con mappa di analisi:**
- `CpDisputeModel`/`DisputedCp` (`cp_dispute_model.dart`): ogni CP contestato ha ora stato indipendente (`pending`/`accepted`/`rejected`), nota pilota per-CP, distanza minima traccia-punto, motivazione admin. Retrocompatibilità: documenti scritti prima di questo Step (un solo `status` per l'intera dispute, nessuno stato per-voce) letti trasparentemente — il rollup legacy diventa lo stato di fallback per ogni voce priva del proprio.
- Lato pilota: `CpDisputeScreen` nuova (sostituisce il vecchio dialog "invia tutto in blocco") — checkbox per CP, nessuna selezione predefinita, distanza minima calcolata da `pilotTrack` già caricata per la mappa risultati, nota per CP + nota generale, invio disabilitato finché 0 selezionati con conteggio nel pulsante.
- Lato admin: `CpDisputeReviewScreen` nuova (sostituisce il dialog `_CpDisputesDialog`) — accetta/rifiuta indipendenti per CP con motivazione, "accetta tutti"/"rifiuta tutti" per segnalazione come scorciatoia esplicita. `CpDisputeMapScreen` nuova: traccia completa del pilota (`getFullPilotTrack`), cerchio del raggio di validità del CP (`CircleLayer`, `useRadiusInMeter`), punto di massimo avvicinamento evidenziato e collegato al CP con linea tratteggiata, traccia di riferimento evento per contesto.
- `FirestoreService.resolveCpDisputeEntries` (sostituisce `resolveCpDispute`): registra il passaggio sintetico solo per i CP che transitano a "accettato" IN QUESTA chiamata (diff con lo stato precedente) — `recordWaypointPassage` usa `.add()`, non idempotente, quindi mai due volte per lo stesso CP già accolto in precedenza. Passaggio sintetico marcato `timingMethod:'dispute'`.
- `SpecialTempo.disputeValidatedPositions` (nuovo, popolato da `classifica_engine.dart` controllando `timingMethod=='dispute'` sui passaggi CP): `TimingScreen` (admin) mostra un badge "CP DA DISPUTA" distinto dai CP rilevati automaticamente.
- `functions/index.js::onCpDisputeResolved` riscritto: confronta le singole voci `missedCps` prima/dopo invece del solo rollup a livello documento — altrimenti una decisione mista (alcuni CP accettati, altri rifiutati) non avrebbe fatto scattare alcuna notifica push, perché il rollup resta `'pending'` finché non sono TUTTI decisi nello stesso verso. Corpo del messaggio con conteggio accolti/rifiutati.
- **Limite noto:** un CP accettato e poi rifiutato in una decisione successiva NON rimuove il passaggio sintetico già registrato (nessuna logica di retract) — scenario non previsto dal flusso normale (decisione singola per segnalazione), da tenere a mente se un admin cambia idea dopo aver già accettato.

**Deploy:**
- `flutter analyze`: 0 issues (intero progetto)
- `flutter test`: 83/83 verdi (nessun nuovo test dedicato — i 6 interventi sono stati verificati con analyze + revisione manuale del flusso dati, non con test automatici aggiuntivi)
- `firebase deploy --only hosting,storage,firestore:rules,functions:onCpDisputeResolved`
- `git push origin main`

---

### Step 43 — Bug test 18/08 "Carring CLO 3": salvataggio incrementale traccia, chiusura automatica gara, varianti percorso, live admin, riepilogo post-gara, pulizia navigazione (12 agosto 2026) ✅

Analisi partita dai dati REALI dell'evento `events/W0QmaCyIHKgRnQa1YfhD`
("Carring CLO 3") via `tools/firestore-cli.js` (sola lettura, OAuth
`firebase login`), non da ipotesi. Piloti coinvolti: Claudia La Rosa
(`XCDyZQvqyXSPHsgmO4Vca93dBFm2`, Team Clo) e Michele Pierini
(`cgHlpp4KMZM2RXlBb54PKcJSIj62`, Team Test, web/Chrome).

**1 (BLOCCANTE) — `pilotTrackFull` non salvato in produzione:**
- Causa reale: il doc tracking di Michele conteneva
  `trackSaveErrorReason: "[cloud_firestore/permission-denied]..."`. Il
  ruleset **deployato** (confrontato via Firebase Rules REST API col file
  committato: identici byte-per-byte, attivo da oltre un'ora prima del
  fallimento) era già corretto — NON è un problema di regole. Causa più
  probabile: ID token Firebase Auth scaduto (TTL 1h) su una sessione
  web/Chrome lunga, il cui refresh automatico (timer JS) può essere
  ritardato dal browser su un tab in background — combinato con
  `saveFullPilotTrack` come unico tentativo one-shot a fine gara, che
  perde l'intera traccia se fallisce.
- Fix: `FirestoreService.appendFullPilotTrackChunks` — scrittura
  INCREMENTALE (append, non delete+rewrite) dei chunk
  `fullTrackChunks`, chiamata ogni ~90s da `GpsRecordingScreen` durante
  la gara (non solo a FINE GARA/RITIRO/timeout, dove
  `saveFullPilotTrack` resta il salvataggio finale autorevole).
  `FirestoreService._withTokenRefreshRetry`: intercetta
  `permission-denied`/`unauthenticated`, forza `getIdToken(true)` e
  ritenta una volta. Errore di flush mostrato al pilota con uno SnackBar
  live (prima solo `flagTrackSaveError` su Firestore + log locale, mai
  visto durante la gara).
- Test: `test/core/services/firestore_track_save_test.dart` — interruzione
  a metà gara con flush incrementali, nessun salvataggio finale, i
  campioni fino all'ultimo flush restano leggibili; verifica separata che
  `resetFullPilotTrackForNewSession` impedisca a chunk di una sessione
  precedente di mescolarsi a quelli nuovi.

**2 (BLOCCANTE) — Gara chiusa dopo pochi secondi (Claudia):**
- Causa reale: il doc tracking di Claudia aveva SOLO
  `raceStatus/finishedAt/routeVariantId` — zero fix GPS mai accettati.
  `GpsService` è un `ChangeNotifierProvider` globale MAI disposato:
  `_toggleRecording` era l'unico handler sia per START che per FINE GARA,
  discriminato solo da `gps.isRecording` (stato in memoria che
  sopravvive a una sessione precedente mai chiusa con
  STOP/FINE GARA/RITIRO). Uno stato residuo soddisfa
  `_allSpecialsCompleted`/`_canFinishNearStart` e chiude la gara
  istantaneamente al primo tocco.
- Fix strutturale: handler separati e non ambigui — `_startRace()`
  (SOLO dalla vista pre-partenza) e `_finishRace()` (SOLO dal pulsante
  FINE GARA della vista attiva). Fonte di verità Firestore: verifica
  one-shot per istanza di schermata — se `isRecording` locale è già
  `true` ma il documento `tracking/{eventId}/pilots/{userId}` non
  conferma `raceStatus=='racing'` per l'evento aperto, la sessione è
  orfana → `GpsService.discardOrphanSession()` (pulizia locale pura,
  azzera `_isRecording`/`_specialEntries`/`_passages`/buffer di
  recovery/detector, nessuna scrittura Firestore) prima di mostrare la
  vista attiva; nel frattempo un breve stato "Verifica stato gara…"
  evita qualunque frame con FINE GARA realmente premibile.
- Fix difesa aggiuntiva: `lib/core/utils/race_session_guard.dart`,
  `canAutoConcludeRace` — soglia di 3 minuti da `recordingStart` prima
  che QUALUNQUE conclusione (timeout automatico o pulsante FINE GARA,
  entrambe le vie) possa avvenire.
- Fix display "Tempo rimasto: 165:03:06": causa reale — il test è
  avvenuto PRIMA dell'orario di partenza ufficiale programmato
  (`startingOrder`, 18/08), producendo `deadline - now` enorme (non
  negativo). `_CountdownStrip` ora mostra "conteggio dalle ore HH:mm del
  gg/MM" se il test precede l'orario ufficiale, o "il conteggio partirà
  con la pubblicazione dell'ordine di partenza" se nessuno slot è
  risolvibile — mai un valore fittizio.
- Test: `test/core/utils/race_session_guard_test.dart` (soglia +
  rilevamento sessione orfana, puri); `test/features/pilot/gps_recording_orphan_session_test.dart`
  (widget: stato locale orfano + tracking non avviato su Firestore →
  mai la vista attiva, nessun "FINE GARA" raggiungibile).

**3 — Tracciato non separato tra variante A e B:**
- Causa reale confermata sui dati: `trackUrl` (A) e `routeB.trackUrl`
  puntavano allo stesso file Storage
  (`tracks/W0QmaCyIHKgRnQa1YfhD/track.kml`), solo token diversi.
  `StorageService.uploadTrack` generava sempre lo stesso path fisso
  `tracks/$eventId/track.$ext` indipendentemente dalla variante in
  editing.
- Fix: `uploadTrack(..., {String routeId = 'A'})` — path invariato per A
  (nessuna migrazione), `track_B.$ext` per B. La funzione "copia da A"
  (`_createRouteB`) era già corretta: non copia mai il file, solo
  speciali/danger/zone — l'admin carica sempre il tracciato di B
  esplicitamente. UI: messaggio "Nessun tracciato caricato per il
  percorso B" quando non impostato, invece di mostrare quello di A.

**4 — Permission-denied sulla lettura del tracking:**
- Verificato che il ruleset **deployato è identico** al file committato
  (stesso confronto del punto 1) e copre correttamente
  `tracking/{eventId}/pilots/{userId}` (owner+admin) e
  `routeVariantByUser` (autenticati). **Non è una regressione delle
  regole** — stessa causa del punto 1 (token Auth scaduto su sessione
  web lunga), applicata a una lettura invece che una scrittura; coperta
  dallo stesso retry-con-refresh-token generico in `FirestoreService`.

**5 — Schermata live admin: TypeError su cast numerico:**
- Causa reale riprodotta dal doc di Claudia (nessun `lat`/`lng`):
  `GpsPointModel.fromFirestore` faceva `(d['lat'] as num).toDouble()`
  senza null check. Fix: cast null-safe + nuovo campo `hasPosition`
  (distingue "nessun fix ancora" da un vero fix a 0,0);
  `LiveTrackingScreen._buildSafeMarkers` isola ogni pilota in un
  try/catch — un documento malformato non abbatte più l'intera lista.
  Test: `test/core/models/gps_point_model_test.dart`.

**6 — Riepilogo post-gara:**
- Traccia di riferimento assente: `_loadRefTrack` usava già la variante
  REGISTRATA sul tracking del pilota (corretto), ma ingoiava ogni
  eccezione in silenzio — ora mostra "Caricamento…"/"Traccia di
  riferimento non disponibile" invece di una mappa muta indistinguibile
  da "nessun errore".
- CP tutti verdi vs "2 CP mancati in PS2" in classifica: causa reale —
  la mappa coloriva i CP dal set grezzo `waypointPassati` (rilevatore
  live sul device), la classifica da `SpecialTempo.missedCpPositions`
  (autorevole, `ClassificaEngine`) — due fonti mai sincronizzate. Fix:
  la mappa usa `missedCpPositions` quando la speciale ha già un tempo
  calcolato, fallback al set grezzo solo se non ancora disponibile.

**7 — Pulizia schermata di navigazione:**
- Pannello debug (heading/bearing/satelliti): nascondibile da uno
  Switch nel bottom sheet impostazioni (`TrackAppearanceSettings.debugPanelVisible`,
  persistito SharedPreferences), default ON finché siamo in test.
- Indicatore di scala spostato in alto a destra; heading-toggle e
  re-center raggruppati in un'unica colonna sul bordo destro (prima
  sparsi su due angoli), centro mappa libero.
- Etichette con sfondo grigio: nessun widget dell'app le disegna
  (verificato — `_WaypointPin`/`_psMarker`/marker pericolo non usano
  grigio); provengono dai tile OpenStreetMap standard. Cambiare stile
  tile è una decisione a parte (nuovo provider/dipendenza), non inclusa
  in questo intervento.
- FINE GARA/RITIRO/SALTA SPECIALE: label avvolte in `FittedBox(fit:
  BoxFit.scaleDown)` invece di `softWrap:false`+ellipsis — un
  `textScaleFactor` di sistema più alto o uno schermo stretto restringe
  il testo invece di troncarlo (causa del troncamento osservato su
  "SALTA SPECIALE").

**8 — Taratura GPS: BLOCCATA.** Nessuna traccia con timestamp reali
disponibile per l'evento (Michele: scrittura fallita per
permission-denied, punto 1; Claudia: zero fix GPS mai accettati, punto
2). Richiede un nuovo test di campo dopo questo deploy.

**Deploy:**
- `flutter analyze`: 0 issues (intero progetto)
- `flutter test`: 94/94 verdi (incluso `test/core/utils/race_session_guard_test.dart`,
  `test/features/pilot/gps_recording_orphan_session_test.dart`,
  `test/core/models/gps_point_model_test.dart`, 2 nuovi test in
  `firestore_track_save_test.dart`)
- `firebase deploy --only hosting`
- `firebase deploy --only firestore:rules` (regole invariate — verifica
  post-deploy che il ruleset attivo resti identico al file committato)
- `git push origin main`

---

### Step 44 — Velocità display stabilizzata, squadra preferita completata, indicatore salvataggio traccia (15 agosto 2026) ✅

Tre interventi indipendenti prima del prossimo test sul campo, commit unico.

**1 — Indicatore di velocità instabile:**
- Causa: il readout "VEL" in navigazione mostrava la velocità geometrica
  istantanea tra due soli fix GPS consecutivi (`GpsService.geometricSpeedKmh`)
  — con fix ogni 250ms in speciale, pochi metri di incertezza sulla
  posizione producono un errore relativo enorme sulla velocità mostrata.
  Anche la velocità IMU (`ImuFusionService.fusedSpeedKmh`) ne era affetta:
  veniva ri-ancorata direttamente al valore istantaneo ad ogni fix GPS.
- Fix: nuovo `GpsService.displaySpeedKmh` — SOLO per il readout "VEL" e per
  il banner informativo di zona a velocità controllata (mai per la logica
  interna: filtro jump, sigmaAccel adattivo, freeze bearing e dead
  reckoning restano su `geometricSpeedKmh`, invariato). Finestra mobile di
  2.5s: corda (spostamento netto) tra il primo e l'ultimo punto della
  finestra diviso il tempo trascorso — non la somma dei segmenti
  intermedi, che da fermo continuerebbe a crescere per il solo jitter GPS
  (zig-zag) invece di restare vicina a zero. Soglia a 3 km/h sotto la
  quale il display mostra 0. Arrotondamento all'unità già presente in UI
  (invariato).
- Test: `test/core/services/gps_display_speed_test.dart` — da fermo con
  jitter di ±1.5m il display resta a 0; a velocità costante con rumore
  punto-a-punto paragonabile al passo vero, la deviazione standard del
  display è meno della metà di quella della velocità istantanea e la
  media converge entro 5 km/h dal valore reale.

**2 — Squadra preferita: verifica e completamento:**
- Verifica sullo stato reale (nessun bug trovato in quanto già
  implementato): il campo `preferredTeamName` si salva correttamente
  (`savePreferredTeamName`, merge write); il pulsante in `team_screen.dart`
  funziona; nel dialogo di iscrizione (`event_detail_screen.dart`) la
  squadra preferita viene già evidenziata/selezionata se una squadra con
  lo stesso nome esiste nell'evento, o pre-compilata nel campo "nuova
  squadra" se assente.
- Gap reale trovato: raggiungibile SOLO dalla schermata squadra di un
  evento specifico, nessun accesso dal profilo; nessuna statistica per
  squadra.
- `PilotStatsModel`: nuovi campi `preferredTeamGare*`/`preferredTeamSpeciali*`
  (stesse metriche esistenti, ristrette alle gare disputate con la
  squadra preferita) e `preferredTeamCompagni` (`TeammateStat`: compagni
  con cui si è corso più spesso in quella squadra, ordinati per numero di
  gare condivise) e `raceTeamNames` (nomi distinti delle squadre con cui
  il pilota ha già una registrazione approvata, per la scelta senza dover
  essere dentro un evento).
- `pilotStatsProvider`: calcola le metriche sopra nello stesso giro di
  eventi già esistente (nessuna query N+1 aggiuntiva).
- `PilotStatsScreen`: nuova sezione "Con «nome squadra»" con le 5
  metriche + elenco compagni (avatar + nome + gare condivise); se non
  impostata, invito con pulsante diretto "Imposta squadra preferita".
- `lib/features/pilot/widgets/preferred_team_picker.dart`
  (`showPreferredTeamPicker`): bottom sheet condiviso che elenca le
  squadre da `raceTeamNames`, scrive `savePreferredTeamName` e invalida
  `currentUserModelProvider`/`pilotStatsProvider`.
- `PilotHomeScreen` (tab Profilo): nuova card "Squadra preferita" con
  nome corrente e pulsante Imposta/Cambia — reso raggiungibile senza
  passare da un evento specifico.

**3 — Indicatore di salvataggio traccia:**
- `_SaveStatusIndicator` (`gps_recording_screen.dart`), accanto al chip
  REC nella top bar: icona con orario dell'ultimo flush incrementale
  riuscito (verde), arancione se l'ultimo tentativo è fallito ma un flush
  precedente era riuscito, rosso se falliscono da più di 5 minuti
  (accompagnato dallo SnackBar di errore già mostrato ad ogni fallimento).
  Grigio prima del primo flush (~90s dall'avvio).
- Stato tracciato in `_GpsRecordingScreenState` (`_lastFlushSuccessAt`,
  `_flushFailingSince`), aggiornato in `_flushFullTrackIncremental` e
  azzerato ad ogni nuovo `_startRace()`.
- Notifica persistente del foreground service (Android): il testo include
  ora anche lo stato salvataggio ("salvato HH:mm" / "salvataggio: ERRORE"
  / "salvataggio: in attesa") accanto al contatore punti già presente —
  verificabile dalla schermata di blocco senza aprire l'app.

**Deploy:**
- `flutter analyze`: 0 issues (intero progetto)
- `flutter test`: 96/96 verdi (94 preesistenti + 2 nuovi in
  `gps_display_speed_test.dart`)
- `firebase deploy --only hosting`
- `git push origin main`

---

## Prossimi Step

**Produzione / sicurezza:**
- Ripristinare regole Storage granulari per produzione (Firestore è già granulare dallo Step 16) — vedi `storage.rules`, TODO ancora aperto

**Test su device reale (Step 36 — mai testati su hardware):**
- Verificare `isForegroundServiceActive`/`openManufacturerBatterySettings`/aggiornamento notifica con contatore su almeno un device Xiaomi/Oppo/Samsung reale — i componenti nativi dei produttori sono percorsi non ufficiali, potrebbero non esistere su tutte le ROM
- Confrontare provider GPS `fused` vs `raw` sullo stesso device/percorso usando lo switch "Avanzate" e i log diagnostici (campo `gpsProvider` in testa a ogni sessione)
- Validare il volume del CSV diagnostico su una gara reale di 4-5 ore (dimensionato a stima, mai verificato con dati reali)

**Test su device reale (Blocco C/D dello Step 35 — mai testati su hardware):**
- Verificare che `GnssStatus.Callback` riceva effettivamente dati sui device di test (in particolare il DOOGEE con chip MediaTek) e che le soglie qualità ECCELLENTE/BUONA/SCARSA/CRITICA siano tarate bene
- Verificare l'instradamento audio degli alert vocali sull'interfono Bluetooth del casco (pulsante "Prova audio" nelle impostazioni navigazione) prima di un test su strada
- Confrontare l'errore di timing porta-vs-raggio su un tracciato reale a 30 e 60 km/h con i log `timingMethod`
- Testare il ricalcolo "Tempi ufficiali" su una gara reale con più piloti per validare lo smoother RTS

**Validazione banco di replay (Step 37 — Parte 1E, dati sintetici finora):**
- Rieseguire il confronto raggio/porta/RTS su una gara futura con `pilotTrackFull` reale (timestamp + accuracy veri, non sintetici) per validare i valori assoluti di durata, non solo il confronto qualitativo tra metodi
- Verificare se la perdita di 2 PS su 5 passando da porta+raggio a porta+RTS (vista nella validazione sintetica) si ripete su dati con cadenza di campionamento reale (250ms in speciale) invece del 1s sintetico usato

**BLOCCATO — qualità traccia in curva, griglia parametrica (Parte 2 sospesa allo Step 40):** l'app nativa produce una traccia meno aderente al percorso reale della web app, soprattutto in curva (sospetto: modello di moto rettilineo uniforme del Kalman — la separazione dati è già verificata corretta, vedi Step 40 Parte 2A). Serve un **nuovo test su strada** con il fix del salvataggio a chunk (ora verificato end-to-end) per avere `pilotTrackFull` con timestamp REALI per entrambi i dispositivi — la traccia del 09/08 non è utilizzabile (un pilota senza traccia, l'altro senza timestamp). Con quei dati, restano da fare: stima velocità angolare da bearing GPS, sigmaAccel adattivo alla curvatura, valutazione modello CTRV, dead reckoning progressivamente ridotto in curva, controllo di coerenza bussola, metriche di scostamento dalla KML + griglia parametrica nel banco di replay, esecuzione sui dati reali con raccomandazione sui default (da NON fissare senza prima riportare i numeri).

**Limiti noti dallo Step 38 (diagnosticati, non risolti — nessuna azione pianificata, solo da tenere a mente):**
- `_trySpecialStartRecovery`/`_trySpecialEndRecovery`: il tentativo "one-shot" può consumarsi troppo presto durante l'avvicinamento a un waypoint (quando la distanza è ancora calando verso il target, non ancora al minimo), fallendo il lookback e non venendo mai ritentato — osservato su PS4 INIZIO. Il Fix 1 (precedenza) ne limita il danno quando una porta successiva recupera il dato, ma il meccanismo in sé resta fragile. Una revisione (es. tentare al momento di massimo avvicinamento, non al primo ingresso in raggio) richiede test approfonditi su altre gare prima di toccare una logica già più volte tarata sul campo.
- PS4 INIZIO: bearing locale confermato corretto (finestra larga e stretta concordano entro 1°) ma la porta non intercetta comunque la traiettoria reale — probabile scarto di pochi metri tra la linea mappata (KML) e la linea effettivamente percorribile in quel punto tecnico. Non risolvibile allargando la porta (l'offset laterale, 15m, era già entro i 25m precedenti) né correggendo l'orientamento.

**Test rimanenti:**
- Test end-to-end classifica campionato con più eventi
- Test flusso iscrizione 2-step su web e Android

**Feature future:**
- Trail percorso per ogni pilota nella mappa admin live (attualmente solo posizione istantanea)
- Export PDF risultati post-gara (logo CCR, classifica finale, tempi speciali)
- Schermata "Profilo pilota" con modifica nome/cognome
- GitHub Actions CI completo (flutter test + flutter analyze)
- Suono/vibrazione al passaggio waypoint su Android
- Timeout automatico fine gara se pilota non preme FINE GARA dopo X minuti dall'ultima speciale
