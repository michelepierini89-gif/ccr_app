const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

// ── Trigger 1: cambio stato iscrizione ──────────────────────────────────────
exports.onRegistrationStatusChange = onDocumentUpdated(
  {
    document: 'events/{eventId}/iscritti/{userId}',
    region: 'europe-west1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after || before.stato === after.stato) return;

    const stato = after.stato;
    if (stato !== 'approvato' && stato !== 'rifiutato') return;

    const { userId, eventId } = event.params;
    const db = getFirestore();

    const [userDoc, eventDoc] = await Promise.all([
      db.collection('users').doc(userId).get(),
      db.collection('events').doc(eventId).get(),
    ]);

    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return;

    const eventName = eventDoc.data()?.nome ?? 'evento';
    const approved = stato === 'approvato';

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: approved ? '✅ Iscrizione approvata' : '❌ Iscrizione rifiutata',
        body: approved
          ? `La tua iscrizione a "${eventName}" è stata approvata!`
          : `La tua iscrizione a "${eventName}" è stata rifiutata.`,
      },
      data: { type: approved ? 'registrationApproved' : 'registrationRejected', eventId },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// ── Trigger 2: ordine di partenza pubblicato ─────────────────────────────────
exports.onStartingOrderPublished = onDocumentUpdated(
  {
    document: 'events/{eventId}',
    region: 'europe-west1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const beforeOrder = before.startingOrder ?? [];
    const afterOrder = after.startingOrder ?? [];
    if (afterOrder.length === 0) return;
    if (JSON.stringify(beforeOrder) === JSON.stringify(afterOrder)) return;

    const { eventId } = event.params;
    const eventName = after.nome ?? 'evento';
    const db = getFirestore();

    const teamsSnap = await db
      .collection('events').doc(eventId).collection('squadre')
      .get();
    const teamsByName = new Map(
      teamsSnap.docs.map((d) => [(d.data().nome ?? '').toLowerCase().trim(), d.data()])
    );

    const messages = [];
    for (const slot of afterOrder) {
      const team = teamsByName.get((slot.teamName ?? '').toLowerCase().trim());
      if (!team) continue;
      const membriIds = team.membriIds ?? [];
      if (membriIds.length === 0) continue;

      const startDate = slot.startTime?.toDate ? slot.startTime.toDate() : new Date(slot.startTime);
      const orario = new Intl.DateTimeFormat('it-IT', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Europe/Rome',
      }).format(startDate);

      const userDocs = await Promise.all(
        membriIds.map((uid) => db.collection('users').doc(uid).get())
      );
      const tokens = userDocs.map((d) => d.data()?.fcmToken).filter(Boolean);
      for (const token of tokens) {
        messages.push({
          token,
          notification: {
            title: '🚦 Ordine di partenza pubblicato',
            body: `"${eventName}": parti con il numero ${slot.orderNumber} alle ${orario}.`,
          },
          data: {
            type: 'startingOrderPublished',
            eventId,
            orderNumber: String(slot.orderNumber),
            startTime: startDate.toISOString(),
          },
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default' } } },
        });
      }
    }

    if (messages.length === 0) return;

    // sendEach accetta fino a 500 messaggi per chiamata
    for (let i = 0; i < messages.length; i += 500) {
      await getMessaging().sendEach(messages.slice(i, i + 500));
    }
  }
);

