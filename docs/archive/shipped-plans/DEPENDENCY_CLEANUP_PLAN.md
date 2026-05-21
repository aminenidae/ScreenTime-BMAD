# Dependency Cleanup Plan

**Source**: `DEPENDENCY_AUDIT.md` (Fresh Scan - January 1, 2026)

---

## Executive Summary

The app uses **zero third-party dependencies** - excellent security posture. Only minor cleanup needed.

---

## Task 1: Delete LegacyContentView.swift

**File**: `ScreenTimeRewards/LegacyContentView.swift`

| Attribute | Value |
|-----------|-------|
| Lines | 87 |
| Status | Unused Xcode template |
| Contains | 2 fatalError() calls |

**Action**: Delete this file.

---

## Task 2: Review AppUsageView.swift

**File**: `ScreenTimeRewards/Views/AppUsageView.swift`

Creates own ViewModel instance instead of using shared one. Review if still needed.

**Action**: Delete if unused, or fix ViewModel usage.

---

## Task 3: Align iOS Deployment Targets ✅

All targets now aligned to **iOS 16.6**:

| Target | Status |
|--------|--------|
| ScreenTimeRewards (app) | 16.6 ✅ |
| ScreenTimeRewardsTests | 16.6 ✅ |
| ScreenTimeRewardsUITests | 16.6 ✅ |
| ScreenTimeActivityExtension | 16.6 ✅ |
| ScreenTimeReportExtension | 16.6 ✅ |
| ShieldConfigurationExtension | 16.6 ✅ (was 26.0) |

---

## Task 4: Review ManagedSettingsUI.framework ✅

**Status:** ACTIVELY USED - Do NOT remove

Used in `ShieldConfigurationExtension.swift`:
- `import ManagedSettingsUI` (line 9)
- Provides `ShieldConfiguration` class for custom shield UI
- Required for themed blocking screens (learning goal, daily limit, downtime, reward expired)

---

## Verification Checklist

- [x] LegacyContentView.swift deleted
- [x] AppUsageView.swift reviewed and deleted
- [x] App builds and runs correctly

---

## Positive Findings

1. **Zero third-party dependencies**
2. **Apple frameworks only**
3. **No supply chain risk**
4. **No license concerns**

---

*Updated January 1, 2026*
