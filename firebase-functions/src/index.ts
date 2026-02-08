/**
 * Firebase Cloud Functions for ScreenTimeRewards
 * Handles subscription abuse prevention via server-side validation
 */

import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp();

// Export all functions
export { createFamily, updateFamilySubscription } from './family';
export { createPairingToken, validateChildPairing, validateCoParentJoin } from './pairing';
export { verifyFamilySubscription, updateSubscriptionStatus, checkParentSubscription, markFamilyExpired } from './subscription';
export { revenueCatWebhook } from './webhooks';
