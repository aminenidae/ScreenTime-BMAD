# Subscription Restructure & Abuse Prevention

## Problem
1. Family plan (5 child devices) can be shared with friends from different households
2. No server-side validation that devices belong to the same family
3. Current model has subscription on child device, limiting parent control

## Solution
Two subscription paths + Firebase server-side validation for abuse prevention.

---

## Subscription Tiers

| Tier | Price | Devices | Where Subscription Lives |
|------|-------|---------|--------------------------|
| **Solo** | $6.99/mo or $49.99/yr | 1 child device only | Child device |
| **Individual** | $9.99/mo or $59.99/yr | 1 child + 2 parents | Parent device |
| **Family** | $12.49/mo or $74.99/yr | 5 children + 2 parents each | Parent device |

---

## Two Subscription Paths

### Path 1: Solo (Single Device)
**Use case:** Parent monitors child on the SAME device (no remote monitoring)

```
Child Device Onboarding (parent setting up):
+-----------------------------------------------------+
| "How would you like to monitor your child?"         |
|                                                     |
| [On this device only]   <- SOLO PATH                |
| [From my own device]    <- FAMILY PATH              |
+-----------------------------------------------------+
         |
         v
   Paywall (Solo tier)
         |
         v
   Permissions -> App Selection -> Avatar -> Done
         |
         v
   Parent manages via PIN-protected section on child device
   NO pairing option available
```

### Path 2: Family (Multi-Device)
**Use case:** Parent monitors remotely from their own device

**Child Device:**
```
Onboarding -> Setup Question -> Permissions -> App Selection -> Avatar -> Done
                                                                    |
                                                         14-day trial starts
                                                                    |
                                                    Prompts to pair with parent
```

**Parent Device:**
```
Install -> Parent Mode -> Paywall (Individual/Family) -> Subscribe -> Generate QR
```

**Pairing:**
```
Child scans QR -> Firebase validates -> CloudKit pairing completes
```

---

## Co-Parent Support (One Pays, Other Joins Free)

**Scenario:** Mom and Dad (different iCloud accounts) both want to monitor their children.

### How It Works
1. **First parent (subscriber)** creates family and subscribes
2. **Second parent (co-parent)** joins existing family without paying
3. **Children** validate against family subscription, not specific parent

### Co-Parent Flow

**First Parent (Subscriber):**
```
Install -> Parent Mode -> Paywall -> Subscribe -> Creates Family
                                                    |
                              Can generate: Child QR OR Co-Parent QR
```

**Second Parent (Co-Parent):**
```
Install -> Parent Mode -> "Join Existing Family" -> Scan Co-Parent QR -> Done (no paywall)
```

### Firebase Family Structure
```
/families/{familyId}
  - subscriberDeviceId: string       // Who pays (mom or dad)
  - subscriptionTier: "individual" | "family"
  - subscriptionStatus: "active" | "trial" | "grace" | "expired"
  - parents: [deviceId1, deviceId2]  // Up to 2 parents
  - maxChildren: 1 | 5               // Based on tier

/families/{familyId}/children/{childDeviceId}
  - deviceName: string
  - pairedAt: timestamp
  - isActive: boolean
```

---

## Firebase Validation (Abuse Prevention)

