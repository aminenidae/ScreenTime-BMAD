# ScreenTime Rewards - Technical Decisions Log

## Overview
This document captures key technical decisions made during the ScreenTime Rewards implementation, including the rationale, alternatives considered, and impact of each decision.

## Decision 1: Simplified Category System

### Decision
Reduce from Apple's 7+ predefined categories to just 2 custom categories: Learning and Reward.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **User Experience**: Simpler for users to understand and manage
2. **App Purpose Alignment**: Better matches the core concept of rewarding learning activities
3. **Reduced Complexity**: Fewer categories mean less cognitive load for users
4. **Easier Management**: Simpler UI and data management

### Alternatives Considered
1. **Use Apple's Predefined Categories**: 
   - Pros: Familiar to users, comprehensive coverage
   - Cons: Overly complex, doesn't align with reward concept, harder to manage

2. **Three-Category System** (Learning, Reward, Other):
   - Pros: Slightly more granular than two categories
   - Cons: Still requires users to categorize non-learning/reward apps

3. **User-Defined Categories**:
   - Pros: Maximum flexibility
   - Cons: Overly complex, potential for inconsistent categorization

### Impact
- ✅ Improved user experience with simpler categorization
- ✅ Better alignment with app's reward concept
- ✅ Reduced UI complexity
- ✅ Easier data management and reporting

### Files Affected
- `Models/AppUsage.swift` - Updated AppCategory enum
- `ViewModels/AppUsageViewModel.swift` - Updated property names and calculations
- `Views/AppUsageView.swift` - Updated UI displays
- `Views/CategoryAssignmentView.swift` - Updated picker options
- `Services/ScreenTimeService.swift` - Updated categorization logic

## Decision 2: User-Defined Reward Points

### Decision
Change reward points calculation from category multipliers to user-assigned points × usage time.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **Intuitive**: Direct correlation between assigned points and earned rewards
2. **Flexible**: Users can assign any value based on their preferences
3. **Transparent**: Clear understanding of reward mechanics
4. **Customizable**: Different apps can have vastly different point values

### Alternatives Considered
1. **Category Multipliers** (original approach):
   - Pros: Automatic, consistent within categories
   - Cons: Less flexible, not intuitive, harder to explain

2. **Fixed Points Per Minute**:
   - Pros: Simple calculation
   - Cons: Not customizable per app

3. **Tiered Reward System**:
   - Pros: Encourages longer usage
   - Cons: More complex, harder to implement and understand

### Impact
- ✅ More intuitive reward calculation
- ✅ Greater flexibility for users
- ✅ Clearer understanding of reward mechanics
- ✅ Better customization per app

### Files Affected
- `Models/AppUsage.swift` - Updated earnedRewardPoints calculation
- `ViewModels/AppUsageViewModel.swift` - Updated display logic
- `Views/AppUsageView.swift` - Updated UI displays
- `Services/ScreenTimeService.swift` - Updated processing logic

## Decision 3: Smart Category Adjustment Workflow

### Decision
Implement intelligent reopening of CategoryAssignmentView that preserves existing assignments.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **User Need**: Users need to adjust categories/points after initial setup
2. **Efficiency**: Direct access when apps already selected
3. **Data Preservation**: Maintain existing assignments
4. **Seamless Experience**: No need to reselect apps for adjustments

### Alternatives Considered
1. **Always Reopen Picker First**:
   - Pros: Consistent flow
   - Cons: Inefficient, loses existing data

2. **Separate Adjustment View**:
   - Pros: Specialized for adjustments
   - Cons: Duplicate UI, maintenance overhead

3. **No Adjustment Capability**:
   - Pros: Simple implementation
   - Cons: Poor user experience, no flexibility

### Impact
- ✅ Seamless category adjustment workflow
- ✅ Preservation of existing assignments
- ✅ Efficient user experience
- ✅ Flexibility for ongoing management

