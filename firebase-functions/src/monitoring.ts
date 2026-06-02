/**
 * Silent-push monitoring refresh — silence detector.
 *
 * Runs every 10 minutes. Finds child devices that have gone silent *while a reward app
 * was unlocked*, during the child's local active hours, and pokes them with a
 * content-available (silent) push so the app restarts monitoring. This recovers from
 * iOS-side background blackouts where iOS stops relaunching the DeviceActivity extension
 * (e.g. under low battery — see the Ali 2026-05-31 Roblox over-limit incident).
 *
 * LOG_ONLY mode (default) logs "WOULD POKE …" without sending anything, so the trigger
 * logic can be validated against real data before any real push goes out.
 * See docs/SILENT_PUSH_MONITORING_REFRESH.md.
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

// --- Tunables (validated in LOG_ONLY mode before going live) ---
const LOG_ONLY = false;            // LIVE — sends real pokes (gated by fcmToken presence + guards)
const SILENCE_THRESHOLD_MIN = 10;  // no check-in for this long → "silent"
const ACTIVE_HOUR_START = 7;       // device-local; no pokes before this hour
const ACTIVE_HOUR_END = 22;        // device-local; no pokes at/after this hour (quiet hours)
const MIN_POKE_INTERVAL_MIN = 20;  // don't re-poke a device more often than this
const MAX_POKES_PER_HOUR = 3;      // per-device APNs-throttle insurance

/** Device-local hour (0–23) for a timezone identifier, or null if unknown/invalid. */
function localHour(timezone: string | undefined, now: Date): number | null {
  if (!timezone) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hour12: false,
      hourCycle: 'h23',
    }).formatToParts(now);
    const hourPart = parts.find((p) => p.type === 'hour');
    if (!hourPart) return null;
    const h = parseInt(hourPart.value, 10);
    return Number.isFinite(h) ? h % 24 : null;
  } catch {
    return null;
  }
}

export const monitoringSilenceDetector = functions.pubsub
  .schedule('every 10 minutes')
  .onRun(async () => {
    const now = new Date();
    const nowMs = now.getTime();

    // Filter rewardUnlocked in code (not a compound query) to avoid a composite index.
    const snap = await db.collection('devices').where('role', '==', 'child').get();

    let scanned = 0;
    let candidates = 0;
    let poked = 0;
    const skip = { fresh: 0, noHeartbeat: 0, locked: 0, hours: 0, rate: 0, noToken: 0 };

    for (const doc of snap.docs) {
      scanned++;
      const d = doc.data();

      const lastHeartbeat = d.lastHeartbeat as admin.firestore.Timestamp | undefined;
      if (!lastHeartbeat) { skip.noHeartbeat++; continue; }

      const staleMin = (nowMs - lastHeartbeat.toMillis()) / 60000;
      if (staleMin < SILENCE_THRESHOLD_MIN) { skip.fresh++; continue; }

      // Gate: only poke when the kid could actually be running up reward usage.
      // rewardUnlocked already folds in empty-bank / unmet-goal / daily-limit / hours.
      if (d.rewardUnlocked !== true) { skip.locked++; continue; }

      // Quiet hours / active-hours gate (device-local). If timezone is unknown, don't
      // suppress — better to poke than miss (a poke is harmless).
      const h = localHour(d.timezone as string | undefined, now);
      if (h !== null && (h < ACTIVE_HOUR_START || h >= ACTIVE_HOUR_END)) { skip.hours++; continue; }

      // Rate-limit insurance: minimum interval + hourly cap.
      const lastPoke = d.lastPokeSentAt as admin.firestore.Timestamp | undefined;
      if (lastPoke && (nowMs - lastPoke.toMillis()) / 60000 < MIN_POKE_INTERVAL_MIN) {
        skip.rate++; continue;
      }
      const pokeHourStart = d.pokeHourStart as admin.firestore.Timestamp | undefined;
      const pokesThisHour = (d.pokesThisHour as number | undefined) ?? 0;
      const withinHour = !!pokeHourStart && (nowMs - pokeHourStart.toMillis()) < 3600000;
      if (withinHour && pokesThisHour >= MAX_POKES_PER_HOUR) { skip.rate++; continue; }

      candidates++;

      const fcmToken = d.fcmToken as string | undefined;
      if (!fcmToken) {
        console.log(`[silence-detector] device=${doc.id} silent=${staleMin.toFixed(0)}min reward-unlocked but NO fcmToken on record`);
        skip.noToken++;
        continue;
      }

      if (LOG_ONLY) {
        console.log(`[silence-detector] WOULD POKE device=${doc.id} silent=${staleMin.toFixed(0)}min localHour=${h ?? 'n/a'} pokesThisHour=${pokesThisHour}`);
        continue;
      }

      // --- live send (Phase 3) ---
      try {
        await admin.messaging().send({
          token: fcmToken,
          apns: {
            headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
            payload: { aps: { 'content-available': 1 } },
          },
          data: { type: 'monitoring-refresh' },
        });
        poked++;
        await doc.ref.set({
          lastPokeSentAt: admin.firestore.FieldValue.serverTimestamp(),
          pokeHourStart: withinHour ? pokeHourStart : admin.firestore.Timestamp.fromMillis(nowMs),
          pokesThisHour: withinHour ? pokesThisHour + 1 : 1,
        }, { merge: true });
      } catch (err) {
        console.error(`[silence-detector] send failed device=${doc.id}`, err);
      }
    }

    console.log(
      `[silence-detector] scanned=${scanned} candidates=${candidates} poked=${poked} ` +
      `LOG_ONLY=${LOG_ONLY} skip=${JSON.stringify(skip)}`
    );
    return null;
  });
