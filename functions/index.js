const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

// ── Trigger 1: cambio stato iscrizione ──────────────────────────────────────
// Invia FCM al pilota quando l'admin approva o rifiuta l'iscrizione.
exports.onRegistrationStatusChange = onDocumentUpdated(
  'events/{eventId}/iscritti/{userId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (!before || !after) return null;
    if (before.stato === after.stato) return null;

    const stato = after.stato;
    if (stato !== 'approvato' && stato !== 'rifiutato') return null;

    const userId = event.params.userId;
    const eventId = event.params.eventId;

    const userDoc = await getFirestore()
      .collection('users')
      .doc(userId)
      .get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return null;

    const approved = stato === 'approvato';

    // Recupera il nome evento per il body
    const eventDoc = await getFirestore()
      .collection('events')
      .doc(eventId)
      .get();
    const eventName = eventDoc.data()?.nome ?? 'evento';

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: approved ? '✅ Iscrizione approvata' : '❌ Iscrizione rifiutata',
        body: approved
          ? `La tua iscrizione a "${eventName}" è stata approvata!`
          : `La tua iscrizione a "${eventName}" è stata rifiutata.`,
      },
      data: {
        type: approved ? 'registrationApproved' : 'registrationRejected',
        eventId,
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    return null;
  }
);

// ── Trigger 2: admin abilita la partenza ────────────────────────────────────
// Invia FCM a tutti i piloti approvati quando startEnabled diventa true.
exports.onStartEnabled = onDocumentUpdated(
  'events/{eventId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (!before || !after) return null;
    if (before.startEnabled === after.startEnabled) return null;
    if (!after.startEnabled) return null;

    const eventId = event.params.eventId;
    const eventName = after.nome ?? 'evento';

    // Recupera tutti i piloti approvati
    const regsSnap = await getFirestore()
      .collection('events')
      .doc(eventId)
      .collection('iscritti')
      .where('stato', '==', 'approvato')
      .get();

    if (regsSnap.empty) return null;

    // Recupera i token FCM in parallelo
    const tokenPromises = regsSnap.docs.map((regDoc) =>
      getFirestore().collection('users').doc(regDoc.id).get()
    );
    const userDocs = await Promise.all(tokenPromises);
    const tokens = userDocs
      .map((d) => d.data()?.fcmToken)
      .filter(Boolean);

    if (tokens.length === 0) return null;

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

    return null;
  }
);
