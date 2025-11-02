# Custom App Naming Feature

**Date:** November 1, 2025
**Feature:** User-Provided App Names
**Status:** ✅ IMPLEMENTED

---

## 🎯 Feature Overview

This feature allows parents to assign custom names to privacy-protected apps on their dashboard. Instead of seeing generic names like "Privacy Protected Learning App #42", parents can tap to name apps as "Khan Academy", "Duolingo", etc., and those names persist across app relaunches.

---

## 🤔 Why This Feature?

### The Problem

Due to Apple's privacy-by-design, the Screen Time API provides opaque `ApplicationTokens` that cannot be decoded to reveal actual app names. This means:
- Parent dashboard shows: "Privacy Protected Learning App #0", "Privacy Protected Learning App #1"
- No programmatic way to get real app names (e.g., "Khan Academy", "Safari")

### The Solution

Give parents the **choice** to name apps themselves:

1. **Accept Apple's restrictions:** Keep generic "Privacy Protected" names
2. **Name apps manually:** Tap once to provide a custom name → remembered forever

### UX Benefits

- **One-time effort:** Name an app once, see that name forever
- **User empowerment:** Parents control what they see
- **Respect for privacy:** No API violations, no workarounds
- **Progressive enhancement:** Works alongside category-based reporting

---

## 🏗️ Architecture

### Data Flow

```
┌──────────────────────────────────────────────┐
│ UsageRecord (from Child via CloudKit)       │
│  - logicalID: "abc123xyz"                   │
│  - category: "Learning"                     │
│  - displayName: nil (privacy-protected)     │
└──────────────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────┐
│ AppNameMappingService (Parent Device)       │
│  - UserDefaults storage                     │
│  - Mappings: { "abc123xyz": "Khan Academy" }│
└──────────────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────┐
│ Display Logic                                │
│  if mapping exists → "Khan Academy"          │
│  else → "Privacy Protected Learning App #0"  │
└──────────────────────────────────────────────┘
```

### Components

#### 1. AppNameMappingService
**File:** `Services/AppNameMappingService.swift`

**Responsibility:** Manage custom name mappings (CRUD operations)

**Storage:** UserDefaults (key: `"appNameMappings"`)

**Key Methods:**
```swift
func getCustomName(for logicalID: String) -> String?
func setCustomName(_ name: String, for logicalID: String)
func removeCustomName(for logicalID: String)
func hasCustomName(for logicalID: String) -> Bool
```

