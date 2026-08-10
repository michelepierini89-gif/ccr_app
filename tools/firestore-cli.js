#!/usr/bin/env node
// Estrazione dati da Firestore/Storage per il banco di replay CCR — usa il
// token OAuth della sessione `firebase login` già attiva sulla macchina
// (stesso approccio adottato allo Step 38, senza service account key).
// Sola lettura: nessun comando qui scrive su Firestore/Storage.
//
// Uso: vedi tools/README.md

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT_ID = 'ccr-enduro';

// Client OAuth pubblico del CLI firebase-tools (installed-app flow, non è
// un segreto — è lo stesso client usato da `firebase login` su qualunque
// macchina). Serve solo per il refresh del token quando è scaduto.
const CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function configstorePath() {
  return path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
}

async function getAccessToken() {
  const raw = fs.readFileSync(configstorePath(), 'utf8');
  const cfg = JSON.parse(raw);
  const tokens = cfg.tokens;
  if (!tokens) {
    throw new Error(
      'Nessun token trovato in ' + configstorePath() + ' — esegui `firebase login`.'
    );
  }
  const now = Date.now();
  if (tokens.access_token && tokens.expires_at && now < tokens.expires_at - 60_000) {
    return tokens.access_token;
  }
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: CLI_CLIENT_ID,
      client_secret: CLI_CLIENT_SECRET,
      refresh_token: tokens.refresh_token,
      grant_type: 'refresh_token',
    }),
  });
  if (!res.ok) {
    throw new Error('Refresh token fallito: ' + res.status + ' ' + (await res.text()));
  }
  const data = await res.json();
  return data.access_token;
}

async function authedFetch(url, opts = {}) {
  const token = await getAccessToken();
  const res = await fetch(url, {
    ...opts,
    headers: { ...(opts.headers || {}), Authorization: 'Bearer ' + token },
  });
  if (!res.ok) {
    throw new Error(`${opts.method || 'GET'} ${url} -> ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

// ── Decodifica valori tipati Firestore REST → JS semplice ──────────────────
function decodeValue(v) {
  if (v == null) return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  if ('referenceValue' in v) return v.referenceValue;
  return v;
}

function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

function decodeDoc(doc) {
  if (!doc || !doc.fields) return null;
  const out = decodeFields(doc.fields);
  out._path = doc.name ? doc.name.split('/documents/')[1] : undefined;
  return out;
}

const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function getDoc(relPath) {
  const doc = await authedFetch(`${BASE}/${relPath}`);
  return decodeDoc(doc);
}

async function listCollection(relPath, { pageSize = 300 } = {}) {
  let pageToken;
  const out = [];
  do {
    const url = new URL(`${BASE}/${relPath}`);
    url.searchParams.set('pageSize', String(pageSize));
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const data = await authedFetch(url.toString());
    for (const d of data.documents || []) out.push(decodeDoc(d));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return out;
}

// Query semplice per campo == valore (usata per trovare eventi per nome).
async function queryEquals(collectionId, field, value, { parentPath = '' } = {}) {
  const body = {
    structuredQuery: {
      from: [{ collectionId }],
      where: {
        fieldFilter: {
          field: { fieldPath: field },
          op: 'EQUAL',
          value: typeof value === 'string' ? { stringValue: value } : { integerValue: value },
        },
      },
    },
  };
  const url = `${BASE}${parentPath ? '/' + parentPath : ''}:runQuery`;
  const res = await authedFetch(url, { method: 'POST', body: JSON.stringify(body) });
  return (Array.isArray(res) ? res : [res])
    .filter((r) => r.document)
    .map((r) => decodeDoc(r.document));
}

// ── Traccia grezza completa: replica la logica di
// FirestoreService.getFullPilotTrack (chunk in fullTrackChunks, fallback sul
// vecchio campo singolo pilotTrackFull sul documento pilota). ────────────
async function getFullPilotTrack(eventId, userId) {
  const chunksPath = `tracking/${eventId}/pilots/${userId}/fullTrackChunks`;
  let chunks = [];
  try {
    chunks = await listCollection(chunksPath);
  } catch (e) {
    chunks = [];
  }
  chunks.sort((a, b) => (a._path > b._path ? 1 : -1));
  if (chunks.length > 0) {
    const out = [];
    for (const c of chunks) out.push(...(c.samples || []));
    return { samples: out, source: 'fullTrackChunks', chunkCount: chunks.length };
  }
  const doc = await getDoc(`tracking/${eventId}/pilots/${userId}`);
  if (doc && Array.isArray(doc.pilotTrackFull)) {
    return { samples: doc.pilotTrackFull, source: 'pilotTrackFull(legacy field)', chunkCount: 0 };
  }
  return { samples: [], source: 'none', chunkCount: 0 };
}

async function downloadStorageFile(bucket, storagePath) {
  const encoded = encodeURIComponent(storagePath);
  const token = await getAccessToken();
  const res = await fetch(
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encoded}?alt=media`,
    { headers: { Authorization: 'Bearer ' + token } }
  );
  if (!res.ok) throw new Error(`Storage download ${storagePath} -> ${res.status}`);
  return res.text();
}

// Estrae bucket+path da una downloadURL di Firebase Storage
// (https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?...).
function parseStorageUrl(url) {
  const m = url.match(/\/v0\/b\/([^/]+)\/o\/([^?]+)/);
  if (!m) throw new Error('URL Storage non riconosciuto: ' + url);
  return { bucket: m[1], storagePath: decodeURIComponent(m[2]) };
}

// ── CLI ──────────────────────────────────────────────────────────────────
async function main() {
  const [, , cmd, ...args] = process.argv;
  switch (cmd) {
    case 'get': {
      const [relPath] = args;
      console.log(JSON.stringify(await getDoc(relPath), null, 2));
      break;
    }
    case 'list': {
      const [relPath] = args;
      console.log(JSON.stringify(await listCollection(relPath), null, 2));
      break;
    }
    case 'event-by-name': {
      const [name] = args;
      const docs = await queryEquals('events', 'nome', name);
      console.log(JSON.stringify(docs, null, 2));
      break;
    }
    case 'pilots-in-event': {
      const [eventId] = args;
      const docs = await listCollection(`tracking/${eventId}/pilots`);
      console.log(JSON.stringify(docs, null, 2));
      break;
    }
    case 'full-track': {
      const [eventId, userId] = args;
      const result = await getFullPilotTrack(eventId, userId);
      console.log(JSON.stringify(result));
      break;
    }
    case 'download-track': {
      // node tools/firestore-cli.js download-track "<downloadURL>" out.gpx
      const [url, outFile] = args;
      const { bucket, storagePath } = parseStorageUrl(url);
      const content = await downloadStorageFile(bucket, storagePath);
      if (outFile) {
        fs.writeFileSync(outFile, content);
        console.error('Scritto ' + outFile + ' (' + content.length + ' bytes)');
      } else {
        console.log(content);
      }
      break;
    }
    default:
      console.error(
        'Comandi: get <path> | list <path> | event-by-name <nome> | ' +
          'pilots-in-event <eventId> | full-track <eventId> <userId> | ' +
          'download-track <url> [outFile]'
      );
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
