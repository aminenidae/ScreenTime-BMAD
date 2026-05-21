# SQLite Usage Audit Log - Implementation Plan

## Purpose

Protect child device usage data against corruption (phantom inflation, data loss, threshold bugs) by maintaining an append-only audit log in SQLite that serves as the source of truth.

## Problem Statement

Current storage (`ext_usage_*` keys in UserDefaults) is vulnerable to:

| Issue | Impact |
|-------|--------|
| Phantom events | Inflate usage (30 min → 60 min) |
| Threshold corruption | Block real usage or allow duplicates |
| Day rollover bugs | Reset at wrong times |
| App reinstall | Lose all usage history |

UserDefaults uses **overwrite** semantics - once corrupted, history is lost.

## Solution: Append-Only SQLite Audit Log

### Core Principle

**Never overwrite, only append.** Each usage event becomes an immutable record.

```
UserDefaults (fast, mutable)     SQLite (slow, immutable)
┌─────────────────────────┐      ┌─────────────────────────┐
│ ext_usage_app1_today=120│  ←── │ app1, +60, 10:00am      │
│ (can be corrupted)      │      │ app1, +60, 10:01am      │
└─────────────────────────┘      │ (append-only audit log) │
                                 └─────────────────────────┘
```

If UserDefaults is corrupted, SQLite has the truth.

---

## Database Schema

### Location

```
App Group Container/Library/Application Support/usage_audit.sqlite
```

Path: `group.com.screentimerewards.shared`

### Tables

#### `usage_events` (Append-Only Audit Log)

```sql
CREATE TABLE usage_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_logical_id TEXT NOT NULL,
    seconds_added INTEGER NOT NULL,      -- Always 60 (one threshold event)
    threshold_minute INTEGER NOT NULL,   -- Which minute threshold triggered this
    event_date TEXT NOT NULL,            -- yyyy-MM-dd
    event_timestamp REAL NOT NULL,       -- Unix timestamp of recording
    session_id TEXT NOT NULL,            -- Extension session ID (for debugging)
    created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX idx_usage_events_app_date ON usage_events(app_logical_id, event_date);
CREATE INDEX idx_usage_events_date ON usage_events(event_date);
```

#### `daily_totals` (Cached Aggregates - Can Be Rebuilt)

```sql
CREATE TABLE daily_totals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_logical_id TEXT NOT NULL,
    event_date TEXT NOT NULL,
    total_seconds INTEGER NOT NULL,
    last_threshold_minute INTEGER NOT NULL,
    updated_at REAL NOT NULL,
    UNIQUE(app_logical_id, event_date)
);

CREATE INDEX idx_daily_totals_date ON daily_totals(event_date);
```

#### `sync_checkpoints` (For Validation)

```sql
CREATE TABLE sync_checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkpoint_type TEXT NOT NULL,       -- 'hourly', 'daily', 'manual'
    checkpoint_timestamp REAL NOT NULL,
    data_hash TEXT,                       -- Optional hash of state for integrity
    created_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
);
```

---

## Extension Integration

### File Structure

```
ScreenTimeActivityExtension/
├── DeviceActivityMonitorExtension.swift  (existing)
├── ExtensionCloudKitSync.swift           (existing)
└── UsageAuditDatabase.swift              (NEW)
```

### UsageAuditDatabase.swift

```swift
import Foundation
import SQLite3

/// Thread-safe, lightweight SQLite wrapper for extension usage audit log
final class UsageAuditDatabase {
    static let shared = UsageAuditDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.screentimerewards.usageaudit", qos: .utility)

    private init() {
        openDatabase()
        createTablesIfNeeded()
    }

    // MARK: - Core Operations

    /// Record a usage event (append-only, never fails silently)
    func recordUsageEvent(
        appLogicalID: String,
        secondsAdded: Int,
        thresholdMinute: Int,
        date: String,
        sessionID: String
    ) -> Bool {
        // INSERT into usage_events
        // UPDATE daily_totals (upsert)
    }

    /// Get total seconds for an app on a specific date
    func getTotalSeconds(appLogicalID: String, date: String) -> Int {
        // SELECT SUM(seconds_added) FROM usage_events WHERE ...
    }

    /// Validate UserDefaults against database
    func validateAgainstUserDefaults(defaults: UserDefaults) -> [ValidationDiscrepancy] {
        // Compare ext_usage_* values with database totals
    }

    /// Repair UserDefaults from database (source of truth)
    func repairUserDefaults(defaults: UserDefaults) {
        // For each discrepancy, set UserDefaults to database value
    }
}
```

### Integration in DeviceActivityMonitorExtension.swift

