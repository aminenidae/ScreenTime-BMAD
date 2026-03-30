# Plan: Extension Memory Optimization to Prevent iOS Kills

## Problem

DeviceActivityMonitor extensions have a **6MB hard memory limit** — the strictest of any iOS extension type. Our extension's `debugLog` function alone generates **~7.5-10MB of transient allocations per event**, virtually guaranteeing iOS kills under sustained usage. Additional issues compound the risk.

## Findings by Priority

### CRITICAL — `debugLog` is catastrophic (lines 30-41)

**Current behavior:** Every `debugLog` call:
1. Creates a new `DateFormatter` (expensive — Apple explicitly warns against this)
2. Reads the **entire** `extension_debug_log` string (~100KB at 1500 lines)
3. Splits into 1500 separate strings (another ~100KB allocation)
4. Filters empty lines → new array (~100KB)
5. Takes `.suffix(1499)` → new array
6. Joins back into a single string (~100KB)
7. Writes the full string back to UserDefaults

**Each call: ~500KB of transient allocations.** A single recorded event triggers **15-20 debugLog calls** = **7.5-10MB of transient allocations**, well above the 6MB limit.

The same pattern exists in `ExtensionCloudKitSync.swift:134-145` (with a 500-line buffer).

**Fix:** Replace with O(1) append-only logging:
- Append each new entry directly to the string (no read-parse-rewrite cycle)
- Only trim when the string exceeds a size threshold (e.g., 50KB)
- Cache `DateFormatter` as a `static let` (created once, reused forever)
- Reduce buffer from 1500 to 200 lines (still plenty for debugging)

### CRITICAL — Shield configs decoded twice per event

`extensionShieldConfigs` is decoded at:
- Line 551: `checkAndUpdateShields()`
- Line 716: `checkAndBlockIfRewardTimeExhausted()`

Both are called sequentially from `recordUsageEfficiently()` (lines 142-145). Same JSON data decoded twice = double the memory + CPU.

**Fix:** Decode once in `recordUsageEfficiently()`, pass the result to both functions.

### HIGH — `dictionaryRepresentation()` materializes all UserDefaults

Called at:
- Line 472: `resetAllDailyCounters()` — scans ALL keys to find `usage_*_today` patterns
- `ExtensionCloudKitSync.swift:92` — scans ALL keys to find `ext_usage_*_today` patterns

This creates a full in-memory copy of every key-value pair in the shared UserDefaults suite (could be thousands of entries with all the per-app keys).

**Fix:** Maintain a simple list of tracked app IDs in a single UserDefaults key (`tracked_app_ids` as a string array). Look up that list instead of scanning all keys.

### HIGH — CloudKit framework loaded in sandboxed extension

`ExtensionCloudKitSync.swift` imports CloudKit, which loads the full framework (~1-2MB). DeviceActivityMonitor extensions likely can't make network requests due to sandbox restrictions — this memory is wasted.

**Fix:** Gate the CloudKit sync behind a feature flag or remove the import entirely. The main app already syncs on foreground activation, so extension CloudKit sync is redundant.

### MEDIUM — Excessive UserDefaults I/O per event

A single recorded event does ~25-35 reads and ~20-30 writes. While individually cheap, the cumulative I/O triggers UserDefaults' internal coalescing/serialization. Not a kill risk on its own, but compounds other issues.

**Fix (partial):** Read commonly-used values once at the start of the function and pass them down, rather than re-reading keys multiple times across nested calls.

## Implementation Steps

### Step 1: Fix `debugLog` — O(1) append-only logging
**File:** `DeviceActivityMonitorExtension.swift` (lines 30-41)
- Create a `static let dateFormatter` cached instance
- Replace read-parse-rewrite with simple string append
- Add size-based trim (only when > 50KB, trim to last 200 lines)
- Apply same fix to `ExtensionCloudKitSync.debugLog` (lines 134-145)

### Step 2: Decode shield configs once
**File:** `DeviceActivityMonitorExtension.swift` (lines 142-148)
- In `recordUsageEfficiently()`, decode `extensionShieldConfigs` once before calling the shield functions
- Change `checkAndUpdateShields(defaults:)` → `checkAndUpdateShields(configs:defaults:)`
- Change `checkAndBlockIfRewardTimeExhausted(defaults:)` → `checkAndBlockIfRewardTimeExhausted(configs:defaults:)`
- Also update the call sites in `recordUsageWithMapping()` (lines 364-367)

### Step 3: Replace `dictionaryRepresentation()` with tracked app list
**Files:** `DeviceActivityMonitorExtension.swift` (line 472), `ExtensionCloudKitSync.swift` (line 92)
- Add a `tracked_app_ids` UserDefaults key (string array)
- Update it in `setUsageToThreshold()` when recording usage (add appID if not already in list)
- Use it in `resetAllDailyCounters()` instead of `dictionaryRepresentation()` scan
- Use it in `ExtensionCloudKitSync.collectUsageData()` instead of `dictionaryRepresentation()` scan

### Step 4: Gate CloudKit sync
**File:** `DeviceActivityMonitorExtension.swift` (line 148, line 370)
- Add a UserDefaults bool check (`ext_cloudkit_sync_enabled`, default `false`)
- Only call `ExtensionCloudKitSync.shared.syncUsageToParent()` if enabled
- Main app already handles CloudKit sync on foreground activation

### Step 5: Build and verify
- Confirm build succeeds with zero errors
- Memory should drop significantly — the debugLog fix alone eliminates ~7-10MB of transient allocations per event
