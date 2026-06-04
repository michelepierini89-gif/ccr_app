// Service worker per FCM background notifications su web.
// Viene registrato automaticamente da firebase_messaging_web.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCpZdlyS-oFIheRmwQHrGTDLz1jGNsOLa8',
  authDomain: 'ccr-enduro.firebaseapp.com',
  projectId: 'ccr-enduro',
  storageBucket: 'ccr-enduro.firebasestorage.app',
  messagingSenderId: '688005570976',
  appId: '1:688005570976:web:6708bfdff0f0154f2b84c5',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'CCR Rally';
  const body = payload.notification?.body ?? '';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});
