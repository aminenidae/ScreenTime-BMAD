/**
 * Subscription verification functions
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

interface VerifySubscriptionData {
  familyId: string;
  deviceId: string;
}

interface UpdateSubscriptionData {
  familyId: string;
  subscriptionTier: string;
  subscriptionStatus: string;
  expiryDate?: number;
}

/**
 * Verify a family's subscription is still valid
 * Called periodically by child devices
 */
export const verifyFamilySubscription = functions.https.onCall(async (data: VerifySubscriptionData, context) => {
  const { familyId, deviceId } = data;

  if (!familyId || !deviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Get family document
  const familyDoc = await db.collection('families').doc(familyId).get();
  if (!familyDoc.exists) {
    return { isValid: false, reason: 'family_not_found' };
  }

  const family = familyDoc.data()!;

  // Check subscription status
  const validStatuses = ['active', 'trial', 'grace'];
  const isValid = validStatuses.includes(family.subscriptionStatus);

  // Update last verification timestamp for the device
  if (deviceId) {
    const deviceRef = db.collection('devices').doc(deviceId);
    await deviceRef.update({
      lastVerification: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {
      // Device might not exist yet - ignore
    });
  }

  return {
    isValid,
    subscriptionStatus: family.subscriptionStatus,
    subscriptionTier: family.subscriptionTier,
    expiryDate: family.expiryDate?.toMillis() || null,
  };
});

/**
 * Update a family's subscription status
 * Called by the app after subscription changes or by webhook
 */
export const updateSubscriptionStatus = functions.https.onCall(async (data: UpdateSubscriptionData, context) => {
  const { familyId, subscriptionTier, subscriptionStatus, expiryDate } = data;

  if (!familyId || !subscriptionTier || !subscriptionStatus) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  const familyRef = db.collection('families').doc(familyId);
  const familyDoc = await familyRef.get();

  if (!familyDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Family not found');
  }

  // Determine max children based on new tier
  const maxChildren = subscriptionTier === 'family' ? 5 : 1;

  const updateData: Record<string, any> = {
    subscriptionTier,
    subscriptionStatus,
    maxChildren,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (expiryDate) {
    updateData.expiryDate = admin.firestore.Timestamp.fromMillis(expiryDate);
  }

  await familyRef.update(updateData);

  console.log(`Updated family ${familyId} subscription: ${subscriptionTier}/${subscriptionStatus}`);

  return { success: true };
});

/**
 * Check if a parent device has an active subscription
 * Used by child devices before pairing to ensure parent can accept children
 */
interface CheckParentSubscriptionData {
  parentDeviceId: string;
}

export const checkParentSubscription = functions.https.onCall(async (data: CheckParentSubscriptionData, context) => {
  const { parentDeviceId } = data;

  if (!parentDeviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing parentDeviceId');
  }

  // Look up the device to find its family
  const deviceDoc = await db.collection('devices').doc(parentDeviceId).get();

  if (!deviceDoc.exists) {
    return {
      isValid: false,
      reason: 'parent_not_found',
      subscriptionTier: null,
      subscriptionStatus: null
    };
  }

  const device = deviceDoc.data()!;
  const familyId = device.familyId;

  if (!familyId) {
    return {
      isValid: false,
      reason: 'no_family',
      subscriptionTier: null,
      subscriptionStatus: null
    };
  }

  // Get family subscription status
  const familyDoc = await db.collection('families').doc(familyId).get();

  if (!familyDoc.exists) {
    return {
      isValid: false,
      reason: 'family_not_found',
      subscriptionTier: null,
      subscriptionStatus: null
    };
  }

  const family = familyDoc.data()!;
  const subscriptionTier = family.subscriptionTier || 'trial';
  const subscriptionStatus = family.subscriptionStatus || 'expired';

  // Solo subscription cannot have children
  if (subscriptionTier === 'solo') {
    return {
      isValid: false,
      reason: 'solo_subscription',
      subscriptionTier,
      subscriptionStatus
    };
  }

  // Trial parents CAN pair with children - pairing is allowed during trial
  // Access is determined by subscription status AFTER trial ends
  // Only block expired subscriptions (trial ended without subscribing)
  const validStatuses = ['active', 'grace', 'trial'];
  const isValid = validStatuses.includes(subscriptionStatus);

  if (!isValid) {
    return {
      isValid: false,
      reason: 'subscription_expired',
      subscriptionTier,
      subscriptionStatus
    };
  }

  // Check child limit
  const currentChildren = family.childCount || 0;
  const maxChildren = family.maxChildren || (subscriptionTier === 'family' ? 5 : 1);

  if (currentChildren >= maxChildren) {
    return {
      isValid: false,
      reason: 'child_limit_reached',
      subscriptionTier,
      subscriptionStatus,
      currentChildren,
      maxChildren
    };
  }

  return {
    isValid: true,
    subscriptionTier,
    subscriptionStatus,
    currentChildren,
    maxChildren
  };
});

/**
 * Mark a family's subscription as expired
 * Called when parent downgrades to Solo or subscription expires
 */
interface MarkFamilyExpiredData {
  familyId: string;
}

export const markFamilyExpired = functions.https.onCall(async (data: MarkFamilyExpiredData, context) => {
  const { familyId } = data;

  if (!familyId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing familyId');
  }

  const familyRef = db.collection('families').doc(familyId);
  const familyDoc = await familyRef.get();

  if (!familyDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Family not found');
  }

  await familyRef.update({
    subscriptionStatus: 'expired',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`Marked family ${familyId} as expired`);

  return { success: true };
});