### Files Affected
- `ViewModels/AppUsageViewModel.swift` - Added openCategoryAssignmentForAdjustment() method
- `Views/AppUsageView.swift` - Updated button action and section

## Decision 4: Privacy-Compliant Design with ApplicationToken

### Decision
Use ApplicationToken as primary identifier instead of bundle IDs or display names.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **Apple's Design**: ApplicationToken is the only guaranteed identifier from FamilyActivityPicker
2. **Privacy Compliance**: Aligns with Apple's privacy-first approach
3. **Reliability**: Tokens are always available when properly authorized
4. **Best Practice**: Recommended approach by Apple documentation

### Alternatives Considered
1. **Bundle ID Dependency**:
   - Pros: Familiar identifier
   - Cons: Often nil due to privacy, unreliable

2. **Display Name Dependency**:
   - Pros: User-friendly
   - Cons: Often nil due to privacy, unreliable

3. **Hybrid Approach** (Token + Bundle ID/Name):
   - Pros: Multiple identifiers
   - Cons: Complex logic, still unreliable

### Impact
- ✅ Full privacy compliance
- ✅ Reliable identification
- ✅ Apple guideline adherence
- ✅ Consistent behavior across devices/versions

### Files Affected
- `Models/AppUsage.swift` - Token-based identification
- `ViewModels/AppUsageViewModel.swift` - Token-based storage
- `Views/CategoryAssignmentView.swift` - Token-based assignments
- `Services/ScreenTimeService.swift` - Token-based monitoring

## Decision 5: App Group UserDefaults for Data Persistence

### Decision
Use App Group UserDefaults for sharing data between app and extension.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **Extension Communication**: Required for app-extension data sharing
2. **Simplicity**: Easy to implement and understand
3. **Performance**: Fast access for frequent operations
4. **Apple Support**: Well-supported mechanism

### Alternatives Considered
1. **CoreData**:
   - Pros: More robust, better for complex data
   - Cons: Overkill for current needs, more complex

2. **File-based Storage**:
   - Pros: Flexible format
   - Cons: More complex implementation, potential performance issues

3. **Keychain**:
   - Pros: Secure storage
   - Cons: Overkill for non-sensitive data, complex API

### Impact
- ✅ Reliable data sharing between app and extension
- ✅ Simple implementation
- ✅ Good performance
- ✅ Apple-supported approach

### Files Affected
- `ViewModels/AppUsageViewModel.swift` - Load/save methods
- `Services/ScreenTimeService.swift` - Data processing with tokens

## Decision 6: Label(token) for App Display

### Decision
Use SwiftUI's Label(token) to display real app names and icons.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **Apple's Recommendation**: Proper way to display app information
2. **Real Information**: Shows actual app names/icons despite nil returns
3. **Privacy Compliant**: Works within Apple's privacy framework
4. **User Friendly**: Familiar app representations

### Alternatives Considered
1. **Manual Naming**:
   - Pros: Full user control
   - Cons: Extra effort, potential for inconsistency

2. **Generic Placeholders**:
   - Pros: Simple implementation
   - Cons: Poor user experience

3. **Bundle ID Display**:
   - Pros: Technical accuracy
   - Cons: Not user-friendly, often nil

### Impact
- ✅ Real app names and icons displayed
- ✅ Privacy compliance maintained
- ✅ Good user experience
- ✅ Apple-recommended approach

### Files Affected
- `Views/CategoryAssignmentView.swift` - App display implementation

## Decision 7: Darwin Notifications + App Group for Extension Communication

### Decision
Use Darwin notifications for triggering and App Group UserDefaults for data exchange.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **System Integration**: Darwin notifications are designed for system-level events
2. **Payload Limitation**: Darwin notifications can't carry payloads
3. **Data Exchange**: App Group provides reliable data sharing
4. **Performance**: Efficient notification mechanism

### Alternatives Considered
1. **Direct Method Calls**:
   - Pros: Simple
   - Cons: Not possible between extension and app

2. **Custom Notification System**:
   - Pros: More control
   - Cons: Complex implementation, potential reliability issues

