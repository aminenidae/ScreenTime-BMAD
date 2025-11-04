# Dev Agent Tasks - Phase 1 Update: 3D Card Carousel

**Priority:** HIGH
**Date:** November 2, 2025 (Updated)
**Estimated Time:** 50-60 minutes

---

## Overview

User feedback on Phase 1 implementation requires two changes:

1. **Wrong icon** - Change from `iphone.gen2.badge.plus` to `plus.circle.fill` (more prominent)
2. **Wrong layout** - Change from vertical list to **two-level navigation:**
   - **Level 1:** 3D card carousel on dashboard (horizontal scroll, tap to view)
   - **Level 2:** Full usage dashboard with swipe navigation between children

---

## Task 1: Fix Add Child Device Icon ⚡ (5 minutes)

**File:** `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift`
**Line:** 107

**Change:**
```swift
// BEFORE
Image(systemName: "iphone.gen2.badge.plus")

// AFTER
Image(systemName: "plus.circle.fill")
```

**Why:** User wants more prominent plus sign, not tiny badge.

---

## Task 2: Implement 3D Card Carousel + Swipeable Dashboard 🎯 (50 minutes)

### Current Problem
Shows multiple child summary cards in vertical list → tap → navigate to detail view.

### User Request
**Two-level navigation system:**
1. **Dashboard:** Large cards with device name/icon, scroll horizontally, tap to drill down
2. **Usage View:** Full usage data, swipe left/right to switch children

### Implementation Steps

#### A. Create Device Card Carousel Component (15 minutes)

**New File:** `ScreenTimeRewards/Views/ParentRemote/DeviceCardCarousel.swift`

**Purpose:** Horizontal scrolling carousel showing large device cards

**Implementation:** Copy from `UX_UI_IMPROVEMENTS_PHASE_1_UPDATE.md` Part B

**Key features:**
- `DeviceCardCarousel` - Main carousel view
- `DeviceCard` - Individual card showing device icon, name, and "Tap to view"
- GeometryReader for card sizing (75% of screen width)
- Shadow effect for depth
- NavigationLink to `ChildUsageDashboardView`

#### B. Create Swipeable Usage Dashboard (20 minutes)

**New File:** `ScreenTimeRewards/Views/ParentRemote/ChildUsageDashboardView.swift`

**Purpose:** Full usage dashboard with horizontal swipe navigation between children

**Implementation:** Copy from `UX_UI_IMPROVEMENTS_PHASE_1_UPDATE.md` Part C

**Key features:**
- `ChildUsageDashboardView` - Main view with TabView paging
- `ChildUsagePageView` - Single page per child showing all usage data
- Custom toolbar with device name and "X of Y" counter
- Arrow buttons for navigation
- TabView with `.page` style (no dots)

#### C. Update ParentRemoteDashboardView (5 minutes)

**File:** `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift`
**Lines to Replace:** 48-85

**Change FROM:**
```swift
// Multi-child view - show all linked children
if !viewModel.linkedChildDevices.isEmpty {
    VStack(spacing: 20) {
        ForEach(viewModel.linkedChildDevices, id: \.deviceID) { childDevice in
            NavigationLink(destination: ChildDetailView(...)) {
                ChildDeviceSummaryCard(...)
            }
        }
    }
    .padding(.horizontal)
}
```

**Change TO:**
```swift
// 3D Card Carousel - Level 1 Navigation
if !viewModel.linkedChildDevices.isEmpty {
    VStack(spacing: 16) {
        Text("Family Devices")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

        // 3D Card Carousel
        DeviceCardCarousel(devices: viewModel.linkedChildDevices)
    }
} else if !viewModel.isLoading {
    // Keep existing empty state unchanged
    ...
}
```

**Note:** See `UX_UI_IMPROVEMENTS_PHASE_1_UPDATE.md` Part A for full code with empty state.

#### D. Verify ViewModel Methods (10 minutes)

**File:** `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Required methods:**
- `loadLinkedChildDevices()` - Already exists
- `loadChildData(for device: RegisteredDevice)` - Check if exists

**If `loadChildData(for:)` doesn't exist:**

The current implementation likely loads data based on a selected device. The `ChildUsagePageView` will call this on appear for each device.

**No changes needed if existing data loading works correctly.**

---

## Expected Result

### Before Fix
```
[📱+badge]                               [🔄]  ← Tiny badge