### Why Firebase?
- Server-side enforcement of device limits
- Single-use pairing tokens (QR can't be shared)
- Subscription status verification
- Family membership tracking

### Firestore Collections

```
/families/{familyId}
  - subscriberDeviceId: string
  - subscriptionTier: string
  - subscriptionStatus: string
  - parents: array<string>
  - maxChildren: number

/families/{familyId}/children/{childDeviceId}
  - deviceName: string
  - pairedAt: timestamp
  - isActive: boolean

/pairingTokens/{tokenId}
  - familyId: string
  - tokenType: "child" | "coparent"
  - token: string (256-bit random)
  - expiresAt: timestamp (10 minutes)
  - maxUses: 1
  - usedCount: number
  - cloudKitShareURL: string (for child tokens)

/devices/{deviceId}
  - familyId: string | null
  - deviceType: "parent" | "child"
  - role: "subscriber" | "coparent" | "child" | "solo"
```

### Cloud Functions

| Function | Purpose |
|----------|---------|
| `createFamily` | First parent subscribes, creates family |
| `createPairingToken` | Parent generates child or co-parent QR |
| `validateChildPairing` | Child validates token before CloudKit |
| `validateCoParentJoin` | Co-parent validates token to join family |
| `verifyFamilySubscription` | Child/co-parent periodic verification |
| `revenueCatWebhook` | Subscription status updates |

### Security Features
1. **Single-use tokens** - QR can only be used once
2. **10-minute expiry** - Token expires quickly
3. **Server-side device limits** - Enforced in Cloud Functions
4. **Periodic re-verification** - Child checks subscription daily

---

## Child Trial & Expiry Logic

### Timeline
```
Day 0:  Child installs, 14-day trial starts
        Gentle prompt: "Connect with a parent for full access"

Day 7:  Notification: "7 days left! Ask your parent to set up"

Day 11: Urgent prompt: "3 days left to connect"

Day 14: Trial expires
        If paired with subscribed parent -> Full access continues
        If NOT paired -> Limited mode + "Ask parent to subscribe"
```

### Limited Mode (After Trial, Not Paired)
- Can view basic stats (engagement hook)
- Core features locked
- Persistent prompt to pair with parent

---

## QR Payloads

### Child Pairing QR
```swift
struct ChildPairingPayload: Codable {
    let version: Int = 2
    let tokenId: String
    let validationToken: String
    let shareURL: String           // CloudKit share URL
    let parentDeviceID: String
    let familyId: String
    let expiresAt: Date
}
```

### Co-Parent QR
```swift
struct CoParentPayload: Codable {
    let version: Int = 1
    let tokenId: String
    let validationToken: String
    let familyId: String
    let familyName: String
    let expiresAt: Date
}
```

---

## Files to Modify

### Child Onboarding
| File | Changes |
|------|---------|
| `Views/Onboarding/OnboardingCoordinator.swift` | Add branching screen, conditional paywall |
| `Views/Onboarding/SetupPathSelectionView.swift` | **NEW** - Solo vs Family choice |
| `Views/Onboarding/Screens/Screen6_TrialPaywallView.swift` | Only show for Solo path |

### Parent Onboarding
| File | Changes |
|------|---------|
| `Views/ParentMode/ParentOnboardingFlow.swift` | Add paywall screen, "Join Family" option |
| `Views/ParentMode/ParentPaywallView.swift` | **NEW** - Paywall for parent device |
| `Views/ParentMode/JoinFamilyView.swift` | **NEW** - Co-parent QR scan |

### Pairing
| File | Changes |
|------|---------|
| `Services/DevicePairingService.swift` | Add Firebase validation, co-parent support |
| `Views/ParentMode/ParentPairingView.swift` | Add co-parent QR generation |
| `Views/ChildMode/ChildPairingView.swift` | Add Firebase validation before CloudKit |

### Firebase Integration
| File | Changes |
|------|---------|
| `Services/FirebaseValidationService.swift` | **NEW** - All Firebase logic |
| `AppDelegate.swift` | Initialize Firebase |

### Subscription
| File | Changes |
|------|---------|
| `Services/SubscriptionManager.swift` | Add Solo tier, family subscription logic |
| `Models/SubscriptionTier.swift` | Add Solo case |
| `Services/ChildBackgroundSyncService.swift` | Add periodic subscription verification |

### RevenueCat
| File | Changes |
|------|---------|
| `Config/RevenueCatConfig.swift` | Add Solo product IDs |
| RevenueCat Dashboard | Create Solo products |

---

## Firebase Cloud Functions

### functions/src/index.ts
```typescript
// Main exports
export { createFamily } from './family';
export { createPairingToken, validateChildPairing, validateCoParentJoin } from './pairing';
export { verifyFamilySubscription } from './subscription';
export { revenueCatWebhook } from './webhooks';
```

### Key Function: validateChildPairing
```typescript
export const validateChildPairing = functions.https.onCall(async (data, context) => {
  const { tokenId, validationToken, childDeviceId } = data;

  // 1. Get token document
  const tokenDoc = await db.collection('pairingTokens').doc(tokenId).get();
  if (!tokenDoc.exists) throw new Error('Invalid token');

  const token = tokenDoc.data();

  // 2. Validate token
  if (token.token !== validationToken) throw new Error('Token mismatch');
  if (token.expiresAt.toDate() < new Date()) throw new Error('Token expired');
  if (token.usedCount >= token.maxUses) throw new Error('Token already used');

  // 3. Check family subscription
  const familyDoc = await db.collection('families').doc(token.familyId).get();
  const family = familyDoc.data();

  if (family.subscriptionStatus === 'expired') throw new Error('Subscription expired');

  // 4. Check device limit
  const childrenSnapshot = await db.collection(`families/${token.familyId}/children`).get();
  if (childrenSnapshot.size >= family.maxChildren) throw new Error('Device limit reached');

  // 5. Mark token as used
  await tokenDoc.ref.update({ usedCount: token.usedCount + 1 });

  // 6. Register child device
  await db.collection(`families/${token.familyId}/children`).doc(childDeviceId).set({
    deviceName: data.deviceName,
    pairedAt: admin.firestore.FieldValue.serverTimestamp(),
    isActive: true
  });

  return { success: true, familyId: token.familyId };
});
```

---

## RevenueCat Webhook

Configure in RevenueCat dashboard:
```
URL: https://us-central1-{project}.cloudfunctions.net/revenueCatWebhook
Events: INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, BILLING_ISSUE
```

Updates family subscription status in Firestore.

---

## Migration Strategy

### Phase 1: Deploy (Backward Compatible)
- New users get new flow (Solo/Family choice)
- Existing child subscriptions continue working
- Existing pairings continue working (no Firebase validation)

### Phase 2: Encourage Migration
- Prompt existing users: "Upgrade to Family plan for remote monitoring"
- Track adoption metrics

### Phase 3: Full Enforcement (Future)
- All new pairings require Firebase validation
- Legacy pairings grandfathered

---

## Implementation Order

### Stage 1: Firebase Setup
1. [ ] Create Firebase project
2. [ ] Set up Firestore collections
3. [ ] Deploy Cloud Functions (pairing, webhooks)
4. [ ] Configure RevenueCat webhook
5. [ ] Create `FirebaseValidationService.swift`

### Stage 2: Subscription Changes
6. [ ] Add Solo tier to RevenueCat
7. [ ] Update `SubscriptionTier.swift` with Solo case
8. [ ] Update `SubscriptionManager.swift` for family logic

### Stage 3: Child Onboarding
9. [ ] Create `SetupPathSelectionView.swift` (Solo vs Family)
10. [ ] Update `OnboardingCoordinator.swift` for branching
11. [ ] Add 14-day trial logic for Family path
12. [ ] Add trial expiry prompts

### Stage 4: Parent Onboarding
13. [ ] Create `ParentPaywallView.swift`
14. [ ] Create `JoinFamilyView.swift` (co-parent scan)
15. [ ] Update parent onboarding flow

### Stage 5: Pairing Updates
16. [ ] Update `DevicePairingService.swift` for Firebase validation
17. [ ] Add co-parent QR generation to `ParentPairingView.swift`
18. [ ] Update `ChildPairingView.swift` for Firebase validation

### Stage 6: Periodic Verification
19. [ ] Add subscription verification to `ChildBackgroundSyncService.swift`
20. [ ] Add limited mode UI for expired/unpaired children

### Stage 7: Testing & Polish
21. [ ] Test Solo flow end-to-end
22. [ ] Test Family flow end-to-end
23. [ ] Test co-parent flow
24. [ ] Test abuse scenarios (shared QR, device limits)
25. [ ] Test migration path for existing users

---

## Cost Estimate

For 10,000 active families:
- Cloud Functions: ~$0.04/month
- Firestore: ~$0.90/month
- **Total: ~$1-2/month**