3. **File-based Communication**:
   - Pros: Flexible
   - Cons: Performance overhead, complexity

### Impact
- ✅ Reliable extension-to-app communication
- ✅ Efficient notification system
- ✅ Proper data exchange mechanism
- ✅ Apple-supported approach

### Files Affected
- `Services/ScreenTimeService.swift` - Notification handling and data exchange
- `Shared/ScreenTimeNotifications.swift` - Notification constants

## Decision 8: Time-Based Reward Calculation

### Decision
Calculate earned reward points as minutes × assigned reward points.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **Intuitive**: Direct relationship between time and points
2. **Consistent**: Same calculation regardless of app
3. **Scalable**: Works for any time duration
4. **Understandable**: Easy for users to predict earnings

### Alternatives Considered
1. **Fixed Points Per Session**:
   - Pros: Simple
   - Cons: Doesn't reward longer usage

2. **Exponential Rewards**:
   - Pros: Encourages longer sessions
   - Cons: Complex, harder to understand

3. **Threshold-Based Rewards**:
   - Pros: Clear goals
   - Cons: Less granular, all-or-nothing feeling

### Impact
- ✅ Intuitive reward calculation
- ✅ Consistent user experience
- ✅ Scalable for any usage pattern
- ✅ Easy to understand and predict

### Files Affected
- `Models/AppUsage.swift` - earnedRewardPoints calculation
- `ViewModels/AppUsageViewModel.swift` - Display logic
- `Views/AppUsageView.swift` - UI displays
- `Services/ScreenTimeService.swift` - Data processing

## Decision 9: Category-Based Reporting

### Decision
Display reward points and time separately by category (Learning/Reward).

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **User Focus**: Users want to see progress in each category
2. **Clear Feedback**: Immediate understanding of achievements
3. **Goal Tracking**: Easy to set category-specific goals
4. **Comparison**: Simple comparison between categories

### Alternatives Considered
1. **Only Total Points**:
   - Pros: Simple
   - Cons: No category insight

2. **App-by-App Display Only**:
   - Pros: Detailed
   - Cons: Hard to see category patterns

3. **Complex Dashboard**:
   - Pros: Lots of information
   - Cons: Overwhelming, hard to parse

### Impact
- ✅ Clear category-based feedback
- ✅ Easy progress tracking
- ✅ Goal-oriented display
- ✅ Simple category comparison

### Files Affected
- `ViewModels/AppUsageViewModel.swift` - Category calculation methods
- `Views/AppUsageView.swift` - Category display sections

## Decision 10: Token Hash-Based Storage Keys

### Decision
Use token hash values as keys for UserDefaults storage.

### Date
October 15, 2025

### Status
✅ Implemented

### Rationale
1. **UserDefaults Limitation**: Can't directly serialize ApplicationToken as key
2. **Uniqueness**: Hash provides unique identifier for each token
3. **Simplicity**: Straightforward implementation
4. **Performance**: Fast key lookup

### Alternatives Considered
1. **Bundle ID as Key**:
   - Pros: More readable
   - Cons: Often nil, not always unique

2. **Custom Serialization**:
   - Pros: More robust
   - Cons: Complex implementation

3. **CoreData Storage**:
   - Pros: Better for complex relationships
   - Cons: Overkill for current needs

### Impact
- ✅ Functional storage mechanism
- ✅ Unique key generation
- ✅ Simple implementation
- ✅ Good performance

### Files Affected
- `ViewModels/AppUsageViewModel.swift` - Load/save methods

## Conclusion

These technical decisions have shaped the ScreenTime Rewards implementation into a privacy-compliant, user-friendly application that successfully addresses the core challenge of app usage tracking within Apple's privacy framework. Each decision was made with careful consideration of user experience, technical feasibility, and Apple's guidelines.

The implementation demonstrates that it's possible to build a rewarding app usage tracking system even with the constraints of Apple's privacy-focused design, by leveraging the proper APIs and patterns.