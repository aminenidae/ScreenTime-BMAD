/**
 * Diagnostic report functions
 *
 * Receives extension log files + device context from a child device for
 * support / forensic debugging. Stored in `diagnosticReports/{reportId}`.
 *
 * Security: Firestore rules MUST deny all client reads on this collection.
 * Only the admin SDK (server / Firebase Console) may read. Client can only
 * write via this callable function — direct client writes are also rule-blocked.
 *
 * Threat model: protect log content (filter chain names, decision logic) from
 * casual extraction by competitors. Auth + deny-all client read rules + no
 * client-facing share UI in Release builds is sufficient for that bar.
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

// Hard cap to prevent abuse / runaway costs. Real logs run ~50–500 KB across
// 7 days; 5 MB allows headroom.
const MAX_PAYLOAD_BYTES = 5 * 1024 * 1024;
const MAX_FILES = 14;
const MAX_FILE_BYTES = 2 * 1024 * 1024;

interface LogFile {
  name: string;
  content: string;  // base64-encoded UTF-8 log content
}

interface DeviceInfo {
  deviceId?: string;
  deviceName?: string;
  deviceModel?: string;
  systemName?: string;
  systemVersion?: string;
  appVersion?: string;
  buildNumber?: string;
  batteryState?: string;
  batteryLevel?: number;
  bundleIdentifier?: string;
}

interface SubmitData {
  logFiles: LogFile[];
  deviceInfo: DeviceInfo;
  notes?: string;  // optional user-entered description (currently unused; reserved)
}

/**
 * Submit a diagnostic report from a user device.
 *
 * Matches the unauthenticated-callable pattern of other functions in this
 * codebase (createFamily, createPairingToken). Validation is by payload
 * shape + size limits + deviceId presence. Firestore rules deny direct
 * client read access to the diagnosticReports collection.
 *
 * Returns a short reference ID the user can quote in support: `RPT-XXXXXX`.
 */
export const submitDiagnosticReport = functions.https.onCall(async (data: SubmitData, context) => {
  const { logFiles, deviceInfo, notes } = data;

  if (!deviceInfo || !deviceInfo.deviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceInfo.deviceId is required');
  }

  if (!Array.isArray(logFiles) || logFiles.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'logFiles array is required');
  }

  if (logFiles.length > MAX_FILES) {
    throw new functions.https.HttpsError('invalid-argument', `Too many files (max ${MAX_FILES})`);
  }

  // Validate total payload size
  let totalBytes = 0;
  for (const f of logFiles) {
    if (typeof f.name !== 'string' || typeof f.content !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'Malformed logFile entry');
    }
    if (f.content.length > MAX_FILE_BYTES) {
      throw new functions.https.HttpsError('invalid-argument', `File ${f.name} exceeds ${MAX_FILE_BYTES} bytes`);
    }
    totalBytes += f.content.length;
  }
  if (totalBytes > MAX_PAYLOAD_BYTES) {
    throw new functions.https.HttpsError('invalid-argument', 'Payload exceeds maximum size');
  }

  // Generate reportId: short, human-quotable, case-insensitive
  // Format: RPT-XXXXXX (6 hex chars from auto-id)
  const docRef = db.collection('diagnosticReports').doc();
  const shortId = docRef.id.substring(0, 6).toUpperCase();
  const reportId = `RPT-${shortId}`;

  // Firestore document-size limit is 1 MiB. Log files commonly exceed that
  // when concatenated, so we store each file in its own subcollection doc and
  // chunk individual files that are themselves > ~900 KB of base64. The
  // parent doc holds only metadata. To reassemble offline: list
  // diagnosticReports/{id}/files, group by `name`, sort by `partIndex`,
  // concat the `content` strings, base64-decode.
  const CHUNK_BYTES = 900_000;  // base64 chars; leaves ~100KB headroom under 1MiB doc limit

  // 1. Parent metadata doc — small, always fits.
  await docRef.set({
    reportId,
    fullDocId: docRef.id,
    submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    submittedBy: {
      uid: context.auth?.uid || null,
      deviceId: deviceInfo.deviceId,
    },
    deviceInfo: deviceInfo || {},
    notes: typeof notes === 'string' ? notes.substring(0, 1000) : null,
    fileManifest: logFiles.map((f) => ({
      name: f.name.substring(0, 256),
      sizeBytes: f.content.length,
      partCount: Math.max(1, Math.ceil(f.content.length / CHUNK_BYTES)),
    })),
    totalBytes,
    fileCount: logFiles.length,
  });

  // 2. Subcollection: one doc per file, chunked across multiple docs if needed.
  const filesCol = docRef.collection('files');
  for (const f of logFiles) {
    const safeName = f.name.replace(/[^a-zA-Z0-9._-]/g, '_').substring(0, 200);
    const partCount = Math.max(1, Math.ceil(f.content.length / CHUNK_BYTES));
    if (partCount === 1) {
      await filesCol.doc(safeName).set({
        name: f.name,
        content: f.content,
        sizeBytes: f.content.length,
        partIndex: 0,
        partCount: 1,
      });
    } else {
      for (let i = 0; i < partCount; i++) {
        const start = i * CHUNK_BYTES;
        const chunk = f.content.substring(start, start + CHUNK_BYTES);
        await filesCol.doc(`${safeName}__part${i}`).set({
          name: f.name,
          content: chunk,
          sizeBytes: f.content.length,
          partIndex: i,
          partCount,
        });
      }
    }
  }

  return { reportId };
});
