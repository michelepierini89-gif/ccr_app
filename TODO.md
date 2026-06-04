# CCR App — TODO e funzionalità mancanti

**Aggiornato:** 04 giugno 2026

---

## Alta priorità (necessari per produzione)

### Deploy
- [ ] `firebase deploy` — deploy su Firebase Hosting
- [ ] Configurare regole Firebase Storage (attualmente aperto o mancante)
- [ ] Build APK Android (richede WSL2 con `memory=4GB` in `.wslconfig`)
- [ ] Test con GPS reale su Android

### Test E2E
- [ ] Test end-to-end classifica e timing con più piloti simulati
- [ ] Test flusso offline: spegnere connessione durante tracking, verificare sync al ritorno

---

## Media priorità (miglioramenti UX)

### Offline
- [ ] Banner visibile nell'app quando ci sono dati in coda offline (badge nel navigatore o snackbar persistente)
- [ ] Sync offline per `joinTeam` (attualmente solo `registerForEvent` viene messo in coda)
- [ ] Sync offline per `updatePilotTracking` (attualmente ignorato offline, potrebbe essere utile per l'ultima posizione)

### Gestione errori
- [ ] Retry automatico con backoff esponenziale per le sync offline
- [ ] Gestione esplicita del caso "iscrizione duplicata" (Firestore lancia un errore se il documento esiste già)

### UX
- [ ] Schermata "Profilo pilota" con modifica nome/cognome
- [ ] Pulsante logout visibile anche nella PilotHomeScreen
- [ ] Animazione di transizione tra le schermate (attualmente nessuna)
- [ ] Pull-to-refresh su EventDetailScreen e TimingScreen

---

## Bassa priorità (funzionalità future)

### Risultati
- [ ] Export PDF risultati post-gara (con logo CCR, classifica finale, tempi speciali)
- [ ] Grafico andamento classifica durante la gara

### Admin
- [ ] Mappa live admin con trail percorso per ogni pilota (attualmente solo posizione istantanea)
- [ ] Dashboard admin con statistiche gara (passaggi speciali, ritiri, progressi)
- [ ] Possibilità di eliminare un evento (con conferma e cleanup dati)
- [ ] Clona evento (copia struttura per garanzia successiva)
- [ ] Impostazione orario di partenza per speciale

### Pilota
- [ ] Notifica push quando l'admin abilita la partenza (già implementato FCM, da testare end-to-end)
- [ ] Visualizzazione track storia (i tracciati percorsi nelle gare passate)

### Tecnico
- [ ] Coverage test su GpsService (waypoint detection, special entry/exit logic)
- [ ] Coverage test su ClassificaEngine (somma tempi, punteggio F1, tie-breaking)
- [ ] Configurare GitHub Actions per CI (flutter test + flutter analyze)
- [ ] Aggiornare CORS Firebase Storage per eventuali nuovi domini

---

## Note tecniche

### Limitazioni note
- **Web**: Firestore offline persistence non abilitata per default → OfflineQueueService gestisce le scritture mancate
- **iOS**: non testato — richiederebbe Mac e developer account Apple
- **Build Android**: richiede WSL2 con limite memoria (`memory=4GB` in `.wslconfig`) per evitare OOM crash

### Credenziali e configurazione
- Chiave VAPID FCM: in `AppConstants.fcmWebVapidKey` (già configurata)
- CORS Storage: già applicato con `cors.json`; se il bucket viene ricreato, riapplicare
- Admin secret code: `CCR2024` in `AppConstants.adminSecretCode`