┌─────────────────────────────────┐
│ Child 1 Summary Card            │ ← Tap to navigate
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ Child 2 Summary Card            │ ← Tap to navigate
└─────────────────────────────────┘

↓ Vertical scroll for more
```

### After Fix - Level 1 (Dashboard)
```
[⭕+]                                    [🔄]  ← Big plus circle

Family Dashboard
Welcome, Parent!

Family Devices

    ┌──────────┐  ┌───────────┐  ┌──────────┐
    │          │  │           │  │          │
    │    📱    │  │    📱     │  │    📱    │
    │  iPad    │  │  iPhone   │  │  iPhone  │
    │          │  │           │  │          │
    │Tap to ›  │  │ Tap to ›  │  │ Tap to › │
    └──────────┘  └───────────┘  └──────────┘

    ← Scroll left/right to see more cards →
```

### After Fix - Level 2 (Usage Dashboard - After Tap)
```
        ← Child's iPhone (1 of 3) →

┌════════════════════════════════════┐
│                                    │
│   ⏰ 2h 30m      ⭐ 1500 pts       │
│                                    │
│   📊 Usage stats                   │
│   📈 Charts                        │
│   📅 History                       │
│                                    │
└════════════════════════════════════┘

    ← Swipe left/right to switch children →
```

---

## Testing Checklist

### Icon
- [ ] Plus icon is prominent (filled circle)
- [ ] Icon is blue and matches iOS design patterns
- [ ] Tapping opens pairing QR code view

### Level 1: Card Carousel (Dashboard)
- [ ] Large device cards appear
- [ ] Cards scroll horizontally (left/right)
- [ ] Device names display correctly
- [ ] Device icons show correctly
- [ ] Cards have shadow/depth effect
- [ ] "Tap to view" indicator shows
- [ ] Tapping card navigates to usage dashboard
- [ ] Works with 1, 2, and 3+ children

### Level 2: Usage Dashboard (After Tapping Card)
- [ ] Full usage data displays for selected child
- [ ] Swipe left shows next child's data
- [ ] Swipe right shows previous child's data
- [ ] Custom header shows device name
- [ ] Header shows "X of Y" counter
- [ ] Left arrow button works
- [ ] Right arrow button works
- [ ] Arrow buttons disable at ends
- [ ] Vertical scrolling works within page
- [ ] Data loads correctly per child

### Navigation
- [ ] Dashboard → Tap card → Usage view
- [ ] Usage view → Back → Returns to dashboard
- [ ] Dashboard → Scroll cards → See all devices
- [ ] Usage view → Swipe → Switch children

---

## Build Verification

After implementation:
1. Build must succeed with no errors
2. No warnings about unused views (ChildDeviceSummaryCard, ChildDetailView can stay for now)
3. Test on simulator with 2+ paired devices

---

## Reference Documentation

**Full implementation details:** `docs/UX_UI_IMPROVEMENTS_PHASE_1_UPDATE.md`

**Complete code for ChildFullPageView with all subviews:** See section "Create New Full-Page Child View" in the update doc.

---

## Time Estimates

| Task | Time |
|------|------|
| Fix icon | 2 min |
| Create DeviceCardCarousel.swift | 15 min |
| Create ChildUsageDashboardView.swift | 20 min |
| Update ParentRemoteDashboardView | 5 min |
| Verify ViewModel methods | 5 min |
| Testing (both levels) | 13 min |
| **Total** | **60 min** |

---

## Summary

**Two-level navigation:**
1. **Dashboard (Level 1):** Large cards in horizontal carousel → tap to drill down
2. **Usage View (Level 2):** Full child data → swipe to switch children

**Key files:**
- `DeviceCardCarousel.swift` (NEW) - Carousel with cards
- `ChildUsageDashboardView.swift` (NEW) - Swipeable dashboard
- `ParentRemoteDashboardView.swift` (MODIFY) - Replace multi-child section

**Reference:** See `UX_UI_IMPROVEMENTS_PHASE_1_UPDATE.md` for complete code.

---

**Start with Task 1 (icon), then Task 2 (carousel + dashboard).**
