# Label Size Issue - FamilyControls Framework

## Problem Statement

App names displayed using `Label(token).labelStyle(.titleOnly)` from the FamilyControls framework do not respect font size modifiers. Long app names like "Mobile Legends: Bang Bang" break the layout across multiple views.

## Root Cause

The FamilyControls `Label` component is a **black box** that renders app names internally and **completely ignores** SwiftUI text modifiers including:
- `.font(.system(size: X))` - Font size is not applied
- `.lineLimit(N)` - Line limiting doesn't work
- `.truncationMode(.tail/.middle)` - Truncation mode is ignored
- `.minimumScaleFactor(X)` - Scaling is not applied
- Any other text-specific modifiers

This is an **iOS privacy restriction** - Apple doesn't allow developers to programmatically access or manipulate app names outside of the Label rendering.

## Why This Happens

From the logs:
```
[ScreenTimeService]   Localized display name: nil
[ScreenTimeService]   Bundle identifier: nil
[ScreenTimeService]   Token: Available
```

- `application.localizedDisplayName` returns `nil` for privacy
- `bundleIdentifier` returns `nil` for privacy
- Only the opaque `ApplicationToken` is available
- The `Label` component uses this token internally to fetch and display the app name
- This rendering happens **inside** the Label component where we have no control

## Alternative Approaches Attempted

### ❌ Approach 1: Use `resolvedDisplayName(for: token)`
**What we tried:** Replace Label with Text using `viewModel.resolvedDisplayName(for: token)`

**Why it failed:**
```swift
let displayName = viewModel.resolvedDisplayName(for: snapshot.token) ?? snapshot.displayName
Text(displayName) // Shows "Unknown App" because displayName is nil
```
- `resolvedDisplayName()` returns `nil` - no programmatic access to app names
- Database already contains "Unknown App" placeholders from initial save
- Cannot extract the actual app name from the token

**Code location:** Attempted in RewardsTabView.swift, ChallengeBuilderView.swift, ChildDashboardView.swift (all reverted)

---

### ❌ Approach 2: Apply Text Modifiers to Label
**What we tried:** Apply `.lineLimit()`, `.truncationMode()`, `.minimumScaleFactor()` directly to Label

**Example:**
```swift
Label(snapshot.token)
    .labelStyle(.titleOnly)
    .font(.system(size: 13, weight: .medium))     // IGNORED
    .lineLimit(1)                                 // IGNORED
    .truncationMode(.tail)                        // IGNORED
    .minimumScaleFactor(0.7)                      // IGNORED
```

**Why it failed:**
- Label is a special FamilyControls component, not a standard SwiftUI Text view
- It renders its content internally using system APIs
- SwiftUI text modifiers are simply not processed by this component
- The font size, line limits, and truncation are all controlled internally

**Code location:** Attempted across all views, modifiers had no effect

---

### ❌ Approach 3: Wrap Label in Fixed-Size Container with Clipping
**What we tried:** Constrain Label in a fixed frame and clip overflow

**Example:**
```swift
HStack {
    Label(snapshot.token)
        .labelStyle(.titleOnly)
        .font(.system(size: 16, weight: .medium))
    Spacer(minLength: 0)
}
.frame(height: 22)
.clipped()  // Cut off overflow text
```

**Why it failed:**
- Text gets **abruptly cut off** instead of truncating with "..."
- Poor UX - looks broken rather than intentional
- Still doesn't solve the fundamental problem of text being too large

**Code location:**
- RewardsTabView.swift (lines 191-199, reverted)
- ChallengeBuilderView.swift (lines 816-823, reverted)
- ChildDashboardView.swift (lines 367-375, reverted)

---

### ❌ Approach 4: Reduce Font Size via Modifier
**What we tried:** Set smaller font sizes to make long names fit

**Attempts:**
1. 16pt → 13pt (first attempt)
2. 13pt → 8pt (second attempt)

**Example:**
```swift
Label(snapshot.token)
    .labelStyle(.titleOnly)
    .font(.system(size: 8, weight: .medium))  // Font size modifier IGNORED
```

**Why it failed:**
- The `.font()` modifier has **NO EFFECT** on Label text size
- Text continues to render at its default size regardless of the font modifier
- This is the current state of the code, but it doesn't actually work

**Code locations (current state, but not working):**
- RewardsTabView.swift:192 - `.font(.system(size: 8, weight: .medium))`
- LearningTabView.swift:186 - `.font(.system(size: 8, weight: .medium))`
- ChildDashboardView.swift:369 - `.font(.system(size: 8, weight: .medium))`
- ChallengeBuilderView.swift:817 - `.font(.system(size: 8, weight: .medium))`

**Status:** ❌ Font size does not change - Label ignores the modifier

---

## Current State

The app is in a **non-functional state** regarding app name display:
- Code has `.font(.system(size: 8))` modifiers applied to all Labels
- These modifiers are **completely ignored** by the Label component
- Long app names still break layouts
- No actual font size reduction occurs

## Affected Views

1. **RewardsTabView** (Parent Mode - Reward Apps)
   - File: `ScreenTimeRewards/Views/RewardsTabView.swift:190-193`
   - Issue: Long names overflow horizontally

