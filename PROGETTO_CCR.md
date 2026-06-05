# CCR App — Riepilogo di Progetto

**Coppa Canta Rally** — App Flutter multipiattaforma per la gestione di eventi rally  
**Data aggiornamento:** 05 giugno 2026 (Step 14 completato)  
**Branch:** main  
**Versione:** 1.0.0+1

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
│   │   │   ├── screens/
│   │   │   │   ├── pilot_home_screen.dart          # 4 tab: Gare|GPS|Campionati|Profilo; PopScope
│   │   │   │   ├── event_detail_screen.dart        # skeleton, errore+retry, dialog iscrizione 2-step
│   │   │   │   ├── event_list_screen.dart          # skeleton, errore+retry, empty state CTA
│   │   │   │   ├── championship_standings_screen.dart # podio + tabella classifica campionato
│   │   │   │   ├── gps_recording_screen.dart       # START/FINE GARA, mappa live GPX+PS+ristoro, freccia bearing
│   │   │   │   └── team_screen.dart                # nomi membri da registrazioni
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

## Prossimi Step

- Ripristinare regole Firestore/Storage granulari per produzione (da git history commit `25ad689`)
- Build APK Android (GitHub Actions su `git push origin main`)
- Test GPS reale su device Android (verificare DIST e VEL con movimento reale)
- Test end-to-end classifica campionato con più eventi reali
- Test flusso iscrizione 2-step su web e Android
- Trail percorso per ogni pilota nella mappa admin live (attualmente solo posizione istantanea)
- Export PDF risultati post-gara (logo CCR, classifica finale, tempi speciali)
- Schermata "Profilo pilota" con modifica nome/cognome
- GitHub Actions CI completo (flutter test + flutter analyze)
