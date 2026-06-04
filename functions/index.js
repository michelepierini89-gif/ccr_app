const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
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

// ── Trigger 2: admin abilita la partenza ────────────────────────────────────
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
