#!/usr/bin/env node
/**
 * Read-only Firestore exporter + analyzer.
 *
 * Credentials are read from the environment, never hard-coded:
 *   - FIREBASE_SERVICE_ACCOUNT      Full service-account JSON (as a string), OR
 *   - GOOGLE_APPLICATION_CREDENTIALS Path to a service-account JSON file
 *
 * Optional:
 *   - FIREBASE_PROJECT_ID  Override project id (otherwise taken from the key)
 *   - EXPORT_DIR           Where to write JSON dumps (default ./export)
 *   - MAX_DOCS_PER_COLL    Safety cap per collection (default 5000)
 *
 * This script only READS. It performs no writes, updates, or deletes.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function loadCredential() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (inline && inline.trim()) {
    try {
      return JSON.parse(inline);
    } catch (e) {
      // Allow base64-encoded JSON too.
      try {
        return JSON.parse(Buffer.from(inline, 'base64').toString('utf8'));
      } catch (_) {
        throw new Error('FIREBASE_SERVICE_ACCOUNT is set but is not valid JSON (or base64 JSON).');
      }
    }
  }
  const file = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (file && fs.existsSync(file)) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  }
  throw new Error(
    'No credentials found. Set FIREBASE_SERVICE_ACCOUNT (JSON string) or ' +
    'GOOGLE_APPLICATION_CREDENTIALS (path to JSON file).'
  );
}

function serialize(value) {
  // Convert Firestore-specific types into plain JSON-friendly values.
  if (value && typeof value === 'object') {
    if (typeof value.toDate === 'function') return value.toDate().toISOString(); // Timestamp
    if (typeof value.latitude === 'number' && typeof value.longitude === 'number') {
      return { _geopoint: [value.latitude, value.longitude] };
    }
    if (value._path && value.id) return { _ref: value.path };
    if (Array.isArray(value)) return value.map(serialize);
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = serialize(v);
    return out;
  }
  return value;
}

async function dumpCollection(db, collRef, exportDir, maxDocs, depth = 0) {
  const snap = await collRef.limit(maxDocs).get();
  const docs = [];
  for (const doc of snap.docs) {
    const data = serialize(doc.data());
    const entry = { _id: doc.id, ...data };

    // Recurse into subcollections (one level is usually enough; this goes all the way).
    const subcolls = await doc.ref.listCollections();
    if (subcolls.length) {
      entry._subcollections = {};
      for (const sub of subcolls) {
        entry._subcollections[sub.id] = await dumpCollection(db, sub, exportDir, maxDocs, depth + 1);
      }
    }
    docs.push(entry);
  }
  return docs;
}

function summarize(name, docs) {
  const lines = [];
  lines.push(`\n### ${name}  (${docs.length} docs${docs.length >= 1 ? '' : ''})`);
  if (!docs.length) return lines.join('\n');

  // Tally a few well-known subscription fields if present.
  const tally = (field) => {
    const counts = {};
    let seen = 0;
    for (const d of docs) {
      if (d[field] !== undefined) {
        seen++;
        const key = String(d[field]);
        counts[key] = (counts[key] || 0) + 1;
      }
    }
    if (!seen) return null;
    const parts = Object.entries(counts)
      .sort((a, b) => b[1] - a[1])
      .map(([k, v]) => `${k}=${v}`)
      .join(', ');
    return `  - ${field}: ${parts}`;
  };

  for (const field of ['subscriptionStatus', 'subscriptionTier', 'role', 'maxChildren']) {
    const line = tally(field);
    if (line) lines.push(line);
  }
  return lines.join('\n');
}

async function main() {
  const cred = loadCredential();
  const projectId = process.env.FIREBASE_PROJECT_ID || cred.project_id;
  const exportDir = path.resolve(process.env.EXPORT_DIR || path.join(__dirname, 'export'));
  const maxDocs = parseInt(process.env.MAX_DOCS_PER_COLL || '5000', 10);

  fs.mkdirSync(exportDir, { recursive: true });

  admin.initializeApp({
    credential: admin.credential.cert(cred),
    projectId,
  });
  const db = admin.firestore();

  console.log(`Connected to Firestore project: ${projectId}`);
  console.log(`Export dir: ${exportDir}\n`);

  const rootColls = await db.listCollections();
  console.log(`Found ${rootColls.length} root collection(s): ${rootColls.map((c) => c.id).join(', ')}\n`);

  const summaries = [`# Firestore export — ${projectId}`, `Generated: ${new Date().toISOString()}`];

  for (const coll of rootColls) {
    process.stdout.write(`Exporting "${coll.id}" ... `);
    const docs = await dumpCollection(db, coll, exportDir, maxDocs);
    const outFile = path.join(exportDir, `${coll.id}.json`);
    fs.writeFileSync(outFile, JSON.stringify(docs, null, 2));
    console.log(`${docs.length} docs -> ${path.relative(process.cwd(), outFile)}`);
    summaries.push(summarize(coll.id, docs));
  }

  const summaryFile = path.join(exportDir, 'SUMMARY.md');
  fs.writeFileSync(summaryFile, summaries.join('\n') + '\n');
  console.log(`\nWrote summary -> ${path.relative(process.cwd(), summaryFile)}`);
  console.log('\nDone. All operations were read-only.');
}

main().catch((err) => {
  console.error('\nERROR:', err.message);
  process.exit(1);
});