```swift
// In setUsageToThreshold(), AFTER phantom protection passes:

// 1. Write to SQLite FIRST (source of truth)
let recorded = UsageAuditDatabase.shared.recordUsageEvent(
    appLogicalID: appID,
    secondsAdded: 60,
    thresholdMinute: thresholdMinutes,
    date: dateString,
    sessionID: Self.sessionID
)

guard recorded else {
    debugLog("AUDIT_DB: Failed to record - NOT updating UserDefaults", defaults: defaults)
    return false  // Don't update UserDefaults if database write failed
}

// 2. Then update UserDefaults (fast access cache)
defaults.set(newTotal, forKey: "ext_usage_\(appID)_today")
```

---

## Main App Validation

### On App Launch / Foreground

```swift
// In ScreenTimeService or AppDelegate

func validateUsageDataIntegrity() {
    guard let db = UsageAuditDatabase.shared else { return }

    let discrepancies = db.validateAgainstUserDefaults(defaults: sharedDefaults)

    if !discrepancies.isEmpty {
        print("[Integrity] Found \(discrepancies.count) discrepancies:")
        for d in discrepancies {
            print("  - \(d.appID): UserDefaults=\(d.userDefaultsValue), DB=\(d.databaseValue)")
        }

        // Auto-repair: Trust database
        db.repairUserDefaults(defaults: sharedDefaults)
        print("[Integrity] Repaired from database source of truth")
    }
}
```

---

## Data Flow

### Recording (Extension)

```
eventDidReachThreshold()
    ↓
recordUsageEfficiently()
    ↓
Phantom protection check ──→ BLOCK if phantom
    ↓ (passed)
UsageAuditDatabase.recordUsageEvent()  ← WRITE TO DB FIRST
    ↓ (success)
Update ext_usage_* UserDefaults        ← Then update cache
    ↓
Sync to CloudKit (optional)
```

### Validation (Main App)

```
App becomes active
    ↓
validateUsageDataIntegrity()
    ↓
Compare: UserDefaults vs SQLite
    ↓
Discrepancy? ──→ Repair UserDefaults from SQLite
    ↓
Continue with validated data
```

---

## Edge Cases

### 1. Database Write Fails

```swift
// Don't update UserDefaults - prevents desync
guard recorded else { return false }
```

### 2. Database Corrupted

```swift
// Rebuild daily_totals from usage_events
func rebuildDailyTotals() {
    // DELETE FROM daily_totals
    // INSERT INTO daily_totals SELECT ... FROM usage_events GROUP BY ...
}
```

### 3. App Reinstall

SQLite in App Group **survives app deletion** (if user keeps app data).
If truly deleted, fresh start - no corruption to worry about.

### 4. Day Rollover

Database uses `event_date` column - natural partitioning by day.
No complex rollover logic needed.

---

## Memory Considerations

Extension has ~6MB memory limit. SQLite is lightweight:

| Operation | Memory Impact |
|-----------|---------------|
| Open database | ~100KB |
| Single INSERT | Negligible |
| Query daily total | Negligible |

**Key**: Don't load large result sets. Use aggregates (`SUM`, `COUNT`).

---

## Testing Strategy

### Unit Tests

1. Record event → verify in database
2. Record duplicate threshold → verify rejected
3. Simulate phantom → verify blocked
4. Corrupt UserDefaults → verify repair works

### Integration Tests

1. Record 10 events → verify total = 600s
2. Kill extension mid-write → verify database consistency
3. Reinstall app → verify database survives (App Group)

### Manual Testing

1. Use app for 30 minutes
2. Check UserDefaults and database match
3. Manually corrupt UserDefaults
4. Launch main app → verify auto-repair

---

## Implementation Steps

### Phase 1: Database Infrastructure
- [ ] Create `UsageAuditDatabase.swift` with SQLite wrapper
- [ ] Create tables on first access
- [ ] Add basic CRUD operations

### Phase 2: Extension Integration
- [ ] Modify `setUsageToThreshold()` to write to database first
- [ ] Add session ID tracking for debugging
- [ ] Add debug logging for database operations

### Phase 3: Main App Validation
- [ ] Add `validateUsageDataIntegrity()` on app launch
- [ ] Add repair logic for discrepancies
- [ ] Add logging/alerting for corruptions detected

### Phase 4: Testing & Hardening
- [ ] Test memory usage in extension
- [ ] Test database survival across reinstall
- [ ] Test corruption detection and repair
- [ ] Load testing (1000+ events)

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `ScreenTimeActivityExtension/UsageAuditDatabase.swift` | CREATE |
| `ScreenTimeActivityExtension/DeviceActivityMonitorExtension.swift` | MODIFY |
| `ScreenTimeRewards/Services/ScreenTimeService.swift` | MODIFY |
| `ScreenTimeRewards/Services/UsageIntegrityValidator.swift` | CREATE |

