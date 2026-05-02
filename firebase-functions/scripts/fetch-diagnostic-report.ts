/**
 * Fetch a diagnostic report from Firestore and reassemble the log files
 * to disk. Usage:
 *
 *   cd firebase-functions
 *   npx ts-node scripts/fetch-diagnostic-report.ts RPT-GZT2O0
 *
 * Output: ./reports/RPT-GZT2O0/
 *           ext-log-2026-05-02.log
 *           ext-log-2026-05-01.log
 *           ...
 *           _metadata.json     (deviceInfo, submittedAt, manifest)
 *
 * Requires:
 *   - firebase-admin (already in package.json)
 *   - GOOGLE_APPLICATION_CREDENTIALS env var pointing to a service-account
 *     JSON key with Firestore read access. To get one:
 *       Firebase Console → Project Settings → Service Accounts →
 *       "Generate new private key" → save somewhere safe
 *       export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
 *
 *   Alternatively run `gcloud auth application-default login` if you have
 *   gcloud CLI configured.
 */

import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';

const reportId = process.argv[2];
if (!reportId || !reportId.startsWith('RPT-')) {
  console.error('Usage: npx ts-node scripts/fetch-diagnostic-report.ts RPT-XXXXXX');
  process.exit(1);
}

admin.initializeApp({
  projectId: 'screentimerewards',
});

const db = admin.firestore();

async function main() {
  console.log(`Looking up ${reportId}...`);

  const snap = await db.collection('diagnosticReports')
    .where('reportId', '==', reportId)
    .limit(1)
    .get();

  if (snap.empty) {
    console.error(`No report found for ${reportId}`);
    process.exit(2);
  }

  const parent = snap.docs[0];
  const meta = parent.data();
  console.log(`  Doc:        ${parent.id}`);
  console.log(`  Submitted:  ${meta.submittedAt?.toDate?.()?.toISOString() || 'unknown'}`);
  console.log(`  Device:     ${meta.deviceInfo?.deviceName} (${meta.deviceInfo?.deviceModel})`);
  console.log(`  iOS:        ${meta.deviceInfo?.systemVersion}`);
  console.log(`  App:        ${meta.deviceInfo?.appVersion} (${meta.deviceInfo?.buildNumber})`);
  console.log(`  Battery:    ${meta.deviceInfo?.batteryState} ${meta.deviceInfo?.batteryLevel}`);
  console.log(`  Files:      ${meta.fileCount}`);
  console.log(`  Total:      ${meta.totalBytes} bytes`);

  // Read all file part docs.
  const fileDocs = await parent.ref.collection('files').get();
  console.log(`  Subcoll:    ${fileDocs.size} part(s)`);

  // Group parts by file name and sort by partIndex.
  const parts: Map<string, Array<{ partIndex: number; content: string }>> = new Map();
  fileDocs.forEach((doc) => {
    const d = doc.data();
    const name = d.name as string;
    const list = parts.get(name) || [];
    list.push({ partIndex: d.partIndex || 0, content: d.content || '' });
    parts.set(name, list);
  });

  // Output directory.
  const outDir = path.join('reports', reportId);
  fs.mkdirSync(outDir, { recursive: true });

  // Write metadata sidecar.
  fs.writeFileSync(
    path.join(outDir, '_metadata.json'),
    JSON.stringify({
      reportId: meta.reportId,
      fullDocId: meta.fullDocId,
      submittedAt: meta.submittedAt?.toDate?.()?.toISOString() || null,
      submittedBy: meta.submittedBy,
      deviceInfo: meta.deviceInfo,
      notes: meta.notes,
      fileManifest: meta.fileManifest,
      totalBytes: meta.totalBytes,
      fileCount: meta.fileCount,
    }, null, 2)
  );

  // Reassemble each file.
  for (const [name, list] of parts.entries()) {
    list.sort((a, b) => a.partIndex - b.partIndex);
    const base64 = list.map((p) => p.content).join('');
    const buffer = Buffer.from(base64, 'base64');
    const outPath = path.join(outDir, name);
    fs.writeFileSync(outPath, buffer);
    console.log(`  → ${outPath} (${buffer.length} bytes, ${list.length} part${list.length > 1 ? 's' : ''})`);
  }

  console.log(`\nDone. Open: open ${outDir}`);
}

main().catch((err) => {
  console.error('Failed:', err);
  process.exit(99);
});
