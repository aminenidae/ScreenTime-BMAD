/**
 * Family management functions
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

interface CreateFamilyData {
  deviceId: string;
  deviceName: string;
  subscriptionTier: 'solo' | 'individual' | 'family';
  subscriptionStatus: string;
}

/**
 * Create a new family when a parent subscribes
 * Called after successful subscription purchase on parent device
 */
export const createFamily = functions.https.onCall(async (data: CreateFamilyData, context) => {
  const { deviceId, deviceName, subscriptionTier, subscriptionStatus } = data;

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

  // Determine max children based on tier
  const maxChildren = subscriptionTier === 'family' ? 5 : 1;

  // Create new family
  const familyRef = db.collection('families').doc();
  const familyId = familyRef.id;

  const familyData = {
    subscriberDeviceId: deviceId,
    subscriptionTier,
    subscriptionStatus,
    parents: [deviceId],
    maxChildren,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

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
  await batch.commit();

  console.log(`Created family ${familyId} for device ${deviceId}`);

  return { familyId };
});

interface UpdateFamilySubscriptionData {
  familyId: string;
  subscriptionTier: 'solo' | 'individual' | 'family';
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