---

## Rollback Plan

If issues arise:
1. Database writes can be disabled with a flag in UserDefaults
2. UserDefaults remains the active cache - app continues working
3. Database is supplementary - removing it doesn't break functionality

---

# Session Summary (2026-01-31)

## Current Status: BLOCKED - Deduplication Not Working

Duplicates are still being recorded despite multiple fix attempts.

---

## The Core Problem

Apple spawns **multiple extension PROCESSES** in parallel. Each process:
- Has its own memory space
- Has its own `UsageAuditDatabase.shared` instance
- Has its own DispatchQueue (queue.sync doesn't help across processes)

When threshold fires:
1. Instance A reads `lastThreshold` from SQLite → returns 0
2. Instance B reads `lastThreshold` from SQLite → ALSO returns 0 (before A writes)
3. Both see `lastThreshold=0` and BOTH record min=1

---

## What We've Tried (All Failed)

| Approach | Why It Failed |
|----------|---------------|
| **Session-based dedup** | Apple uses different session IDs per instance |
| **Time-based (55s) dedup** | Parallel instances fire >55s apart |
| **Strict dedup (block if ever recorded today)** | Blocked legitimate new sessions after INTERVAL_END/START |
| **No dedup (rely on extension logic)** | UserDefaults sync too slow between processes |
| **SQLite reads for lastThreshold** | Read/write not atomic across processes |

---

## Key Insight: Interval Restart Behavior

From logs, after `INTERVAL_END/START`, Apple resets thresholds:
```
01:35:29 - Last recording before interval end
01:39:34 - INTERVAL_END/START
01:41:53 - min=1 fires again (should be ALLOWED - new interval)
```

**Within ONE interval**: Each threshold should only count once
**After interval restart**: Same threshold (min=1) should be allowed again

---

## Proposed Solution: Interval-Aware Deduplication

Track interval start timestamp in SQLite and only dedup within current interval.

### Implementation Sketch:
1. On `INTERVAL_START` callback, record timestamp to SQLite
2. In `recordUsageEvent()`, check:
   ```sql
   SELECT COUNT(*) FROM usage_events
   WHERE app_logical_id = ?
     AND event_date = ?
     AND threshold_minute = ?
     AND event_timestamp > ?  -- current interval start
   ```
3. If count > 0, skip (duplicate within this interval)
4. If count = 0, record (first occurrence in this interval)

### Files to Modify:
- `UsageAuditDatabase.swift` - Add interval tracking + dedup logic
- `DeviceActivityMonitorExtension.swift` - Record interval start on INTERVAL_START

---

## Changes Already Made (Keep These)

### ✅ SQLite reads in DeviceActivityMonitorExtension.swift:
- `currentToday` reads from `getTotalSeconds()` (line ~327)
- `lastThreshold` reads from `getLastThresholdMinute()` (line ~332)
- `checkGoalMet()` reads from SQLite (lines ~733, 748)
- `checkAndBlockIfRewardTimeExhausted()` reads from SQLite (line ~862)
- `calculateEarnedMinutes()` reads from SQLite (lines ~974, 991)

### ✅ ExtensionCloudKitSync.swift:
- Reads from SQLite with UserDefaults fallback

### ❌ UsageAuditDatabase.recordUsageEvent():
- Currently has NO deduplication (we removed it)
- NEEDS interval-aware deduplication added back

---

## Completed Tasks

### ✅ CloudKit Sync (Already Fixed)
`ExtensionCloudKitSync.swift` now reads from SQLite database with fallback to UserDefaults.

### ✅ SQLite Integration Complete
- Extension writes to SQLite (source of truth)
- Main app syncs SQLite → UsagePersistence on launch/foreground
- UI reads from UsagePersistence

---

## Data Flow (After This Fix)

```
Extension threshold fires:
  1. Interval-aware deduplication check (already recorded in current interval?)
  2. If allowed → Write to SQLite ✅ (source of truth)
  3. Write to ext_* keys (cache/backup)
  4. CloudKit sync reads from SQLite ✅

Main app on foreground:
  → SQLite → UsagePersistence (sync)
  → UI displays from UsagePersistence ✅
```

---

## Next Steps (For Next Session)

1. Add `interval_starts` table or column to track INTERVAL_START timestamps
2. Modify `recordUsageEvent()` to check if threshold already recorded in current interval
3. Test with learning app for 5+ minutes
4. Verify each minute recorded exactly once
5. Verify new interval allows thresholds to record again
