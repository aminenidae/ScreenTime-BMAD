# Plan — Make family ownership survive a parent's device change

**Date**: 2026-07-24
**Status**: 📋 Plan for review — no code written. Requires CEO go-ahead before implementation.
**Area**: pairing / Firebase family records / CloudKit identity — the highest-risk plumbing in the app.

---

## The problem in one paragraph

A parent's "family" — the record that holds which children are paired and what plan they're on — is filed on the server under the **parent's device ID**. That device ID is deliberately **not durable**: on a parent device it lives in ordinary app storage and is wiped on reinstall. So when a parent reinstalls or replaces their phone, the app can no longer find their family, creates a **new empty one**, and the already-paired children are left pointing at the old record. The subscription itself is safe (Apple restores that); what breaks is the **link between the parent and their children's devices** — which is the product.

---

## Verified findings (evidence)

| # | Finding | Evidence |
|---|---|---|
| 1 | The family is keyed **only** by device ID. The `devices` collection uses deviceId as the document ID; there is no other lookup key. | `firebase-functions/src/family.ts:30,65` |
| 2 | The family record stores `subscriberDeviceId` and `parents: [deviceId]` — device IDs, not a person. | `family.ts:44,47` |
| 3 | **The server is already idempotent by device ID** — if the device already has a family, `createFamily` returns the existing one instead of creating a duplicate. So recovery works *whenever the device ID survives*. | `family.ts:29-34` |
| 4 | **The parent's device ID deliberately does not survive.** Child devices store it in the Keychain "to prevent orphaned zones"; parent devices use UserDefaults only, and the code *actively deletes* any Keychain copy to force "reinstall = fresh start, must re-pair". | `DeviceModeManager.swift:28-30, 66-90` |
| 5 | The client-side pointer to the family (`firebase_family_id`) is in UserDefaults — erased on delete/reinstall. | `FirebaseValidationService.swift:235,255-257` |
| 6 | The iCloud identity we'd key on is **already fetched in production, with no sign-in prompt**, to route parent dashboard queries. | `ParentRemoteViewModel.swift:1949` |

### The key insight (this changes the framing)

This is **not a bug** — it's a deliberate decision (labelled "PHASE 3" in the code): *"Parent device: Use UserDefaults only (reinstall = fresh start, must re-pair)."*

But note the asymmetry it creates. The **child** device was given durable Keychain storage *explicitly* "to prevent orphaned zones" — the exact failure we're discussing. The **parent** device, which actually *owns* the family, was left ephemeral. So the side that matters most is the side that forgets.

