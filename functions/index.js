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
      const orario = startDate.toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' });

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