// ── Trigger 3: admin abilita la partenza ────────────────────────────────────
exports.onStartEnabled = onDocumentUpdated(
  {
    document: 'events/{eventId}',
    region: 'europe-west1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    if (before.startEnabled === after.startEnabled || !after.startEnabled) return;

    const { eventId } = event.params;
    const eventName = after.nome ?? 'evento';
    const db = getFirestore();

    const regsSnap = await db
      .collection('events').doc(eventId).collection('iscritti')
      .where('stato', '==', 'approvato')
      .get();

    if (regsSnap.empty) return;

    const userDocs = await Promise.all(
      regsSnap.docs.map((d) => db.collection('users').doc(d.id).get())
    );
    const tokens = userDocs.map((d) => d.data()?.fcmToken).filter(Boolean);
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: '🏁 Via libera!',
        body: `L'organizzatore ha abilitato la partenza per "${eventName}". Puoi avviare il GPS!`,
      },
      data: { type: 'startEnabled', eventId },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// ── Trigger 3b: percorso alternativo attivato/disattivato (10/08/2026) ──────
// Stesso pattern di onStartEnabled: reagisce al cambio di un campo su
// events/{eventId}, notifica tutti gli iscritti approvati. Il client scrive
// SOLO activeRouteId (+ routeChangeLog) su Firestore — nessuna chiamata FCM
// diretta dal client, che non ha le credenziali per farlo.
exports.onRouteChanged = onDocumentUpdated(
  {
    document: 'events/{eventId}',
    region: 'europe-west1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const beforeRoute = before.activeRouteId ?? 'A';
    const afterRoute = after.activeRouteId ?? 'A';
    if (beforeRoute === afterRoute) return;

    const { eventId } = event.params;
    const eventName = after.nome ?? 'evento';
    const label = afterRoute === 'B'
      ? (after.routeB?.label ?? 'Percorso alternativo')
      : (after.routeALabel ?? 'Percorso principale');
    const db = getFirestore();

    const regsSnap = await db
      .collection('events').doc(eventId).collection('iscritti')
      .where('stato', '==', 'approvato')
      .get();
    if (regsSnap.empty) return;

    const userDocs = await Promise.all(
      regsSnap.docs.map((d) => db.collection('users').doc(d.id).get())
    );
    const tokens = userDocs.map((d) => d.data()?.fcmToken).filter(Boolean);
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: '🛣️ Percorso modificato',
        body: `Percorso modificato: la manifestazione si svolgerà sul ${label}. Controlla la mappa aggiornata. (${eventName})`,
      },
      data: { type: 'routeChanged', eventId, routeId: afterRoute },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// ── Trigger 4: segnalazione CP risolta dall'admin ────────────────────────────
// Step 42 — decisione granulare per singolo CP: ogni voce di `missedCps` ha
// il proprio `status` ('pending'/'accepted'/'rejected'), non più un unico
// stato per l'intera segnalazione. Il trigger confronta le voci prima/dopo
// per capire se QUESTO aggiornamento ha deciso almeno un CP (prima
// 'pending', dopo 'accepted' o 'rejected') — così spara anche per
// decisioni parziali/miste, che prima (basandosi solo sul rollup
// `status` a livello di documento) non facevano scattare alcuna notifica
// se il rollup restava 'pending' per via di voci ancora indecise.
exports.onCpDisputeResolved = onDocumentUpdated(
  {
    document: 'cp_disputes/{eventId}/disputes/{disputeId}',
    region: 'europe-west1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const beforeByCpId = new Map(
      (before.missedCps || []).map((c) => [c.cpId, c.status])
    );
    const decidedNow = (after.missedCps || []).filter(
      (c) =>
        (c.status === 'accepted' || c.status === 'rejected') &&
        beforeByCpId.get(c.cpId) !== c.status
    );
    if (decidedNow.length === 0) return;

    const pilotId = after.pilotId;
    if (!pilotId) return;

    const db = getFirestore();
    const userDoc = await db.collection('users').doc(pilotId).get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return;

    const allCps = after.missedCps || [];
    const acceptedCount = allCps.filter((c) => c.status === 'accepted').length;
    const rejectedCount = allCps.filter((c) => c.status === 'rejected').length;
    const anyAccepted = acceptedCount > 0;

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: anyAccepted ? '✅ Segnalazione CP verificata' : '❌ Segnalazione CP verificata',
        body: `L'organizzatore ha verificato la tua segnalazione: ${acceptedCount} CP accolti, ${rejectedCount} rifiutati.`,
      },
      data: {
        type: anyAccepted ? 'cpDisputeAccepted' : 'cpDisputeRejected',
        eventId: event.params.eventId,
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// ── Scheduled: archivia automaticamente gli eventi alla fine del giorno di gara ─
exports.autoArchiveEvents = onSchedule(
  {
    schedule: '59 23 * * *',
    timeZone: 'Europe/Rome',
    region: 'europe-west1',
  },
  async () => {
    const db = getFirestore();

    // Calcola la data odierna in timezone Europe/Rome nel formato ISO YYYY-MM-DD
    const todayRome = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Europe/Rome',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date()); // es. "2026-06-09"

    // Recupera tutti gli eventi non ancora archiviati
    const snapshot = await db
      .collection('events')
      .where('stato', '!=', 'archiviata')
      .get();

    if (snapshot.empty) {
      console.log('autoArchiveEvents: nessun evento da esaminare.');
      return;
    }

    const batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const eventTimestamp = data.data; // campo 'data' → Firestore Timestamp
      if (!eventTimestamp) continue;

      const eventDate = eventTimestamp.toDate();

      // Data dell'evento in timezone Europe/Rome (formato YYYY-MM-DD, confrontabile lessicograficamente)
      const eventDateRome = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Rome',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).format(eventDate);

      if (eventDateRome <= todayRome) {
        batch.update(doc.ref, { stato: 'archiviata' });
        count++;
        console.log(`autoArchiveEvents: archivio "${data.nome}" (data gara: ${eventDateRome})`);
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    console.log(`autoArchiveEvents: ${count} event${count === 1 ? 'o archiviato' : 'i archiviati'}.`);
  }
);

// ── Scheduled: ritiro automatico per superamento tempo massimo gara ─────────
exports.enforceMaxRaceTime = onSchedule(
  {
    schedule: '*/5 * * * *',
    timeZone: 'Europe/Rome',
    region: 'europe-west1',
  },
  async () => {
    const db = getFirestore();
    const now = new Date();

    // Query active events (in_corso only)
    const eventsSnap = await db
      .collection('events')
      .where('stato', '==', 'in_corso')
      .get();

    if (eventsSnap.empty) return;

    for (const eventDoc of eventsSnap.docs) {
      const eventData = eventDoc.data();
      const maxMinutes = eventData.maxRaceTimeMinutes ?? 270;
      const startingOrder = eventData.startingOrder ?? [];
      if (startingOrder.length === 0) continue;

      // Build map: teamName → startTime (Date)
      const startTimeByTeam = {};
      for (const slot of startingOrder) {
        const st = slot.startTime;
        if (!st) continue;
        const startDate = st.toDate ? st.toDate() : new Date(st);
        startTimeByTeam[slot.teamName.trim().toLowerCase()] = startDate;
      }

      // Get all racing pilots for this event
      const pilotsSnap = await db
        .collection('tracking')
        .doc(eventDoc.id)
        .collection('pilots')
        .where('raceStatus', '==', 'racing')
        .get();

      if (pilotsSnap.empty) continue;

      // Get all approved registrations to match userId → teamName
      const regsSnap = await db
        .collection('registrations')
        .where('eventId', '==', eventDoc.id)
        .where('stato', '==', 'approvato')
        .get();

      const teamByUserId = {};
      for (const reg of regsSnap.docs) {
        const d = reg.data();
        if (d.userId && d.teamName) {
          teamByUserId[d.userId] = d.teamName.trim().toLowerCase();
        }
      }

      const batch = db.batch();
      let retiredCount = 0;

      for (const pilotDoc of pilotsSnap.docs) {
        const userId = pilotDoc.id;
        const pilotData = pilotDoc.data();
        const teamName = teamByUserId[userId];
        if (!teamName) continue;

        const startTime = startTimeByTeam[teamName];
        if (!startTime) continue;

        const deadlineMs = startTime.getTime() + maxMinutes * 60 * 1000;
        if (now.getTime() < deadlineMs) continue;

        // Check if pilot has completed all required specials (waypointPassati)
        const waypointPassati = pilotData.waypointPassati ?? [];
        const specialiValide = (eventData.speciali ?? []).filter(
          (s) => !s.annullata,
        );
        const requiredWpIds = new Set(
          specialiValide.flatMap((s) => [s.waypointInizio?.id, s.waypointFine?.id].filter(Boolean)),
        );
        const passedIds = new Set(waypointPassati);
        const allDone = [...requiredWpIds].every((id) => passedIds.has(id));
        if (allDone) continue;

        // Retire pilot
        batch.set(
          pilotDoc.ref,
          { raceStatus: 'retired', retiredReason: 'timeout' },
          { merge: true },
        );

        // Also write to withdrawals sub-collection
        const withdrawalRef = db
          .collection('events')
          .doc(eventDoc.id)
          .collection('withdrawals')
          .doc(userId);
        batch.set(
          withdrawalRef,
          {
            userId,
            eventId: eventDoc.id,
            timestamp: now,
            retiredReason: 'timeout',
          },
          { merge: true },
        );

        retiredCount++;
        console.log(`enforceMaxRaceTime: ritirato userId=${userId} evento=${eventDoc.id}`);
      }

      if (retiredCount > 0) await batch.commit();
    }
  }
);
