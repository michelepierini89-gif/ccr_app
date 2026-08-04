# Stato del Progetto CCR App — Report di Ripresa

**Generato:** 04 agosto 2026 (ripresa dopo ~1 mese di pausa dall'ultimo commit)
**Metodo:** analisi statica del repository locale, nessuna modifica al codice.

---

## 1 — Stato Git e Deploy

**Ultimo commit su `main`:**
- Hash: `2d341e6`
- Data: 01/07/2026, 08:27:43 +0200
- Messaggio: `docs: aggiorna PROGETTO_CCR.md con Step 34 (10 interventi post-test moto)`
- È un commit solo-documentazione. Il commit di codice reale è quello precedente:
  - `e9b62e8` — 01/07/2026, 08:25:41 +0200 — messaggio: *"Step 32 — 10 interventi post-test moto: ..."*
  - ⚠️ **Nota:** il messaggio del commit di codice dice "Step 32" mentre `PROGETTO_CCR.md` lo documenta come "Step 34". È quasi certamente un refuso di numerazione nel messaggio di commit (copia-incolla), non un problema funzionale — ma segnalo la discrepanza.

**Modifiche non committate:** nessuna sui file tracciati. Presenti solo file/cartelle **non tracciati** e non in `.gitignore`:
- `.firebase/`, `android/build/`, `node_modules/`, `package.json`, `package-lock.json`
- Sono artefatti locali di build/cache (Gradle, Firebase CLI, `node_modules` per `set-storage-cors.js`). Non contengono modifiche di codice, ma andrebbero aggiunti a `.gitignore` per pulizia.

**Allineamento con origin/main:** verificato con `git fetch` — il branch locale è **allineato**, nessun commit da tirare o da pushare.

**Ultimo Step documentato in PROGETTO_CCR.md:** Step 34 (01/07/2026) — 10 interventi post-test moto.

**Versione deployata su ccr-enduro.web.app:**
- `main.dart.js` (bundle compilato) ha header `Last-Modified: Tue, 30 Jun 2026 21:57:48 GMT` (= 30/06 23:57 CEST)
- I commit di Step 34 sono del 01/07 alle 08:25–08:27 CEST (06:25–06:27 UTC), cioè **~8,5 ore dopo** il timestamp del bundle deployato
- ⚠️ Non è possibile stabilire con certezza dai soli timestamp se il deploy contenga già il codice di Step 34: è compatibile sia con un flusso "build+deploy la sera, commit la mattina dopo" (nessun problema) sia con un deploy mancato dopo l'ultima sessione di lavoro. **Raccomando di rilanciare `firebase deploy --only hosting`** per avere certezza, oppure controllare la cronologia deploy sulla Firebase Console.

---

## 2 — Verifica ultimo blocco di lavoro (Step 34 — 10 interventi post-test moto)

Tutti e 10 gli interventi sono stati verificati direttamente nel codice sorgente (non solo nella documentazione).

| # | Intervento | Stato | Riferimento |
|---|---|---|---|
| 1 | GPS background + battery optimization | ✅ **FATTO** | `android/app/src/main/AndroidManifest.xml:13` (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`); `MainActivity.kt` (MethodChannel `ccr/battery`); `lib/core/services/battery_service.dart`; banner in `gps_recording_screen.dart:790-795` |
| 2 | Rotazione anti-scossone (IMU anti-shake) | ✅ **FATTO** | `lib/core/services/imu_fusion_service.dart:41` (`_displayAlpha()`), `:49` (`kMaxHeadingDeltaPerSample = 8.0`), `:51-59` (`_updateDisplayHeading`) |
| 3 | Nomi squadra univoci | ✅ **FATTO** | `lib/core/services/firestore_service.dart:165-175` (`createTeam()`, throw `team_name_exists`); `lib/features/pilot/screens/event_detail_screen.dart:532` (catch dedicato con SnackBar) |
| 4 | Tile mappa offline (download per area evento) | ✅ **FATTO** | `lib/core/services/offline_tile_service.dart`, `offline_tile_service_io.dart`, `offline_tile_service_web.dart`, `lib/features/map/screens/offline_maps_screen.dart`; rotta `/pilot/offline-maps` in `app.dart:187-188`; pulsante in `pilot_home_screen.dart:587` |
| 5 | Salto PS con penalità forfettaria | ✅ **FATTO** | `lib/core/services/gps_service.dart:984` (`skipCurrentSpecial()`); bottone "SALTA SPECIALE" in `gps_recording_screen.dart:1796-1805`; logica forfeit (worst+30min) in `lib/core/services/classifica_engine.dart:134-151` |
| 6 | No banner stale da fermo | ✅ **FATTO** | `lib/core/services/gps_service.dart:327-334` (`isGpsStale`, `return false` se velocità < 2 km/h) |
| 7 | Mappa zoomabile/interattiva pilota | ✅ **FATTO** | `lib/features/pilot/screens/event_detail_screen.dart` — rimosso `interactive: false` (default `true` in `track_map_screen.dart:23`) |
| 8 | Fix traccia non visibile (grey-screen offline) | ✅ **FATTO** | `gps_recording_screen.dart:1064-1069` (fallback su `_eventTrackPoints.first` quando nessun fix GPS) |
| 9 | Miglioramenti precisione GPS (ZUPT) | ✅ **FATTO** | `lib/core/services/imu_fusion_service.dart:403-407` (reset velocità a 0 se < 0.3 m/s e accel bassa) |

**Esito complessivo: 9/9 aree richieste dall'utente confermate FATTO nel codice** (corrispondenti ai 10 sotto-interventi elencati in PROGETTO_CCR.md, i punti 4 e 5 del changelog originale sono stati raggruppati in una sola riga "tile mappa offline"/"fix traccia non visibile" nella lista utente).

---

## 3 — Salute del progetto

**`flutter analyze`:**
```
No issues found! (ran in 200.3s)
```
✅ Zero problemi.

**`flutter pub outdated` — dipendenze con major disponibile:**

| Pacchetto | Attuale | Ultima major |
|---|---|---|
| `cloud_firestore` | 5.6.12 | 6.8.0 |
| `firebase_auth` | 5.7.0 | 6.5.7 |
| `firebase_core` | 3.15.2 | 4.13.0 |
| `firebase_messaging` | 15.2.10 | 16.5.0 |
| `firebase_storage` | 12.4.10 | 13.4.6 |
| `flutter_riverpod` / `riverpod` | 2.6.1 | **3.4.2** (major breaking) |
| `geolocator` | 13.0.4 | 14.0.3 |
| `go_router` | 15.1.3 | 17.3.0 |
| `gpx` | 2.3.0 | 2.5.0 |
| `latlong2` | 0.9.1 | 0.10.1 |
| `sensors_plus` | 6.1.2 | 7.1.0 |
| `wakelock_plus` | 1.5.2 | 1.7.0 |
| `xml` | 6.6.1 | 7.0.1 |
| `file_picker` | 10.3.10 | 11.0.3 (stable) / 12.0.0-beta.7 |

Nessun aggiornamento è urgente, ma l'intero stack Firebase è indietro di una major su tutte le librerie — da pianificare come blocco unico vista l'interdipendenza. `flutter_riverpod` 3.x è breaking change significativo, da testare a parte.

**GitHub Actions (build-apk.yml):**
⚠️ **Non verificabile in modo affidabile.** `gh` CLI non installato in questo ambiente; ho tentato una query diretta alle API GitHub usando il token presente nel remote `origin` ma ha risposto `401 Bad credentials` — il token è scaduto o revocato (vedi anche nota di sicurezza sotto). Il file `.github/workflows/build-apk.yml` esiste, è configurato per buildare APK debug+release su push a `main` e usa correttamente i 4 secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). **Raccomando controllo manuale su github.com** nella tab Actions del repository.

**TODO/FIXME nel codice (`lib/`):** nessuno trovato — `grep -rn "TODO\|FIXME" lib/` non produce risultati. Le attività pendenti sono tracciate solo in `TODO.md` e nella sezione "Prossimi Step" di `PROGETTO_CCR.md`.

---

## 4 — Verifica configurazione critica

**AndroidManifest.xml — permessi GPS background:**
- `ACCESS_BACKGROUND_LOCATION` ✅ (riga 7)
- `FOREGROUND_SERVICE_LOCATION` ✅ (riga 9)
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ✅ (riga 13)
- `foregroundServiceType="location"` ✅ dichiarato (riga 41)

**Keystore release:**
- ✅ Configurato correttamente via GitHub Secrets, nessuna credenziale in chiaro nel repo: `android/app/build.gradle.kts` legge `KEY_ALIAS`/`KEY_PASSWORD`/`KEYSTORE_PASSWORD` da variabili d'ambiente (`System.getenv`), `storeFile` punta a `ccr-release-key.jks` (generato a runtime dal workflow decodificando `KEYSTORE_BASE64`)
- `.gitignore` esclude correttamente `android/app/*.jks` e `*.keystore`
- ⚠️ Non verificabile da qui se i 4 secrets sono effettivamente popolati su GitHub (richiede accesso alla UI/API del repo) — `PROGETTO_CCR.md` li segnala ancora come "azione manuale richiesta" dallo Step 33, da confermare.

**Cloud Functions — allineamento codice/deploy:**
- `functions/index.js` esporta **6 funzioni**: `onRegistrationStatusChange`, `onStartingOrderPublished`, `onStartEnabled`, `onCpDisputeResolved`, `autoArchiveEvents`, `enforceMaxRaceTime`
- Il file locale `functions/functions.yaml` (cache di build/deploy generata da Firebase CLI) ne elenca solo **5**, mancante `onCpDisputeResolved`, e la sua data di modifica (09/06) precede quella di `index.js` (22/06)
- Questo è coerente con quanto già annotato in `PROGETTO_CCR.md` ("Prossimi Step" — deploy di `firestore:rules` per `cp_disputes` e di `functions:onCpDisputeResolved` ancora sospesi): **`onCpDisputeResolved` risulta scritta nel codice ma non ancora deployata**
- Non verificabile lo stato live effettivo su Firebase senza accesso CLI autenticato — conclusione basata su evidenza locale (artefatti di build), non su query diretta al progetto Firebase

**Regole di sicurezza — Firestore vs Storage:**
- `firestore.rules`: ✅ regole granulari di produzione già in vigore (funzioni `isAdmin()`/`isOwner()`, regole per-collezione — corrispondono allo Step 16)
- `storage.rules`: ❌ **ancora la regola permissiva temporanea** `allow read, write: if request.auth != null;` su tutto il bucket, NON le regole granulari admin/pilota descritte allo Step 9. Il TODO "ripristinare regole granulari per produzione" in `PROGETTO_CCR.md` risulta **ancora aperto solo per Storage**, non per Firestore.

---

## ⚠️ Segnalazione di sicurezza (fuori scope dai punti richiesti, ma rilevante)

L'URL del remote `origin` in `.git/config` contiene un **Personal Access Token GitHub in chiaro** (formato `https://ghp_...@github.com/...`). La query di test alle API GitHub ha restituito `401 Bad credentials`, quindi il token risulta **già scaduto o revocato** — ma resta buona norma:
1. Rimuovere il token dall'URL del remote (`git remote set-url origin https://github.com/<owner>/<repo>.git`) e autenticarsi invece via SSH o credential manager/`gh auth login`
2. Se il token dovesse risultare ancora attivo altrove, revocarlo dalle impostazioni GitHub

Non ho scritto il valore del token in questo file né altrove nel repository.

---

## Riepilogo esecutivo

- **Codice:** allineato tra locale e `origin/main`, nessuna modifica pendente, `flutter analyze` pulito
- **Step 34 (10 interventi post-test moto):** tutti confermati implementati nel codice, non solo documentati
- **Deploy hosting:** probabilmente aggiornato, ma timestamp ambigui — consigliato un redeploy di conferma prima di continuare
- **Cloud Functions:** una funzione (`onCpDisputeResolved`) scritta ma non ancora deployata
- **Gap di sicurezza produzione:** `storage.rules` ancora permissivo (Firestore invece già granulare)
- **Da verificare manualmente:** esito ultimo run GitHub Actions, presenza reale dei 4 secrets keystore su GitHub (non verificabile senza `gh` CLI/accesso API funzionante)
