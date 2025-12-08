# Personalized Shield Messages Feature

## Overview

This feature enhances the shield view to display personalized, context-aware messages based on the specific blocking reason for each reward app. Instead of a generic "Learning Time First!" message, users see exactly why an app is blocked and what they need to do to unlock it.

## Requirements

- **Per-app messages**: Each reward app shows its own personalized blocking reason
- **Single reason display**: Show primary reason only (no combined messages)
- **Priority order**: Time Window > Daily Limit > Challenge Goal

## Blocking Reasons

### 1. Outside Time Window (Highest Priority)
When the current time is outside the app's allowed usage window.

**Example messages:**
- "This app is available Monday-Friday, 5:00 PM - 8:00 PM"
- "YouTube is available on weekends only"
- "Come back at 4:00 PM when this app becomes available"

### 2. Daily Limit Reached (Medium Priority)
When the user has exhausted their daily time allowance for the app.

**Example messages:**
- "You've used your 30 minutes of YouTube today"
- "Daily limit reached! Come back tomorrow"
- "You've used 30/30 minutes of TikTok today"

### 3. Challenge Not Met (Lowest Priority)
When the user needs to complete learning goals before unlocking.

**Example messages:**
- "Complete 12 more minutes of Duolingo to unlock"
- "Learn for 15 minutes to unlock this app (5/15 done!)"
- "Almost there! Just 3 more minutes of reading"

## Data Architecture

### BlockingReason Enum
```swift
enum BlockingReason: String, Codable {
    case outsideTimeWindow
    case dailyLimitReached
    case challengeNotMet
}
```

### AppBlockingInfo Structure
```swift
struct AppBlockingInfo: Codable {
    let tokenHash: String
    let appName: String
    let reason: BlockingReason

    // Time window data (when reason == .outsideTimeWindow)
    var allowedDays: [String]?        // ["Mon", "Tue", "Wed"]
    var allowedStartTime: String?     // "5:00 PM"
    var allowedEndTime: String?       // "8:00 PM"

    // Daily limit data (when reason == .dailyLimitReached)
    var dailyLimitMinutes: Int?
    var usedMinutes: Int?

    // Challenge data (when reason == .challengeNotMet)
    var targetMinutes: Int?
    var currentMinutes: Int?
    var learningAppNames: [String]?
}
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Main App                                 │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ AppUsageViewModel│───▶│ ShieldDataService│                   │
│  │                 │    │                 │                    │
│  │ - Check time    │    │ - Sync blocking │                    │
│  │ - Check limits  │    │   info to       │                    │
│  │ - Check goals   │    │   UserDefaults  │                    │
│  └─────────────────┘    └────────┬────────┘                    │
│                                  │                              │
└──────────────────────────────────┼──────────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │    App Groups UserDefaults   │
                    │  group.com.screentimerewards │
                    │         .shared              │
                    └──────────────┬──────────────┘
                                   │
┌──────────────────────────────────┼──────────────────────────────┐
│                                  │                              │
│            Shield Configuration Extension                       │
│                                  │                              │
│  ┌─────────────────┐    ┌───────▼─────────┐                    │
│  │ShieldConfiguration│◀──│ Read blocking  │                    │
│  │   Extension     │    │ info by token  │                    │
│  │                 │    │ hash           │                    │
│  │ - Generate msg  │    └─────────────────┘                    │
│  │ - Set icon      │                                           │
│  │ - Set buttons   │                                           │
│  └─────────────────┘                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Files to Modify

| File | Changes |
|------|---------|
| `ScreenTimeRewards/Services/ShieldDataService.swift` | Add new data structures and sync methods |
| `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift` | Add blocking reason calculation logic |
| `ShieldConfigurationExtension/ShieldConfigurationExtension.swift` | Update to read per-app blocking info |
| `ScreenTimeRewards/Services/AppScheduleService.swift` | May need to expose schedule data for sync |

## Sync Triggers

The blocking info is recalculated and synced when:
1. App schedule config changes (time window, daily limit)
2. Challenge progress updates
3. Usage tracking updates (for daily limits)
4. On app foreground

## Testing Checklist

- [ ] Time window blocking shows correct days/times
- [ ] Daily limit shows used/total minutes
- [ ] Challenge shows progress and learning app names
- [ ] Priority order works (time > limit > challenge)
- [ ] Fallback message shows when no specific data
- [ ] Data syncs correctly between app and extension
- [ ] Messages update in real-time as conditions change
- [ ] Token hashing is consistent between main app and extension
