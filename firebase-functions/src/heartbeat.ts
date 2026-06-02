/**
 * Child-device monitoring heartbeat for the silent-push monitoring refresh.
 *
 * The child app calls this periodically (on foreground + its background upload cycle).
 * We stamp liveness and the reward-unlock state onto the device record so the scheduled
 * silence detector (monitoring.ts) can tell when a device has gone dark *while a reward
 * app was unlocked* — the only window where a background blackout lets reward usage run
 * past its limit. See docs/SILENT_PUSH_MONITORING_REFRESH.md.
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

interface HeartbeatData {
  deviceId: string;
  familyId?: string;
  rewardUnlocked?: boolean;
  timezone?: string;
  fcmToken?: string;
  extensionLastActive?: number; // unix seconds — the extension's last event cycle
}

export const childHeartbeat = functions.https.onCall(async (data: HeartbeatData, _context) => {
  const { deviceId, familyId, rewardUnlocked, timezone, fcmToken, extensionLastActive } = data;

  if (!deviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing deviceId');
  }

  const update: Record<string, unknown> = {
    lastHeartbeat: admin.firestore.FieldValue.serverTimestamp(),
    rewardUnlocked: rewardUnlocked === true,
  };
  if (familyId) update.familyId = familyId;
  if (timezone) update.timezone = timezone;
  if (fcmToken) update.fcmToken = fcmToken;
  if (typeof extensionLastActive === 'number') update.extensionLastActive = extensionLastActive;

  // Merge so we never clobber the pairing-time fields (role, deviceType, createdAt).
  await db.collection('devices').doc(deviceId).set(update, { merge: true });

  return { success: true };
});
