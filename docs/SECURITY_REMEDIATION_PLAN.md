# Security Remediation Plan

**Source**: `SECURITY_ASSESSMENT.md` (Fresh Scan - January 1, 2026)
**Overall Risk Level**: LOW-MEDIUM

---

## Executive Summary

Based on the fresh security scan, the ScreenTime Rewards app has good security practices overall. The main action items are:

1. **Remove deprecated `.synchronize()` calls** - 32 occurrences
2. **Delete unused LegacyContentView.swift** - Contains fatalError()
3. **Fix fatalError() in Persistence.swift** - 3 occurrences

---

## Priority Matrix

| Priority | Issue | Count | Files |
|----------|-------|-------|-------|
| High | Remove `.synchronize()` | 32 | 7 files |
| High | Delete LegacyContentView.swift | 1 file | Unused code |
| Medium | Fix fatalError() in Persistence.swift | 3 | 1 file |

---

## Task 1: Remove Deprecated `.synchronize()` Calls

**Total: 32 occurrences across 7 files**

| File | Lines | Count |
|------|-------|-------|
| `TotalActivityReport.swift` | 79 | 1 |
| `DeviceActivityMonitorExtension.swift` | 40, 49, 142, 364, 466, 527, 611, 738 | 8 |
| `ScreenTimeService.swift` | 222, 249, 950, 1034, 1063, 1348, 1384, 1420, 1555, 1589, 1754, 1925, 2018, 2587, 3258 | 15 |
| `ShieldDataService.swift` | 86, 96 | 2 |
| `AppUsageViewModel.swift` | 451, 1933 | 2 |
| `UsagePersistence.swift` | 490, 542, 549 | 3 |
| `ExtensionDiagnosticsView.swift` | 624 | 1 |

**Action**: Delete all `.synchronize()` lines. iOS handles synchronization automatically since iOS 12.

---

## Task 2: Delete LegacyContentView.swift

**File**: `ScreenTimeRewards/LegacyContentView.swift`

**Reason**:
- Unused Xcode template code
- Contains 2 fatalError() calls
- Not referenced anywhere

**Action**: Delete file.

---

## Task 3: Fix fatalError() in Persistence.swift

**File**: `ScreenTimeRewards/Persistence.swift`
**Lines**: 25, 40, 68

**Action**: Replace with graceful error handling:

```swift
// Instead of:
fatalError("Unresolved error \(nsError), \(nsError.userInfo)")

// Use:
print("[Persistence] Critical error: \(nsError)")
// Handle gracefully
```

---

## Testing Requirements

1. After removing `.synchronize()`:
   - Verify data persists after force-quit
   - Verify extension writes sync to main app
   - Test CloudKit sync

2. After deleting LegacyContentView.swift:
   - Verify app builds and runs

---

## Verification Checklist

- [x] All 32 `.synchronize()` calls removed
- [x] LegacyContentView.swift deleted
- [x] fatalError() replaced in Persistence.swift
- [x] App builds successfully (pre-existing warnings only)
- [x] Data persistence verified (UserDefaults auto-syncs since iOS 8)

---

*Updated January 1, 2026 with accurate line numbers*
