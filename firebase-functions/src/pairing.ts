/**
 * Pairing token functions for child and co-parent pairing
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

const db = admin.firestore();

// Token expiration in minutes
const TOKEN_EXPIRATION_MINUTES = 10;

interface CreateTokenData {
  familyId: string;
  tokenType: 'child' | 'coparent';
  deviceId: string;
  cloudKitShareURL?: string;
}

interface ValidateChildData {
  tokenId: string;
  validationToken: string;
  childDeviceId: string;
  deviceName: string;
}

interface ValidateCoParentData {
  tokenId: string;
  validationToken: string;
  parentDeviceId: string;
  deviceName: string;
}

/**
 * Create a single-use pairing token
 * Called by parent when generating QR code
 */
export const createPairingToken = functions.https.onCall(async (data: CreateTokenData, context) => {
  const { familyId, tokenType, deviceId, cloudKitShareURL } = data;

  if (!familyId || !tokenType || !deviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Verify family exists and device is a parent
  const familyDoc = await db.collection('families').doc(familyId).get();
  if (!familyDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Family not found');
  }

  const family = familyDoc.data()!;
  if (!family.parents.includes(deviceId)) {
    throw new functions.https.HttpsError('permission-denied', 'Only parents can create pairing tokens');
  }

  // Check subscription is active
  if (family.subscriptionStatus === 'expired') {
    throw new functions.https.HttpsError('permission-denied', 'Subscription expired');
  }

  // Generate cryptographically secure token
  const validationToken = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + TOKEN_EXPIRATION_MINUTES * 60 * 1000);

  // Create token document
  const tokenRef = db.collection('pairingTokens').doc();
  const tokenData = {
    familyId,
    tokenType,
    token: validationToken,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    maxUses: 1,
    usedCount: 0,
    createdBy: deviceId,
    cloudKitShareURL: cloudKitShareURL || null,
    isRevoked: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await tokenRef.set(tokenData);

  console.log(`Created ${tokenType} token ${tokenRef.id} for family ${familyId}`);

  return {
    tokenId: tokenRef.id,
    validationToken,
    expiresAt: expiresAt.getTime(),
  };
});

/**
 * Validate and consume a child pairing token
 * Called by child device before accepting CloudKit share
 */
export const validateChildPairing = functions.https.onCall(async (data: ValidateChildData, context) => {
  const { tokenId, validationToken, childDeviceId, deviceName } = data;

  if (!tokenId || !validationToken || !childDeviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Get token document
  const tokenRef = db.collection('pairingTokens').doc(tokenId);
  const tokenDoc = await tokenRef.get();

  if (!tokenDoc.exists) {
    return { success: false, errorCode: 'invalid_token' };
  }

  const token = tokenDoc.data()!;

  // Validate token
  if (token.token !== validationToken) {
    return { success: false, errorCode: 'invalid_token' };
  }

  if (token.isRevoked) {
    return { success: false, errorCode: 'invalid_token' };
  }

  if (token.expiresAt.toDate() < new Date()) {
    return { success: false, errorCode: 'token_expired' };
  }

  if (token.usedCount >= token.maxUses) {
    return { success: false, errorCode: 'token_used' };
  }

  if (token.tokenType !== 'child') {
    return { success: false, errorCode: 'invalid_token' };
  }

  // Get family and check subscription
  const familyDoc = await db.collection('families').doc(token.familyId).get();
  if (!familyDoc.exists) {
    return { success: false, errorCode: 'invalid_token' };
  }

  const family = familyDoc.data()!;

  if (family.subscriptionStatus === 'expired') {
    return { success: false, errorCode: 'subscription_expired' };
  }

  // Check if child device is same as any parent (same account pairing)
  if (family.parents.includes(childDeviceId)) {
    return { success: false, errorCode: 'same_account' };
  }

  // Check device limit
  const childrenSnapshot = await db.collection(`families/${token.familyId}/children`).get();
  if (childrenSnapshot.size >= family.maxChildren) {
    return { success: false, errorCode: 'device_limit' };
  }

  // Check if child already exists in this family
  const existingChild = await db.collection(`families/${token.familyId}/children`).doc(childDeviceId).get();
  if (existingChild.exists) {
    // Already paired - allow re-pairing
    console.log(`Child ${childDeviceId} already paired with family ${token.familyId}`);
  }

  // All validations passed - consume token and register child
  const batch = db.batch();

  // Mark token as used
  batch.update(tokenRef, {
    usedCount: admin.firestore.FieldValue.increment(1),
  });

  // Register child device
  batch.set(db.collection(`families/${token.familyId}/children`).doc(childDeviceId), {
    deviceName,
    pairedAt: admin.firestore.FieldValue.serverTimestamp(),
    isActive: true,
  });

  // Update device record
  batch.set(db.collection('devices').doc(childDeviceId), {
    familyId: token.familyId,
    deviceType: 'child',
    role: 'child',
    deviceName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  console.log(`Child ${childDeviceId} paired with family ${token.familyId}`);

  return {
    success: true,
    familyId: token.familyId,
    cloudKitShareURL: token.cloudKitShareURL,
  };
});

/**
 * Validate and consume a co-parent token
 * Called by second parent device when joining family
 */
export const validateCoParentJoin = functions.https.onCall(async (data: ValidateCoParentData, context) => {
  const { tokenId, validationToken, parentDeviceId, deviceName } = data;

  if (!tokenId || !validationToken || !parentDeviceId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Get token document
  const tokenRef = db.collection('pairingTokens').doc(tokenId);
  const tokenDoc = await tokenRef.get();

  if (!tokenDoc.exists) {
    return { success: false, errorCode: 'invalid_token' };
  }

  const token = tokenDoc.data()!;

  // Validate token
  if (token.token !== validationToken) {
    return { success: false, errorCode: 'invalid_token' };
  }

  if (token.isRevoked) {
    return { success: false, errorCode: 'invalid_token' };
  }

  if (token.expiresAt.toDate() < new Date()) {
    return { success: false, errorCode: 'token_expired' };
  }

  if (token.usedCount >= token.maxUses) {
    return { success: false, errorCode: 'token_used' };
  }

  if (token.tokenType !== 'coparent') {
    return { success: false, errorCode: 'invalid_token' };
  }

  // Get family
  const familyRef = db.collection('families').doc(token.familyId);
  const familyDoc = await familyRef.get();
  if (!familyDoc.exists) {
    return { success: false, errorCode: 'invalid_token' };
  }

  const family = familyDoc.data()!;

  // Check subscription
  if (family.subscriptionStatus === 'expired') {
    return { success: false, errorCode: 'subscription_expired' };
  }

  // Check parent limit (max 2 parents)
  if (family.parents.length >= 2) {
    return { success: false, errorCode: 'parent_limit' };
  }

  // Check if this device is already a parent
  if (family.parents.includes(parentDeviceId)) {
    return { success: false, errorCode: 'same_account' };
  }

  // All validations passed - consume token and add co-parent
  const batch = db.batch();

  // Mark token as used
  batch.update(tokenRef, {
    usedCount: admin.firestore.FieldValue.increment(1),
  });

  // Add parent to family
  batch.update(familyRef, {
    parents: admin.firestore.FieldValue.arrayUnion(parentDeviceId),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Create device record
  batch.set(db.collection('devices').doc(parentDeviceId), {
    familyId: token.familyId,
    deviceType: 'parent',
    role: 'coparent',
    deviceName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  console.log(`Co-parent ${parentDeviceId} joined family ${token.familyId}`);

  return {
    success: true,
    familyId: token.familyId,
  };
});