The server was even built to self-heal (finding #3) — that recovery path just never fires for parents, because their key is gone.

**So the fix is not to reverse the "fresh start" decision.** It's to give the family a *second, durable owner key* so the record is recoverable even when the device ID intentionally resets. The device can stay disposable; the family stops being disposable with it.

---

## Goal / non-goals

**Goal:** a parent who reinstalls or gets a new phone signs into iCloud (as they already do during device setup) and gets their existing family — and their paired children — back automatically, with no screens, no login, and no action from them.

**Non-goals (explicitly out of scope):**
- No account system, email, or password.
- No change to how subscriptions are purchased or restored (Apple already handles that).
- No change to the child device's identity model (it already works).
- Not reversing the parent "fresh start on reinstall" behaviour — the *device* can still reset.

---

## Design

Add a **durable owner key** to the family: the parent's iCloud user record ID (an opaque, per-app identifier — not an email, not an Apple ID, and different for the same person in any other app).

**Data changes (Firestore)**
- `families/{familyId}`: add `ownerKey` (string, indexed).
- New lookup collection `familyOwners/{ownerKey}` → `{ familyId }`, so "which family do I own?" is a single direct read.

**Server changes (`firebase-functions/src/family.ts`)**
- `createFamily`: accept an optional `ownerKey`; write it to the family and to `familyOwners`. Keep the existing device-ID idempotency untouched.
- New `lookupFamilyByOwner({ ownerKey })` → returns `familyId` or null.
- New `claimFamilyOwnership({ familyId, ownerKey, deviceId })` → attaches a new parent device ID to an existing family (the re-adoption step after a device change).

**App changes**
- Fetch the iCloud record name once at launch (already proven at `ParentRemoteViewModel.swift:1949`), cache it, and pass it on family creation.
- On launch, when the local family pointer is missing **before** creating a family: ask `lookupFamilyByOwner`. If a family comes back → `claimFamilyOwnership` with the new device ID, restore the local pointer, and re-attach to the existing CloudKit zone. Only create a new family if the lookup genuinely returns nothing.

**Migration (existing families)**
- Backfill lazily and safely: whenever an existing parent device launches with a known familyId **and** we can read its iCloud key, write `ownerKey` if absent. No data backfill script, no downtime — families become recoverable as parents open the app.
- Families whose parent never opens the app again stay as they are today (no worse than the status quo).

---

## Implementation order (each step verifiable on its own)

1. **Add the iCloud key accessor** (app) — fetch + cache the record name, with a clean "unavailable" result. *Verify: logs the same stable ID across relaunches; returns nil cleanly in airplane mode / signed out.* **Ships safely on its own — nothing reads it yet.**
2. **Server: accept and store `ownerKey`; add the lazy backfill on existing families.** *Verify: a newly created family has `ownerKey`; an existing family gains one on next launch. No client behaviour changes yet.*
3. **Server: add `lookupFamilyByOwner` + `claimFamilyOwnership`.** *Verify: called directly with a known key, returns the right family; claiming adds the new device to `parents`.*
4. **App: use the lookup in the "no local family" path**, ahead of creating a new one. *Verify (the real test): parent device with a paired child → delete and reinstall the app → family and child return with no re-pairing.*
5. **Re-attach the CloudKit zone** so the restored parent sees live child data, not just a family record. *Verify: child usage appears on the restored parent dashboard.*
6. **Harden:** what happens when the lookup fails mid-flight, when iCloud is unavailable, and when a family is claimed from two devices at once.

Steps 1–3 are invisible to users and can ship independently. Step 4 is the behavioural change and is the one that needs two-device testing.

---

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Spoofing** — the server trusts an `ownerKey` sent by the client, so someone who obtained another person's key could claim their family. | Medium | This is **not a regression**: today `createFamily` equally trusts a client-supplied `deviceId`, so the exposure is unchanged. The key is high-entropy and per-app. Proper fix is Firebase App Check / verified auth on these callables — worth doing, but as its own task, not bundled here. **Flagging explicitly rather than quietly accepting it.** |
| A parent **changes iCloud account** → looks like a new person. | Low | Same as today. The app already has orphan-zone detection. Falls back to current behaviour. |
| **iCloud unavailable / signed out** at launch. | Low | Lookup is skipped; behaviour is exactly today's. Never block family creation on it. |
| Two devices claim the same family simultaneously. | Low | Server-side transaction on `claimFamilyOwnership`; `parents` is a set, and the tier's parent-device limit still applies. |
| **Regression in pairing** — the app's most bug-prone area. | **High** | Steps 1–3 change nothing user-visible. Step 4 only alters the path that today *creates a new family* — i.e. the already-broken case. Existing, working pairings never enter this code path. |
| Duplicate/stale families created by past reinstalls already exist. | Low | Out of scope for this plan; worth a separate cleanup audit once ownerKey exists to identify them. |

---

## Test plan (two real devices — simulator can't prove this)

1. Fresh parent device → subscribe → pair a child → confirm child appears.
2. **Delete the app on the parent device. Reinstall.** → expect: family restored, child still paired, no re-pairing prompt, dashboard shows live data.
3. Repeat while signed out of iCloud → expect: today's behaviour, no crash, no duplicate family.
4. Existing (pre-migration) family: launch once → confirm `ownerKey` backfilled → then run test 2.
5. Confirm the child device is unaffected throughout.

---

## Open decisions for the CEO

1. **Do we also fix the spoofing gap now?** (App Check on the callables.) It's pre-existing, not caused by this change — but this plan makes the ownership key more valuable to steal. My recommendation: separate task, soon.
2. **Should a restored parent be *told*?** e.g. "Welcome back — we reconnected Sami's iPhone." My recommendation: yes, one quiet confirmation; silent magic reads as a bug when it's the only signal.
3. **Do we clean up orphaned families** created by past reinstalls? Needs its own audit; recommend after this ships.

---

## Estimate

Steps 1–3 are small and low-risk. Step 4–5 are the real work and need on-device validation with two phones. The dominant cost is **testing, not coding** — this is pairing plumbing, and the codebase history says it punishes shortcuts.
