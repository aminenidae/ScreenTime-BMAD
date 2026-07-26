/**
 * Family management functions
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

interface CreateFamilyData {
  deviceId: string;
  deviceName: string;
  subscriptionTier: 'trial' | 'solo' | 'individual' | 'family';
  subscriptionStatus: string;
  // Optional: the parent's iCloud-account owner key (an opaque, per-app CloudKit
  // record name — not an email or Apple ID). When present, tags the new family
  // so it stays recoverable after a future parent-device reinstall/replacement,
  // even though deviceId itself is deliberately NOT durable on parent devices.
  // See docs/FAMILY_OWNERSHIP_ICLOUD_KEY_PLAN_2026-07-24.md.
  ownerKey?: string;
}

/**
 * Create a new family when a parent subscribes
 * Called after successful subscription purchase on parent device
 */
export const createFamily = functions.https.onCall(async (data: CreateFamilyData, context) => {
  const { deviceId, deviceName, subscriptionTier, subscriptionStatus, ownerKey } = data;

  // Validate required fields
  if (!deviceId || !subscriptionTier) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Check if device already has a family
  const existingDevice = await db.collection('devices').doc(deviceId).get();
  if (existingDevice.exists && existingDevice.data()?.familyId) {
    // Return existing family
    return { familyId: existingDevice.data()?.familyId };
  }

  // Check if this iCloud owner already has a family. A parent deviceId is
  // deliberately ephemeral (wiped on reinstall — DeviceModeManager "PHASE 3"), so a
  // returning owner reaches this point with a brand-new deviceId and no local
  // familyId pointer, and the check above can't match. Creating a second family for
  // them would orphan the original (along with its already-paired children) AND
  // clobber the familyOwners pointer written below, making the original permanently
  // unrecoverable. Reuse the existing family instead, adopting this device into it.
  if (ownerKey) {
    const ownerDoc = await db.collection('familyOwners').doc(ownerKey).get();
    const ownedFamilyId = ownerDoc.exists ? (ownerDoc.data()?.familyId as string | undefined) : undefined;

    if (ownedFamilyId) {
      const ownedFamilyRef = db.collection('families').doc(ownedFamilyId);
      const ownedFamily = await ownedFamilyRef.get();

      // If the pointer is dangling (family deleted), fall through and create fresh.
      if (ownedFamily.exists) {
        const parents: string[] = ownedFamily.data()?.parents || [];
        const previousSubscriberId: string | undefined = ownedFamily.data()?.subscriberDeviceId;
        // Rotate the owner's own slot rather than appending, for the same reason as
        // claimFamilyOwnership: otherwise every reinstall permanently burns a slot.
        const coParents = parents.filter((p) => p !== previousSubscriberId).slice(0, 1);
        const nextParents = parents.includes(deviceId) ? parents : [...coParents, deviceId];

        const reuseBatch = db.batch();
        reuseBatch.update(ownedFamilyRef, {
          parents: nextParents,
          subscriberDeviceId: deviceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        reuseBatch.set(
          db.collection('devices').doc(deviceId),
          {
            familyId: ownedFamilyId,
            deviceType: 'parent',
            role: 'subscriber',
            deviceName: deviceName || 'Device',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await reuseBatch.commit();

        console.log(`Reused existing family ${ownedFamilyId} for returning owner ${ownerKey} (device ${deviceId})`);
        return { familyId: ownedFamilyId };
      }
    }
  }

  // Determine max children based on tier. Trial gets the same limit as Family
  // (full access during trial, matching SubscriptionTier.childDeviceLimit on
  // the client) — Individual and a real Solo-turned-family edge case get 1.
  const maxChildren = (subscriptionTier === 'family' || subscriptionTier === 'trial') ? 5 : 1;

  // Create new family
  const familyRef = db.collection('families').doc();
  const familyId = familyRef.id;

  const familyData: FirebaseFirestore.DocumentData = {
    subscriberDeviceId: deviceId,
    subscriptionTier,
    subscriptionStatus,
    parents: [deviceId],
    maxChildren,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (ownerKey) {
    familyData.ownerKey = ownerKey;
  }

  // Create device record
  const deviceData = {
    familyId,
    deviceType: 'parent',
    role: 'subscriber',
    deviceName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Batch write
  const batch = db.batch();
  batch.set(familyRef, familyData);
  batch.set(db.collection('devices').doc(deviceId), deviceData);
  if (ownerKey) {
    // Owner-key lookup index: "which family does this iCloud identity own?"
    // Lets a future reinstalled parent device recover this family via
    // lookupFamilyByOwner without needing the old (by-then-gone) deviceId.
    batch.set(db.collection('familyOwners').doc(ownerKey), { familyId });
  }
  await batch.commit();

  console.log(`Created family ${familyId} for device ${deviceId}${ownerKey ? ' (owner-tagged)' : ''}`);

  return { familyId };
});

interface LookupFamilyByOwnerData {
  ownerKey: string;
}

/**
 * Look up the family owned by a given iCloud identity (owner key). Used by a
 * parent device that has lost its local familyId pointer (e.g. after a
 * reinstall, which deliberately wipes the parent deviceID — see
 * DeviceModeManager "PHASE 3") to recover its existing family instead of
 * creating a new, disconnected one that orphans already-paired children.
 *
 * Read-only and side-effect-free. A caller that gets a non-null familyId back
 * must still call claimFamilyOwnership to attach its (new) device ID to it.
 */
export const lookupFamilyByOwner = functions.https.onCall(
  async (data: LookupFamilyByOwnerData, context) => {
    const { ownerKey } = data;

    if (!ownerKey) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing ownerKey');
    }

    const ownerDoc = await db.collection('familyOwners').doc(ownerKey).get();
    if (!ownerDoc.exists) {
      return { familyId: null };
    }

    return { familyId: ownerDoc.data()?.familyId ?? null };
  }
);

interface ClaimFamilyOwnershipData {
  familyId: string;
  ownerKey: string;
  deviceId: string;
  deviceName?: string;
}

/**
 * Attach a device to a family under a given iCloud owner key. Idempotent and
 * dual-purpose:
 *  - Backfill: called silently at launch by a parent device that already
 *    knows its familyId, to tag a pre-existing (pre-ownerKey) family for the
 *    first time. deviceId is typically already a member of `parents`, so
 *    this is usually a same-owner, no-new-device no-op.
 *  - Recovery: called after lookupFamilyByOwner finds a family for a NEW
 *    device ID (post-reinstall), to re-adopt that device into the family.
 *
 * Once a family has an owner key, only that same owner may claim it again —
 * this stops a stray/incorrect key from hijacking someone else's family.
 * Adding a genuinely new parent device is still capped at 2, matching the
 * co-parent-join limit enforced in validateCoParentJoin (pairing.ts).
 */
export const claimFamilyOwnership = functions.https.onCall(
  async (data: ClaimFamilyOwnershipData, context) => {
    const { familyId, ownerKey, deviceId, deviceName } = data;

    if (!familyId || !ownerKey || !deviceId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    const familyRef = db.collection('families').doc(familyId);
    const familyDoc = await familyRef.get();

    if (!familyDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Family not found');
    }

    const family = familyDoc.data()!;

    if (family.ownerKey && family.ownerKey !== ownerKey) {
      throw new functions.https.HttpsError('permission-denied', 'This family has a different owner');
    }

    const parents: string[] = family.parents || [];
    const isNewParentDevice = !parents.includes(deviceId);

    // Only the verified owner reaches this point (ownerKey guard above); a genuine
    // co-parent joins through validateCoParentJoin instead, under their own iCloud
    // account. So a "new" device here is always the owner returning on a fresh
    // install — and a parent deviceId is deliberately ephemeral (wiped on reinstall,
    // see DeviceModeManager "PHASE 3"). Appending each time would burn a permanent
    // parent slot per reinstall and lock the owner out of their own family on the
    // second one. Rotate the owner's own slot instead: drop the stale subscriber
    // device, keep any genuine co-parent, and hand the subscriber role to this device.
    const previousSubscriberId: string | undefined = family.subscriberDeviceId;
    const parentsWithoutStaleOwner = parents.filter((p) => p !== previousSubscriberId);

    if (isNewParentDevice && parentsWithoutStaleOwner.length >= 2) {
      throw new functions.https.HttpsError('resource-exhausted', 'Maximum number of parent devices reached for this family');
    }

    const isNewOwnerLink = !family.ownerKey;

    const familyUpdates: { [key: string]: unknown } = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (isNewOwnerLink) {
      familyUpdates.ownerKey = ownerKey;
    }
    if (isNewParentDevice) {
      familyUpdates.parents = [...parentsWithoutStaleOwner, deviceId];
      familyUpdates.subscriberDeviceId = deviceId;
    }

    const batch = db.batch();
    batch.update(familyRef, familyUpdates);
    if (isNewOwnerLink) {
      batch.set(db.collection('familyOwners').doc(ownerKey), { familyId });
    }
    batch.set(
      db.collection('devices').doc(deviceId),
      {
        familyId,
        deviceType: 'parent',
        role: 'subscriber',
        deviceName: deviceName || 'Device',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await batch.commit();

    console.log(`Claimed family ${familyId} for device ${deviceId} under owner ${ownerKey}`);

    return { success: true, familyId };
  }
);

interface UpdateFamilySubscriptionData {
  familyId: string;
  subscriptionTier: 'trial' | 'solo' | 'individual' | 'family';
  maxChildren: number;
}

/**
 * Update family's subscription tier (called when parent upgrades/downgrades)
 * Updates maxChildren limit to match new tier
 */
export const updateFamilySubscription = functions.https.onCall(
  async (data: UpdateFamilySubscriptionData, context) => {
    const { familyId, subscriptionTier, maxChildren } = data;

    // Validate required fields
    if (!familyId || !subscriptionTier || maxChildren === undefined) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    // Verify family exists
    const familyRef = db.collection('families').doc(familyId);
    const familyDoc = await familyRef.get();

    if (!familyDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Family not found');
    }

    // Update family subscription
    await familyRef.update({
      subscriptionTier,
      maxChildren,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Updated family ${familyId} subscription: tier=${subscriptionTier}, maxChildren=${maxChildren}`);

    return { success: true };
  }
);

interface RemoveChildData {
  childDeviceId: string;
  // Optional. If supplied, used directly. Otherwise we look it up from the
  // device's `families/*/children` membership via the device record.
  familyId?: string;
}

/**
 * Remove a child device from its family. Idempotent: succeeds even if the
 * child is already absent (so retries from either parent-side or child-side
 * unpair flows are safe).
 *
 * Deletes:
 *   - families/{familyId}/children/{childDeviceId}  (decrements the device count)
 *   - devices/{childDeviceId}                       (top-level device record)
 *
 * Either the parent OR the child device may invoke this:
 *   - On parent-side unpair: parent calls with its own familyId.
 *   - On child-side unpair: child calls with childDeviceId; we resolve the
 *     family from the devices/{childDeviceId} record.
 */
export const removeChildFromFamily = functions.https.onCall(
  async (data: RemoveChildData, context) => {
    const { childDeviceId } = data;
    let { familyId } = data;

    if (!childDeviceId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing childDeviceId');
    }

    // Resolve familyId from the child's device record if not supplied.
    if (!familyId) {
      const deviceDoc = await db.collection('devices').doc(childDeviceId).get();
      if (!deviceDoc.exists) {
        // Already absent — treat as success for idempotency.
        console.log(`removeChildFromFamily: device ${childDeviceId} not found, treating as already removed`);
        return { success: true, alreadyRemoved: true };
      }
      familyId = deviceDoc.data()?.familyId;
      if (!familyId) {
        console.log(`removeChildFromFamily: device ${childDeviceId} has no familyId, treating as already removed`);
        return { success: true, alreadyRemoved: true };
      }
    }

    const childRef = db.collection(`families/${familyId}/children`).doc(childDeviceId);
    const deviceRef = db.collection('devices').doc(childDeviceId);

    const batch = db.batch();
    batch.delete(childRef);
    batch.delete(deviceRef);
    await batch.commit();

    console.log(`Removed child ${childDeviceId} from family ${familyId}`);

    return { success: true, familyId };
  }
);
