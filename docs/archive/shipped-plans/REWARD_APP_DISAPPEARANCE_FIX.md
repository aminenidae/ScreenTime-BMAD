# Fix: Reward Apps Disappearing on Child Devices

## Context

Reward apps disappear from the reward view and become completely unchecked from the picker on some kids' devices, but never on the parent's iPhone. The root cause is that `FamilyActivitySelection` silently fails to decode from JSON on child devices. When this happens, the entire app state cascade collapses: `familySelection`, `categoryAssignments`, and `rewardPointsAssignments` all become empty, so the UI shows zero reward apps and the picker shows nothing checked.

**Why child devices only:** On managed child devices (Family Sharing with parental Screen Time), Apple's opaque `ApplicationToken` encoding can be invalidated by parent-side Screen Time changes, iOS updates, or authorization context shifts. The parent's personal iPhone has stable token encoding with no external management forces.

**Key safety note:** The persisted app data (`persistedApps_v3`) actually survives the failure since the main reconciliation is guarded by `if !restoredSelection.applications.isEmpty`. But the in-memory state is fully empty, causing the UI to break.

## Files to Modify

1. **`ScreenTimeRewardsProject/ScreenTimeRewards/Services/ScreenTimeService.swift`** — persistence & restoration (lines 246-460)
2. **`ScreenTimeRewardsProject/ScreenTimeRewards/Shared/UsagePersistence.swift`** — reconciliation safety (line 579)
3. **`ScreenTimeRewardsProject/ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`** — reconciliation guard in `configureMonitoring()` (line 1646)

## Implementation Steps

### Step 1: Add error logging in `persistFamilySelection()` (ScreenTimeService.swift:255)

Replace `try?` with `do/catch` on the JSON encode call so we can see if encoding ever fails:

```swift
// Replace: if let encoded = try? JSONEncoder().encode(selection) {
do {
    let encoded = try JSONEncoder().encode(selection)
    sharedDefaults.set(encoded, forKey: "familySelection_persistent")
    sharedDefaults.set(selection.applications.count, forKey: "familySelection_app_count")
    // ... existing debug prints ...
} catch {
    print("[ScreenTimeService] ⚠️ JSONEncoder failed for FamilyActivitySelection: \(error.localizedDescription)")
    // Fall through to token fallback
}
```

Also persist the app count as metadata (`familySelection_app_count` key) so we can detect decode failures on restore.

### Step 2: Fix the token fallback persistence (ScreenTimeService.swift:271-286)