2. **LearningTabView** (Parent Mode - Learning Apps)
   - File: `ScreenTimeRewards/Views/LearningTabView.swift:184-187`
   - Issue: Long names overflow horizontally

3. **ChallengeBuilderView** (Challenge Builder - App Selection)
   - File: `ScreenTimeRewards/Views/ParentMode/ChallengeBuilderView.swift:815-820`
   - Issue: Long names overflow in 90pt wide buttons

4. **ChildDashboardView** (Child Mode - Play Zone)
   - File: `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift:367-370`
   - Issue: Long names push lock icon off screen

## iOS Limitation Details

### What Apple Provides
- `Label(token: ApplicationToken)` - Renders app icon and/or name
- `.labelStyle(.iconOnly)` - Shows only icon (works)
- `.labelStyle(.titleOnly)` - Shows only name (renders at fixed size)
- `.labelStyle(.automatic)` - Shows both icon and name

### What Apple Does NOT Provide
- Programmatic access to app name string
- Control over text rendering (size, truncation, wrapping)
- Access to bundle identifier
- Any way to customize Label text appearance

### Why This Limitation Exists
**Privacy by Design:** iOS 15+ FamilyControls framework uses opaque tokens to prevent apps from:
- Identifying which specific apps are installed
- Tracking app usage patterns programmatically
- Building profiles based on app names

The Label component acts as a **controlled rendering gate** - it can display the app name to users, but the app code cannot access or manipulate that name.

## Research Findings

### Attempted Solutions from Research
1. **LabeledContentStyle** - Not applicable to FamilyControls Labels
2. **GeometryReader** - Cannot measure or constrain Label text
3. **ViewThatFits** (iOS 16+) - Doesn't work with Label (not truly adaptive)
4. **ScrollView for horizontal scrolling** - Considered but not implemented (poor UX)
5. **Custom LabelStyle** - Cannot conform to LabelStyle for FamilyControls Labels

### Similar Issues in Community
- This is a known limitation across the iOS developer community
- No public workarounds exist as of iOS 15-17
- Apple's documentation does not acknowledge this limitation
- FB (Feedback) reports exist but no response from Apple

## Potential Future Solutions

### Option 1: Multi-line Layout (Not Tested)
Allow Label to wrap to 2 lines by increasing container height:
```swift
Label(snapshot.token)
    .labelStyle(.titleOnly)
    .frame(height: 40)  // Allow 2 lines
```
**Pros:** May show more of long names
**Cons:** Takes vertical space, unknown if Label actually wraps

---

### Option 2: Horizontal ScrollView (Not Tested)
Wrap Label in a small horizontal ScrollView:
```swift
ScrollView(.horizontal, showsIndicators: false) {
    Label(snapshot.token)
        .labelStyle(.titleOnly)
}
.frame(height: 22)
```
**Pros:** User can scroll to see full name
**Cons:** Non-standard UI, may feel broken

---

### Option 3: Redesign Layout
Restructure views to give more space to app names:
- Reduce icon sizes further
- Stack vertically instead of horizontally
- Remove other UI elements to make room

**Pros:** Might accommodate longer names
**Cons:** Major UI redesign required

---

### Option 4: Use Icon Only + Tooltip (Not Tested)
Show only app icons, display name in tooltip/overlay on tap:
```swift
Label(snapshot.token)
    .labelStyle(.iconOnly)
    .onTapGesture {
        // Show overlay with app name
    }
```
**Pros:** Icons fit in small space
**Cons:** Requires extra tap to see name, poor discoverability

---

### Option 5: Wait for Apple Fix
File radar/feedback and wait for Apple to add text customization APIs.

**Pros:** Proper solution if Apple provides it
**Cons:** May never happen, timeline unknown

---

## Logs Evidence

From app logs showing the privacy restrictions:
```
[ScreenTimeService] Processing application: Unknown App 0
[ScreenTimeService]   Display Name: Unknown App 0
[ScreenTimeService]   Bundle ID: nil (this is normal)
[ScreenTimeService]   Token: Available
```

Label view hierarchy warnings (expected for LazyVGrid):
```
Label is already or no longer part of the view hierarchy
Label is already or no longer part of the view hierarchy
...
```
These warnings are normal - they occur when LazyVGrid/LazyVStack adds/removes Labels during scrolling. They don't affect functionality.

## Recommendation

**BLOCKED:** This issue cannot be resolved with the current FamilyControls API. The `.font()` modifier approach does not work.

**Next Steps:**
1. Choose one of the "Potential Future Solutions" above
2. Consider whether the layout can be redesigned to accommodate default Label text size
3. File feedback with Apple requesting text customization APIs for FamilyControls Label
4. Accept the limitation and design around default Label behavior

## References

- **FamilyControls Framework:** https://developer.apple.com/documentation/familycontrols
- **ApplicationToken:** https://developer.apple.com/documentation/managedsettings/applicationtoken
- **Label (FamilyControls):** https://developer.apple.com/documentation/familycontrols/label

---

**Document Created:** 2025-11-09
**Last Updated:** 2025-11-09
**Status:** 🔴 **UNRESOLVED** - No working solution exists
