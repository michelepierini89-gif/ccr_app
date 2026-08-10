# Stato del Progetto CCR App — Report di Ripresa

**Generato:** 04 agosto 2026, **aggiornato:** 11 agosto 2026 (dopo Step 41 — percorso alternativo, deploy separato e verifica end-to-end)
**Metodo:** analisi statica del repository locale + verifiche dirette su Firestore/GitHub API con le credenziali della sessione (non solo lettura documentazione).

---

## 1 — Stato Git e Deploy

**Ultimo commit su `main`:**
- Hash: `6db02c9`
- Data: 10/08/2026, 21:57
- Messaggio: `docs: aggiorna PROGETTO_CCR.md con l'esito della verifica end-to-end Step 41`
- Commit di codice più recente: `2fdf07a` (10/08, 18:02) — *"feat: percorso alternativo per evento con attivazione admin, notifica piloti e tracciabilità variante usata"*

**Modifiche non committate:** nessuna. `git status` pulito, branch allineato con `origin/main`.

**Ultimo Step documentato in `PROGETTO_CCR.md`:** Step 41 (10-11/08/2026) — percorso alternativo per evento (variante B attivabile dall'admin, es. per maltempo), con tracciabilità della variante usata da ogni pilota indipendente da cambi successivi.

**Deploy — tutti e tre i canali allineati al commit corrente, verificati in questa sessione:**
- **Hosting**: `firebase deploy --only hosting` eseguito subito dopo il commit `2fdf07a` — bundle web aggiornato.
- **Firestore rules**: `firebase deploy --only firestore:rules` eseguito — regole Step 41 in vigore (lettura `tracking/{eventId}/pilots/{userId}` ora ad admin **e** proprietario, non solo admin; nuova collezione pubblica `tracking/{eventId}/routeVariantByUser`).
- **Cloud Functions**: nuovo trigger `onRouteChanged` deployato e **verificato end-to-end** con log diagnostici temporanei (poi rimossi, `git diff` confermato vuoto prima del redeploy finale) — vedi dettaglio sezione 2.

**GitHub Actions:** verificato via API con il token presente nel remote (**vedi nota sicurezza sotto**, il token risulta oggi valido e con scope `repo, workflow`) — ultime 3 run di `Build APK (Debug + Release)` tutte `completed`/`success`, l'ultima sul commit di questa stessa sessione.

---

## 2 — Verifica ultimo blocco di lavoro (Step 41 — percorso alternativo)

A differenza del check di ripresa del 04/08 (analisi statica), questa verifica è stata **eseguita in produzione** con chiamate dirette a Firestore/Firebase Auth REST API, non solo lettura del codice.

| # | Verifica | Esito | Come |
|---|---|---|---|
| 1 | Un pilota (non admin) legge il proprio tracking | ✅ **CONFERMATO** | Login reale come `test.pilota.audit@ccr-enduro-test.com`, lettura `tracking/{eventId}/pilots/{uid}` proprio → `200`. Controllo negativo: stesso pilota su tracking di un ALTRO pilota → `403` (la regola resta ristretta ad admin+proprietario, non aperta a tutti) |
| 2 | Notifica FCM inviata all'attivazione del percorso | ✅ **CONFERMATO** | Trigger `onRouteChanged` verificato con log temporanei: rilevato cambio `activeRouteId`, trovato iscritto approvato, risolto token FCM, chiamata `sendEachForMulticast` eseguita (fallita solo perché il token di test era fittizio — `messaging/invalid-argument`, non un errore di logica) |
| 3 | `routeVariantByUser` leggibile da un pilota non admin (serve alla classifica) | ✅ **CONFERMATO** | Stesso pilota di test, lettura dell'intera collezione (propria voce + voce di un altro pilota) → `200`, entrambe visibili |

**Dati di test:** creati in un evento isolato (`verify-route-variant-test`) e **completamente ripuliti** al termine — confermato che il conteggio eventi in Firestore è tornato al valore precedente (15) senza residui.

**Incidente segnalato per trasparenza:** durante la pulizia, un comando con `updateMask` mal formato ha temporaneamente azzerato i campi del documento utente del pilota di test (non solo il campo da rimuovere). Rilevato subito e ripristinato allo stato esatto precedente (stesso `nome`/`cognome`/`email`/`role`/`createdAt`) — nessun impatto residuo, dettagli completi in `PROGETTO_CCR.md` sotto Step 41.

**Esito complessivo: 3/3 verifiche superate**, feature Step 41 operativa in produzione end-to-end (non solo deployata).

---

## 3 — Salute del progetto

**`flutter analyze`:** `No issues found!` — verificato più volte nel corso della sessione Step 41, incluso dopo l'ultimo commit.

**`flutter test`:** 83/83 verdi (72 preesistenti + 11 nuovi per il percorso alternativo).

**`flutter pub outdated`:** non rieseguito in questa sessione — l'ultima rilevazione (04/08/2026) mostrava l'intero stack Firebase indietro di una major (`cloud_firestore`, `firebase_auth`, `firebase_core`, `firebase_messaging`, `firebase_storage`) e `flutter_riverpod`/`riverpod` con major 3.x disponibile (breaking change). Nessun aggiornamento era urgente allora; da rivalutare con un nuovo `flutter pub outdated` se si pianifica un aggiornamento dipendenze, non assumere che i numeri di luglio siano ancora esatti.

**TODO/FIXME nel codice (`lib/`):** non rieseguito il grep in questa sessione; alle rilevazioni precedenti risultava vuoto (nessun TODO/FIXME lasciato nel codice, le attività pendenti restano tracciate in `TODO.md` e "Prossimi Step" di `PROGETTO_CCR.md`).

---

## 4 — Verifica configurazione critica

**Keystore release e secrets GitHub:** verificato via GitHub API (nomi/data aggiornamento, mai i valori) — tutti e 4 i secret **presenti**: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (ultimo aggiornamento 27/06/2026). Il dubbio lasciato aperto dal report del 04/08 ("non verificabile senza accesso API") è risolto: **sono popolati**, e le build APK Debug+Release completano con successo (vedi sezione 1).

**Cloud Functions — allineamento codice/deploy:** **7 funzioni deployate**, tutte allineate al codice sorgente attuale: `onRegistrationStatusChange`, `onStartingOrderPublished`, `onStartEnabled`, `onCpDisputeResolved`, `onRouteChanged` (nuova, Step 41), `autoArchiveEvents`, `enforceMaxRaceTime`. Il gap segnalato dal report del 04/08 (`onCpDisputeResolved` scritta ma non deployata) risulta **già risolto** (deployata allo Step 35, confermato ora `firebase functions:list`).

**Regole di sicurezza — Firestore vs Storage:**
- `firestore.rules`: ✅ granulari, aggiornate allo Step 41 (lettura tracking pilota estesa al proprietario, nuova collezione pubblica `routeVariantByUser`) — verificate con un pilota reale non admin, non solo lette dal file.
- `storage.rules`: ❌ **ancora aperto** — resta la regola permissiva temporanea `allow read, write: if request.auth != null;` su tutto il bucket, non le regole granulari admin/pilota. Nessuna sessione recente l'ha toccato: stesso TODO del report del 04/08, ancora da fare.

---

## ⚠️ Segnalazione di sicurezza (aggiornata)

L'URL del remote `origin` in `.git/config` contiene ancora un **Personal Access Token GitHub in chiaro**. A differenza del report del 04/08 (che lo dava per scaduto/revocato, `401`), verificato ora via API: **il token è valido**, con scope `repo, workflow`. Questo cambia la raccomandazione da "non urgente" a **da sistemare a breve**:
1. Rimuovere il token dall'URL del remote (`git remote set-url origin https://github.com/<owner>/<repo>.git`) e passare a SSH o a un credential manager/`gh auth login`
2. Valutare la revoca del token attuale e la generazione di uno nuovo con lo scope minimo necessario, una volta spostata l'autenticazione

Non ho scritto il valore del token in questo file né altrove nel repository.

---

## Riepilogo esecutivo

- **Codice:** allineato tra locale e `origin/main`, nessuna modifica pendente, `flutter analyze` pulito, 83/83 test verdi
- **Step 41 (percorso alternativo):** implementato, deployato su tutti e tre i canali (hosting/functions/firestore rules) e **verificato end-to-end in produzione** con un pilota reale non admin — non solo documentato
- **Deploy:** hosting, Cloud Functions e Firestore rules tutti allineati al commit corrente
- **Cloud Functions:** tutte e 7 le funzioni del codice sorgente risultano deployate, nessun gap residuo
- **Gap di sicurezza produzione:** `storage.rules` ancora permissivo (unico TODO aperto rimasto su questo fronte)
- **Nuovo item da sistemare:** token GitHub in chiaro nell'URL del remote, verificato **attivo** — da rimuovere/ruotare a breve
- **Da rivalutare se si pianifica lavoro sulle dipendenze:** `flutter pub outdated` non rieseguito in questa sessione, i numeri di riferimento sono di luglio
