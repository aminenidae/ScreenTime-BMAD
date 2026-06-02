/**
 * RevenueCat webhook handler
 * Receives subscription events and updates family subscription status
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

// RevenueCat webhook event types
type RevenueCatEventType =
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'NON_RENEWING_PURCHASE'
  | 'SUBSCRIPTION_PAUSED'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE';

interface RevenueCatWebhookEvent {
  event: {
    type: RevenueCatEventType;
    app_user_id: string;
    product_id: string;
    entitlement_ids: string[];
    period_type: string;
    purchased_at_ms: number;
    expiration_at_ms: number;
    environment: string;
    store: string;
    is_trial_conversion?: boolean;
  };
  api_version: string;
}

/**
 * Map RevenueCat event to subscription status
 */
function mapEventToStatus(eventType: RevenueCatEventType): string {
  switch (eventType) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
      return 'active';
    case 'BILLING_ISSUE':
      return 'grace';
    case 'EXPIRATION':
    case 'CANCELLATION':
      return 'expired';
    default:
      return 'active';
  }
}

/**
 * Determine subscription tier from product ID
 */
function getTierFromProductId(productId: string): string {
  if (productId.includes('family')) {
    return 'family';
  } else if (productId.includes('individual')) {
    return 'individual';
  } else if (productId.includes('solo')) {
    return 'solo';
  }
  return 'trial';
}

/**
 * RevenueCat webhook endpoint
 * Configure in RevenueCat dashboard:
 * URL: https://us-central1-{project}.cloudfunctions.net/revenueCatWebhook
 */
export const revenueCatWebhook = functions.https.onRequest(async (req, res) => {
  // Only accept POST requests
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  // Verify webhook authorization (optional but recommended)
  const authHeader = req.headers.authorization;
  const expectedToken = process.env.REVENUECAT_WEBHOOK_SECRET;

  if (expectedToken && authHeader !== `Bearer ${expectedToken}`) {
    console.warn('Unauthorized webhook request');
    res.status(401).send('Unauthorized');
    return;
  }

  try {
    const payload: RevenueCatWebhookEvent = req.body;
    const event = payload.event;

    console.log(`Received RevenueCat event: ${event.type} for user ${event.app_user_id}`);

    // The app_user_id is the device ID (set during RevenueCat login)
    const deviceId = event.app_user_id;

    // Find the family associated with this device
    const deviceDoc = await db.collection('devices').doc(deviceId).get();

    if (!deviceDoc.exists) {
      console.log(`Device ${deviceId} not found - might be a new subscriber`);
      // For new subscribers, the family will be created by the app
      res.status(200).json({ received: true, action: 'no_family_yet' });
      return;
    }

    const device = deviceDoc.data()!;
    const familyId = device.familyId;

    if (!familyId) {
      console.log(`Device ${deviceId} has no family - subscription event ignored`);
      res.status(200).json({ received: true, action: 'no_family' });
      return;
    }

    // Only process if device is the subscriber (not co-parent)
    if (device.role !== 'subscriber') {
      console.log(`Device ${deviceId} is not the subscriber - event ignored`);
      res.status(200).json({ received: true, action: 'not_subscriber' });
      return;
    }

    // Map event to subscription status
    const subscriptionStatus = mapEventToStatus(event.type);
    const subscriptionTier = getTierFromProductId(event.product_id);
    const maxChildren = subscriptionTier === 'family' ? 5 : 1;

    // Update family subscription status
    const familyRef = db.collection('families').doc(familyId);

    const updateData: Record<string, any> = {
      subscriptionStatus,
      subscriptionTier,
      maxChildren,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (event.expiration_at_ms) {
      updateData.expiryDate = admin.firestore.Timestamp.fromMillis(event.expiration_at_ms);
    }

    await familyRef.update(updateData);

    console.log(`Updated family ${familyId}: ${subscriptionTier}/${subscriptionStatus}`);

    // If subscription expired or downgraded, we might need to handle excess children
    if (subscriptionStatus === 'expired') {
      // Log for monitoring - actual enforcement happens on child verification
      const childrenSnapshot = await db.collection(`families/${familyId}/children`).get();
      console.log(`Family ${familyId} expired with ${childrenSnapshot.size} children`);
    }

    res.status(200).json({
      received: true,
      action: 'updated',
      familyId,
      status: subscriptionStatus,
    });

  } catch (error) {
    console.error('Error processing webhook:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