The current fallback uses `NSKeyedArchiver` which does NOT work for `ApplicationToken` (it's not an NSObject/NSSecureCoding type). Replace with `PropertyListEncoder` which is **proven to work** (already used at line 4109 and in the extension at lines 987/1017/1050):

```swift
// Replace NSKeyedArchiver with PropertyListEncoder
var archivedTokens: [Data] = []
for application in selection.applications {
    if let token = application.token,
       let archived = try? PropertyListEncoder().encode(token) {
        archivedTokens.append(archived)
    }
}
```

### Step 3: Implement fallback token restoration (ScreenTimeService.swift:295-322)

After JSON decode fails, ACTUALLY TRY the token fallback (currently the code just returns empty). Replace with `do/catch` and a multi-step fallback:

```swift
func restoreFamilySelection() -> FamilyActivitySelection {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { ... }

    // Step A: Try JSON Codable decode (primary)
    if let data = sharedDefaults.data(forKey: "familySelection_persistent") {
        do {
            let selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            // success — return
            return selection
        } catch {
            print("[ScreenTimeService] ⚠️ JSON decode failed: \(error.localizedDescription)")
            // Fall through to token fallback
        }
    }

    // Step B: Try individual token restoration (fallback)
    if let tokenArrayData = sharedDefaults.data(forKey: "familySelection_tokens_persistent"),
       let tokenDataArray = try? JSONDecoder().decode([Data].self, from: tokenArrayData) {
        var tokens: Set<ApplicationToken> = []
        for tokenData in tokenDataArray {
            if let token = try? PropertyListDecoder().decode(ApplicationToken.self, from: tokenData) {
                tokens.insert(token)
            }
        }
        if !tokens.isEmpty {
            var selection = FamilyActivitySelection(includeEntireCategory: true)
            selection.applicationTokens = tokens
            print("[ScreenTimeService] ✅ Restored \(tokens.count) tokens from fallback")
            return selection
        }
    }

    // Step C: Complete failure — check metadata to detect if this is a real loss
    let lastKnownCount = sharedDefaults.integer(forKey: "familySelection_app_count")
    if lastKnownCount > 0 {
        print("[ScreenTimeService] ❌ DECODE FAILURE: Had \(lastKnownCount) apps, decoded 0")
    }

    return FamilyActivitySelection(includeEntireCategory: true)
}
```

### Step 4: Add safety guard in `reconcileWithSelection()` (UsagePersistence.swift:579)

Prevent catastrophic wipe when called with an empty set while data exists:

```swift
func reconcileWithSelection(validLogicalIDs: Set<LogicalAppID>) {
    // SAFETY: Never wipe all apps — an empty validLogicalIDs with existing data
    // almost certainly means a FamilyActivitySelection decode failure
    if validLogicalIDs.isEmpty && !cachedApps.isEmpty {
        print("[UsagePersistence] ⚠️ SAFETY: Refusing to reconcile — 0 valid IDs but \(cachedApps.count) cached apps")
        return
    }
    // ... existing logic ...
}
```

### Step 5: Guard reconciliation in `configureMonitoring()` (AppUsageViewModel.swift:1645-1646)

The reconciliation call at line 1646 uses `familySelection` which could be empty in edge cases (e.g., if the ViewModel inherited empty state). Add a guard:

```swift
// Line 1645-1646: Only reconcile if we have tokens
let validLogicalIDs = Set(familySelection.applicationTokens.compactMap { service.getLogicalID(for: $0) })
if !validLogicalIDs.isEmpty {
    service.usagePersistence.reconcileWithSelection(validLogicalIDs: validLogicalIDs)
}
```

Note: The guard in Step 4 also protects this path, but an explicit check is clearer.

### Step 6: Detect decode failure in `loadPersistedAssignments()` (ScreenTimeService.swift:396-398)

After the `if !restoredSelection.applications.isEmpty` block, add a check to detect the failure case using the persisted count:

```swift
let restoredSelection = restoreFamilySelection()
if !restoredSelection.applications.isEmpty {
    // ... existing rebuild logic (lines 399-455) ...
} else {
    // Check if this is a decode failure vs genuinely empty
    if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
        let lastKnownCount = sharedDefaults.integer(forKey: "familySelection_app_count")
        if lastKnownCount > 0 {
            print("[ScreenTimeService] ⚠️ SELECTION DECODE FAILURE: Expected \(lastKnownCount) apps, got 0")
            print("[ScreenTimeService] ⚠️ Persisted app data preserved — user needs to re-select apps")
            // Do NOT reconcile or clear anything — preserve persistedApps_v3
        }
    }
}
```

## What This Does NOT Fix (acceptable)

- If ALL decode paths fail (JSON + token fallback), the user still needs to re-select apps via the picker. But their **configuration is preserved** (`persistedApps_v3` survives) — categories, points, and usage data auto-restore when they re-pick the same apps via `resolveLogicalID()` matching on bundleIdentifier/displayName.
- The root cause (Apple invalidating tokens on child devices) is not something we can prevent — we can only add resilience.

## Verification

1. **Build the project** in Xcode — ensure no compilation errors
2. **Test on device (parent mode):**
   - Select reward apps → close and reopen app → verify apps persist
   - Check debug console for "Persisted FamilyActivitySelection" and "familySelection_app_count" logs
3. **Test token fallback (simulated):**
   - After persisting, manually corrupt the `familySelection_persistent` key in UserDefaults (or delete it)
   - Reopen app → verify fallback restoration from `familySelection_tokens_persistent`
   - Check debug console for "Restored N tokens from fallback" log
4. **Test safety guard:**
   - Delete both persistence keys but leave `familySelection_app_count` at > 0
   - Reopen app → verify persisted app data (`persistedApps_v3`) is NOT wiped
   - Check for "SAFETY: Refusing to reconcile" log
5. **Test on child device:**
   - Deploy to a child's device and verify reward apps persist across app restarts
   - Monitor for any "DECODE FAILURE" logs that indicate the fix was needed
