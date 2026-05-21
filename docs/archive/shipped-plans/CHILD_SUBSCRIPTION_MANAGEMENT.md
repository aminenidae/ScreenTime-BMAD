# Child Device Subscription Management

**Date:** 2026-02-04
**Status:** Implemented

## Overview

This document describes the device-aware subscription management system that ensures child devices see appropriate subscription options based on their device mode and subscription source.

## Problem Statement

Previously, the "Manage Subscription" screen on child devices showed the same options as parent devices, which was incorrect because:

- **Child devices can ONLY subscribe to the Solo plan directly**
- **Individual/Family plans must be purchased from a parent device** (child gets access via pairing)
- Showing "Upgrade to Family" on child devices was misleading

## Solution: Device-Aware Subscription Management

The subscription management UI now adapts based on:
1. Device mode (child vs parent)
2. Subscription source (self-purchased vs parent-paired)

### Behavior by Scenario

| Device | Subscription State | UI Shown |
|--------|-------------------|----------|
| **Child** | Trial (unpaired) | `ChildSubscriptionView` - Solo plan + Connect with Parent options |
| **Child** | Solo (self-purchased) | Subscription status + App Store link + "Connect with Parent" upgrade card |
| **Child** | Individual/Family (parent-paired) | "Managed by Parent" status card only |
| **Parent** | Any | Full subscription management (unchanged) |

## Files Modified

### 1. SubscriptionManager.swift

Added computed property to detect parent-paired subscriptions:

```swift
/// Whether this is a child device receiving subscription access from a parent
/// True when child device has Individual/Family tier (which can only come from parent pairing)
var isParentPairedSubscription: Bool {
    deviceManager.currentMode == .childDevice &&
    (currentTier == .individual || currentTier == .family)
}
```

**Location:** `ScreenTimeRewardsProject/ScreenTimeRewards/Services/SubscriptionManager.swift`

### 2. SubscriptionManagementView.swift

Major restructure to handle device-specific content:

- Added `@EnvironmentObject var deviceModeManager: DeviceModeManager`
- Split view into `childDeviceContent` and `parentDeviceContent`
- Added new UI components for child-specific scenarios

**Key Components Added:**

#### `childDeviceContent`
Routes to appropriate view based on subscription state:
```swift
@ViewBuilder
private var childDeviceContent: some View {
    if subscriptionManager.isParentPairedSubscription {
        // "Managed by Parent" status only
        managedByParentCard
    } else if subscriptionManager.currentTier == .solo {
        // Solo management + upgrade path
        soloManagementContent + connectWithParentUpgradeCard
    } else {
        // Trial - show ChildSubscriptionView
        ChildSubscriptionView()
    }
}
```

#### `managedByParentCard`
Displays when child is paired with a parent's Individual/Family subscription:
- Shows "Managed by Parent" header
- Displays current plan badge (Individual/Family)
- Shows subscription status
- No action buttons (subscription controlled by parent)

#### `connectWithParentUpgradeCard`
Displayed for Solo subscribers who want remote monitoring:
- "Want Remote Monitoring?" header
- Explains the upgrade path via parent pairing
- "Connect with Parent" button opens `ChildPairingView`

**Location:** `ScreenTimeRewardsProject/ScreenTimeRewards/Views/Subscription/SubscriptionManagementView.swift`

### 3. SettingsTabView.swift

Updated subscription row to reflect parent-managed status:

```swift
if subscriptionManager.isParentPairedSubscription {
    Text("Managed by Parent")
        .foregroundColor(AppTheme.vibrantTeal)
} else {
    Text(subscriptionManager.currentTierName)
        .foregroundColor(AppTheme.sunnyYellow)
}
```

**Location:** `ScreenTimeRewardsProject/ScreenTimeRewards/Views/SettingsTabView.swift`

## Subscription Tiers Reference

| Tier | Purchase Location | Features |
|------|------------------|----------|
| **Solo** | Child device | Single device, on-device monitoring only |
| **Individual** | Parent device | 1 child device, 2 parent devices, remote monitoring |
| **Family** | Parent device | Up to 5 children, 2 parents per child, remote monitoring |

## Upgrade Paths

### From Trial (Child Device)
1. **Solo Plan** - Subscribe directly on child device
2. **Individual/Family** - Have parent subscribe on their device, then pair via QR code

### From Solo (Child Device)
1. **Individual/Family** - Use "Connect with Parent" to pair with a parent who has an Individual/Family subscription

### From Individual (Parent Device)
1. **Family** - Upgrade directly from subscription management

## Testing Verification

1. **Child + Trial** → Should show `ChildSubscriptionView` with Solo + Connect with Parent options
2. **Child + Solo** → Should show subscription status, App Store link, and "Connect with Parent" upgrade card
3. **Child + Paired (Individual/Family)** → Should show "Managed by Parent" card only
4. **Parent + Any** → Should show full management options (unchanged behavior)

## Related Files

- `ChildSubscriptionView.swift` - Paywall for child devices (Solo + parent pairing)
- `SubscriptionPaywallView.swift` - Paywall for parent devices (all tiers)
- `ChildPairingView.swift` - QR code scanning for parent pairing
- `DeviceModeManager.swift` - Tracks current device mode
