# tools/ — script di estrazione dati per il banco di replay

Script Node.js usati per leggere dati reali da Firestore/Storage del
progetto `ccr-enduro` fuori dall'app Flutter — servono per alimentare
`TrackReplayService` (`lib/core/services/track_replay_service.dart`) e la
griglia di metriche qualità traccia con tracce di gara reali invece che
sintetiche.

## Setup

```bash
cd tools
npm install
```

## Autenticazione

Nessun service account key: gli script riusano il token OAuth della sessione
CLI già autenticata sulla macchina (`firebase login`), leggendo
`~/.config/configstore/firebase-tools.json` e rinfrescandolo se scaduto con
il client OAuth pubblico di `firebase-tools` (lo stesso usato da `firebase
login`, non un segreto). Stesso approccio adottato allo Step 38 per l'analisi
dell'evento "Enduro test 01". Prerequisito: `firebase login` con un account
che ha accesso al progetto `ccr-enduro`.

## `firestore-cli.js`

Sola lettura — nessun comando scrive su Firestore/Storage.

```bash
# Documento singolo (path relativo a .../documents/)
node tools/firestore-cli.js get events/<eventId>

# Collezione (con paginazione automatica)
node tools/firestore-cli.js list events

# Trova un evento per nome esatto (campo `nome`)
node tools/firestore-cli.js event-by-name "Carring Clo 2 HB"

# Documenti pilota di un evento (tracking/{eventId}/pilots)
node tools/firestore-cli.js pilots-in-event <eventId>

# Traccia grezza completa di un pilota (RawTrackSample: lat/lng/accuracy/ts)
# — replica FirestoreService.getFullPilotTrack: prova prima la
# sottocollezione a chunk fullTrackChunks, poi il vecchio campo singolo
# pilotTrackFull come fallback. { samples, source, chunkCount } su stdout.
node tools/firestore-cli.js full-track <eventId> <userId>

# Scarica un file da Storage a partire dalla sua downloadURL (es. trackUrl
# di un evento, in genere un KML/GPX di riferimento)
node tools/firestore-cli.js download-track "<downloadURL>" out.kml
```

Tutti i comandi stampano JSON su stdout (tranne `download-track` con
`outFile`, che scrive su file e logga solo la dimensione su stderr).

## Dati personali — non committare output

Le tracce GPS estratte sono dati reali di gara/test dei piloti. Non
committare file scaricati con questi script (JSON/KML/GPX di output) fuori
da `test/fixtures/` — e solo lì se esplicitamente destinati a diventare
fixture di regressione (come già fatto per "Enduro test 01" allo Step 38),
con lo stesso criterio già in uso nel progetto.

## `package.json`

`puppeteer` e `@google-cloud/storage` sono dipendenze preesistenti,
conservate come da richiesta ma non usate dagli script sopra (che si
appoggiano solo alle API `fetch`/`https` native di Node 18+). Se in una
sessione precedente sono serviti per un flusso diverso (es. automazione
browser, upload/gestione bucket), quel codice non è stato trovato nel
repository né altrove sulla macchina al momento di questo riordino — vanno
scritti da capo se servono di nuovo.
