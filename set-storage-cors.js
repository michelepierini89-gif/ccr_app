// Script per configurare CORS su Firebase Storage
// Esegui: node set-storage-cors.js
// Richiede: npm install @google-cloud/storage
//           + autenticazione: gcloud auth application-default login

const { Storage } = require('@google-cloud/storage');

const BUCKET = 'ccr-enduro.firebasestorage.app';

const corsConfig = [
  {
    origin: [
      'http://localhost:8080',
      'http://localhost:*',
      'https://ccr-enduro.web.app',
      'https://ccr-enduro.firebaseapp.com',
    ],
    method: ['GET', 'HEAD'],
    responseHeader: ['Content-Type', 'Content-Length'],
    maxAgeSeconds: 3600,
  },
];

async function main() {
  const storage = new Storage();
  const bucket = storage.bucket(BUCKET);
  await bucket.setCorsConfiguration(corsConfig);
  const [meta] = await bucket.getMetadata();
  console.log('CORS aggiornato:', JSON.stringify(meta.cors, null, 2));
}

main().catch((err) => {
  console.error('Errore:', err.message);
  process.exit(1);
});
