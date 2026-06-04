# Regole Firestore — CCR App

**File:** `firestore.rules`  
**Versione regole:** 2

---

## Principi generali

- Tutte le operazioni richiedono autenticazione (`isAuthenticated`)
- Gli admin possono leggere e scrivere ovunque (salvo eccezioni esplicite)
- Ogni pilota può scrivere solo sui propri documenti (`isOwner`)
- Il campo `stato` dell'iscrizione può essere modificato solo dall'admin

---

## Helper functions

| Funzione | Descrizione |
|---|---|
| `isAuthenticated()` | `request.auth != null` |
| `isAdmin()` | Autenticato + `users/{uid}.role == 'admin'` |
| `isOwner(uid)` | Autenticato + `request.auth.uid == uid` |

---

## Struttura collezioni e regole

### `/users/{userId}`

| Operazione | Chi può |
|---|---|
| read | Qualsiasi utente autenticato |
| create | Solo il proprietario (`isOwner`) |
| update | Proprietario o admin |
| delete | Solo admin |

---

### `/events/{eventId}`

| Operazione | Chi può |
|---|---|
| read | Qualsiasi utente autenticato |
| create / update / delete | Solo admin |

#### `/events/{eventId}/iscritti/{userId}`

| Operazione | Chi può | Note |
|---|---|---|
| read | Admin o proprietario | |
| create | Proprietario | Solo con `stato == 'inAttesa'` |
| update | Admin o proprietario | Il pilota non può modificare il campo `stato` |
| delete | Solo admin | |

> **Dettaglio update pilota:** il check usa `request.resource.data.diff(resource.data).affectedKeys()` per verificare che il campo `stato` non venga toccato dal pilota.

#### `/events/{eventId}/squadre/{teamId}`

| Operazione | Chi può |
|---|---|
| read | Qualsiasi autenticato |
| create / update | Qualsiasi autenticato |
| delete | Solo admin |

> Le squadre sono aperte per consentire ai piloti di crearle e di unirsi (`joinTeam` → `update`).

#### `/events/{eventId}/notifications/{notifId}`

| Operazione | Chi può |
|---|---|
| read | Solo admin |
| create | Qualsiasi autenticato (sistema) |
| update / delete | Solo admin |

#### `/events/{eventId}/withdrawals/{userId}`

| Operazione | Chi può |
|---|---|
| read | Admin o proprietario |
| create | Proprietario o admin |
| delete | Solo admin |

---

### `/tracking/{eventId}`

| Operazione | Chi può |
|---|---|
| read (collection) | Solo admin |

#### `/tracking/{eventId}/pilots/{userId}`

| Operazione | Chi può |
|---|---|
| read | Solo admin |
| write | Proprietario o admin |

> Il pilota aggiorna la propria posizione GPS in tempo reale.

#### `/tracking/{eventId}/passages/{passageId}`

| Operazione | Chi può | Note |
|---|---|---|
| read | Admin o pilota proprietario del passaggio | `resource.data.userId == request.auth.uid` |
| create | Autenticato | Solo se `request.resource.data.userId == request.auth.uid` |
| delete | Solo admin | |

> I passaggi waypoint sono immutabili una volta scritti (nessuna update rule).

---

## Indici (firestore.indexes.json)

Gli indici Firestore dichiarativi necessari sono in `firestore.indexes.json`. Deploy con:
```bash
firebase deploy --only firestore:indexes
```

---

## Deploy regole

```bash
firebase deploy --only firestore:rules
```

Per verificare le regole prima del deploy:
```bash
firebase emulators:start --only firestore
```