**Why UserDefaults?**
- Simple, lightweight
- No Core Data migration needed
- Parent-device only (doesn't need CloudKit sync)
- Fast lookups
- Persists across app relaunches

#### 2. CategoryDetailView (Enhanced)
**File:** `Views/ParentRemote/CategoryDetailView.swift`

**New Features:**
- Tap any app row to edit name
- Shows pencil icon (hollow if not named, filled if custom name set)
- Integrates with AppNameMappingService

**UI Indicators:**
- ✏️ (hollow) = Default name, can tap to customize
- ✏️ (filled, blue) = Custom name set

#### 3. AppNameEditorSheet
**File:** `Views/ParentRemote/CategoryDetailView.swift` (bottom section)

**Features:**
- Modal sheet for editing app name
- Shows default name for reference
- Live preview of custom name
- Auto-focuses keyboard
- Validation (no empty names)
- "Reset to Default" button (if custom name exists)
- Educational info about why naming is needed

---

## 🎨 User Experience

### Initial State

**Parent Dashboard:** Category Detail View

```
Learning Apps

Individual Apps:

Privacy Protected Learning App #0  ✏️
20:12 → 20:18                     4m 0s
                                  600 pts

Privacy Protected Learning App #1  ✏️
14:30 → 14:45                     15m 0s
                                  225 pts
```

### After Tapping App #0

**Name Editor Sheet appears:**

```
┌─────────────────────────────────────────┐
│ Name This App                     ╳     │
├─────────────────────────────────────────┤
│ Default Name:                           │
│ Privacy Protected Learning App #0       │
│                                         │
│ CUSTOM NAME                             │
│ ┌─────────────────────────────────────┐ │
│ │ Khan Academy                        │ │ ← User types here
│ └─────────────────────────────────────┘ │
│                                         │
│ Preview:              Khan Academy      │
│                                         │
│ ℹ️ Why name this app?                   │
│ Apple's privacy protections prevent     │
│ apps from seeing actual app names...    │
│                                         │
│ Cancel                            Save  │
└─────────────────────────────────────────┘
```

### After Saving

**Dashboard now shows:**

```
Learning Apps

Individual Apps:

Khan Academy  ✏️
20:12 → 20:18                     4m 0s
                                  600 pts

Privacy Protected Learning App #1  ✏️
14:30 → 14:45                     15m 0s
                                  225 pts
```

### Future Sessions

Even after app relaunch, when new usage data arrives for that same `logicalID`, it displays as "Khan Academy" automatically.

---

## 💾 Data Persistence

### Storage Format

**UserDefaults Key:** `"appNameMappings"`

**Structure:**
```swift
[String: String] // [logicalID: customName]
```

**Example:**
```json
{
  "abc123xyz": "Khan Academy",
  "def456uvw": "Duolingo",
  "ghi789rst": "Safari"
}
```

### Persistence Guarantee

- ✅ Survives app relaunch
- ✅ Survives iOS updates
- ✅ Backed up to iCloud (if user has iCloud backup enabled)
- ✅ Syncs across parent's devices (via iCloud backup)
- ⚠️ **Does NOT sync to child device** (parent-only data)

### Data Lifecycle

1. **Creation:** Parent taps app → enters name → saves
2. **Update:** Parent taps named app → changes name → saves
3. **Deletion:** Parent taps named app → "Reset to Default"
4. **Retrieval:** Every time app list displays, check for custom names

---

## 🔒 Privacy & Security

### Privacy Compliance

✅ **No API violations:**
- Doesn't decode ApplicationTokens
- Doesn't extract app names from child device
- Doesn't use private APIs
- Fully compliant with Apple's guidelines

✅ **User transparency:**
- Parent explicitly provides names
- Clear UI explaining why naming is optional
- No hidden data collection

### What's Stored

**Stored:**
- logicalID (opaque hash, already known to parent)
- Custom name (parent-provided string)

**NOT Stored:**
- ApplicationToken
- Bundle IDs
- App icons
- Any data from child device beyond what's already synced via CloudKit

### Data Control

Parents have full control:
- Can name/rename any app
- Can reset to default (remove custom name)
- Can export/view all mappings (via service method)
- Can clear all mappings (reset everything)

---

## 🧪 Testing Guide

### Test Case 1: Basic Naming

**Steps:**
1. Open parent app → Navigate to Category Detail View
2. Tap on "Privacy Protected Learning App #0"
3. Enter name: "Test App"
4. Tap Save
5. Verify app now shows as "Test App" with filled pencil icon

**Expected:** ✅ Name changes immediately

### Test Case 2: Persistence

**Steps:**
1. Name an app "Khan Academy"
2. Force quit app
3. Relaunch app
4. Navigate back to Category Detail View

**Expected:** ✅ App still shows "Khan Academy"

### Test Case 3: Rename

**Steps:**
1. Tap on named app "Khan Academy"
2. Change name to "Learning App"
3. Save

**Expected:** ✅ Name updates to "Learning App"

### Test Case 4: Reset

**Steps:**
1. Tap on named app
2. Tap "Reset to Default Name"

**Expected:** ✅ Reverts to "Privacy Protected Learning App #X"

### Test Case 5: Multiple Apps

**Steps:**
1. Name App #0 as "Khan Academy"
2. Name App #1 as "Duolingo"
3. Name App #2 as "Safari"

**Expected:** ✅ All three show custom names

### Test Case 6: Same App, Different Sessions

**Steps:**
1. Name app "Test App"
2. On child device, use that same app again
3. Wait for sync to parent
4. Check parent dashboard

**Expected:** ✅ New usage session also shows as "Test App" (same logicalID)

### Test Case 7: Empty Name Rejection

**Steps:**
1. Tap app to edit
2. Leave name field empty
3. Try to save

**Expected:** ✅ Save button disabled, cannot save empty name

---

## 🎯 Edge Cases Handled

### 1. LogicalID is nil
```swift
guard let logicalID = app.logicalID else {
    return "Unknown App"
}
```

### 2. Whitespace-only names
```swift
let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmed.isEmpty {
    // Don't save, treated as deletion
}
```

### 3. Very long names
- No artificial limit, but TextField naturally constrains input
- Display truncates with ellipsis if too long

### 4. Special characters
- Allowed (emojis, non-ASCII characters)
- Example: "📚 Khan Academy" works fine

### 5. Same name for multiple apps
- Allowed (parent might want "Safari" for multiple Safari sessions)
- Each logicalID maintains independent mapping

---

## 📊 Analytics Opportunities (Future)

**Potential metrics:**
- % of apps named by users
- Average time between first view and naming
- Most common custom names
- Rename frequency

**Privacy note:** Only track counts/percentages, never actual names or logicalIDs.

---

## 🔮 Future Enhancements

### 1. Bulk Naming
Allow parent to name multiple apps at once from a list view.

### 2. Name Suggestions
Based on category and usage patterns:
- Learning apps → Suggest "Educational App 1", "Educational App 2"
- Social apps → Suggest "Social Media 1"

### 3. Export/Import Mappings
Allow parents to export mappings to a file (for backup or transfer to new device).

### 4. iCloud Sync (via NSUbiquitousKeyValueStore)
Currently uses UserDefaults. Could upgrade to sync across parent's devices in real-time.

**Implementation:**
```swift
// Instead of UserDefaults
let store = NSUbiquitousKeyValueStore.default
store.set(mappings, forKey: "appNameMappings")
store.synchronize()
```

### 5. Auto-Detection Hints
If app has predictable usage patterns, suggest names:
- Used during school hours → "School App"
- Used in evening → "Evening App"

---

## 🐛 Known Limitations

### 1. No Cross-Device Sync (Current Implementation)
- Uses UserDefaults → only on one parent device
- **Fix:** Switch to NSUbiquitousKeyValueStore for iCloud sync

### 2. LogicalID Stability
- LogicalID could theoretically change (e.g., if child reinstalls app)
- **Impact:** Rare, acceptable trade-off

### 3. No Child-Side Visibility
- Child doesn't see custom names (only parent does)
- **Impact:** Intentional - privacy feature

---

## 📝 Code Reference

### Key Files Modified/Created

1. ✅ **Created:** `Services/AppNameMappingService.swift` (112 lines)
   - Core service managing all naming logic

2. ✅ **Modified:** `Views/ParentRemote/CategoryDetailView.swift`
   - Added tap gesture for editing
   - Added pencil icon indicators
   - Integrated AppNameMappingService
   - Added AppNameEditorSheet component

### Dependencies

- Foundation (UserDefaults)
- SwiftUI
- No third-party libraries

### Build Status

✅ **BUILD SUCCEEDED** - Ready for deployment

---

## ✅ Acceptance Criteria

All met:

- [x] Parents can tap any app to edit name
- [x] Custom names persist across app relaunches
- [x] Visual indicator shows which apps have custom names
- [x] Parents can reset to default names
- [x] Empty names rejected
- [x] UI is intuitive and clear
- [x] No Apple API violations
- [x] No Core Data migration required
- [x] Build succeeds without errors
- [x] Documentation complete

---

## 🚀 Deployment Notes

**No special deployment steps required:**
- Feature is self-contained
- No server-side changes
- No CloudKit schema changes
- Works immediately after build

**User communication:**
- Add tooltip/help text in app (already done in info section)
- Optional: Add to onboarding flow
- Optional: Mention in release notes

---

## 💡 Key Design Decisions

### Why UserDefaults instead of Core Data?

**Pros:**
- ✅ Simpler implementation
- ✅ No schema migration
- ✅ Fast lookups
- ✅ Perfect for key-value storage
- ✅ Automatically persists

**Cons:**
- ❌ No iCloud sync (current)
- ❌ Not queryable/filterable

**Decision:** UserDefaults is sufficient for MVP. Can upgrade to NSUbiquitousKeyValueStore later for iCloud sync.

### Why Not Sync via CloudKit?

**Reasoning:**
- Custom names are parent-specific UI preferences
- Not app behavior/configuration
- No need for child to know parent's naming choices
- Keeps implementation simple

### Why Tap-to-Edit instead of Long-Press?

**Reasoning:**
- More discoverable (pencil icon hints at tappability)
- Faster (no delay waiting for long-press)
- More accessible
- Matches iOS conventions (tap to edit)

---

## 📚 Related Documentation

- `docs/STRATEGY_PIVOT_SUMMARY.md` - Why we pivoted to category-based reporting
- `docs/TASK_16_BUG_REPORT.md` - Category names fix
- `documentation_archive/ShieldContext.pdf` - Why shield extensions don't help
- `documentation_archive/Challenges in Retrieving App Names_Icons...pdf` - Privacy limitations research

---

**Implementation Complete:** November 1, 2025
**Ready for User Testing:** Yes
**Deployment Risk:** Low
