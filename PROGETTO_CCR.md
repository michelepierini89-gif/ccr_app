# CCR App — Riepilogo di Progetto

**Coppa Canta Rally** — App Flutter multipiattaforma per la gestione di eventi rally  
**Data aggiornamento:** 20 giugno 2026 (Step 27 completato)  
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

## Prossimi Step

**Produzione / sicurezza:**
- Ripristinare regole Firestore/Storage granulari per produzione (da git history commit `25ad689`)

**Test su device reale:**
- Test GPS su Android con movimento reale (verificare interpolazione marker, modalità HEADING, tempo speciale)
- Test end-to-end classifica campionato con più eventi
- Test flusso iscrizione 2-step su web e Android

**Feature future:**
- Trail percorso per ogni pilota nella mappa admin live (attualmente solo posizione istantanea)
- Export PDF risultati post-gara (logo CCR, classifica finale, tempi speciali)
- Schermata "Profilo pilota" con modifica nome/cognome
- GitHub Actions CI completo (flutter test + flutter analyze)
- Suono/vibrazione al passaggio waypoint su Android
- Timeout automatico fine gara se pilota non preme FINE GARA dopo X minuti dall'ultima speciale
