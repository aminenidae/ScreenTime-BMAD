# ScreenTime Reward System - Source Tree

## Overview

This document provides a detailed overview of the project's source tree structure, explaining the purpose and contents of each directory and file. This structure follows Apple's recommended practices for iOS applications while organizing code for maintainability and scalability.

## Root Directory

```
ScreenTimeRewardSystem/
├── ScreenTimeRewardSystem.xcodeproj
├── ScreenTimeRewardSystem.xcworkspace
├── ScreenTimeRewardSystem/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── Assets.xcassets
│   ├── Preview Content/
│   │   └── Preview Assets.xcassets
│   └── Info.plist
├── ScreenTimeRewardSystemTests/
├── ScreenTimeRewardSystemUITests/
└── Documentation/
    ├── architecture/
    │   ├── architecture.md
    │   ├── tech-stack.md
    │   ├── coding-standards.md
    │   └── source-tree.md
    ├── prd/
    │   ├── prd.md
    │   └── prd-sharded/
    ├── front-end-spec.md
    ├── technical-feasibility-study.md
    ├── technical-feasibility-testing-plan.md
    ├── technical-feasibility-checklist.md
    └── project-brief.md
```

## Application Source Code

### Main Application Directory

```
ScreenTimeRewardSystem/
├── AppDelegate.swift
├── SceneDelegate.swift
├── Assets.xcassets
├── Preview Content/
│   └── Preview Assets.xcassets
├── Info.plist
├── Models/
├── Views/
├── ViewModels/
├── Services/
├── Utilities/
├── Extensions/
├── Protocols/
└── Resources/
```

#### AppDelegate.swift

The application delegate handles app-level concerns:
- Application lifecycle events
- Initial setup and configuration
- Background task management
- Notification handling setup

#### SceneDelegate.swift

The scene delegate manages UI scenes:
- Scene lifecycle events
- Window and view controller management
- State restoration
- Multi-window support (iPad)

#### Assets.xcassets

Contains all visual assets:
- App icons
- Image assets
- Color definitions
- Symbol configurations

#### Preview Content/

Assets used exclusively for SwiftUI previews:
- Sample data for previewing views
- Preview-specific configurations
- Test images and data

#### Info.plist

Application configuration file:
- Required permissions and entitlements
- Supported interface orientations
- Device capability requirements
- Custom URL schemes

### Models Directory

```
Models/
├── User/
│   ├── UserProfile.swift
│   ├── FamilyProfile.swift
│   └── UserSettings.swift
├── Tracking/
│   ├── AppUsage.swift
│   ├── AppCategory.swift
│   └── TrackingSession.swift
├── Rewards/
│   ├── Reward.swift
│   ├── RewardStatus.swift
│   └── RewardClaim.swift
├── Analytics/
│   ├── AnalyticsEvent.swift
│   ├── UsageReport.swift
│   └── ProgressSnapshot.swift
└── Core/
    ├── Identifiable.swift
    └── Codable.swift
```

#### User Module

Handles all user-related data models:
- `UserProfile`: Individual user information and preferences
- `FamilyProfile`: Family account information and settings
- `UserSettings`: User-specific configuration options

#### Tracking Module

Manages app usage tracking data:
- `AppUsage`: Detailed records of app usage sessions
- `AppCategory`: Classification of apps as learning or reward
- `TrackingSession`: Time-based tracking sessions

#### Rewards Module

Handles reward system data:
- `Reward`: Definition of rewardable items (apps)
- `RewardStatus`: Current state of rewards for users
- `RewardClaim`: Record of claimed rewards

#### Analytics Module

Manages analytics and reporting data:
- `AnalyticsEvent`: Individual tracked events
- `UsageReport`: Compiled usage statistics
- `ProgressSnapshot`: Point-in-time progress records

### Views Directory

```
Views/
├── Parent/
│   ├── Dashboard/
│   │   ├── ParentDashboardView.swift
│   │   ├── AnalyticsView.swift
│   │   └── FamilyManagementView.swift
│   ├── Configuration/
│   │   ├── LearningTargetsView.swift
│   │   ├── AppSelectionView.swift
│   │   └── RewardSetupView.swift
│   ├── Settings/
│   │   ├── ParentSettingsView.swift
│   │   └── NotificationSettingsView.swift
│   └── Components/
│       ├── TargetConfigurationView.swift
│       ├── AppCategoryView.swift
│       └── ProgressReportingView.swift
├── Child/
│   ├── Progress/
│   │   ├── ChildProgressView.swift
│   │   └── AchievementView.swift
│   ├── Rewards/
│   │   ├── RewardGalleryView.swift
│   │   └── RewardClaimView.swift
│   └── Components/
│       ├── ProgressIndicatorView.swift
│       ├── RewardCardView.swift
│       └── ChildDashboardView.swift
├── Components/
│   ├── ProgressIndicatorView.swift
│   ├── AppCardView.swift
│   ├── TimeInputView.swift
│   └── DashboardCardView.swift
├── Modifiers/
│   ├── AccessibilityModifiers.swift
│   └── StylingModifiers.swift
└── Shared/
    ├── LoadingView.swift
    ├── ErrorView.swift
    └── EmptyStateView.swift
```

#### Parent Views

All views accessible only from parent devices:
- Dashboard views for overview and analytics
- Configuration views for setting up learning targets and rewards
- Settings views for account and notification management

#### Child Views

All views accessible from child devices:
- Progress visualization views
- Reward viewing and claiming interfaces
- Achievement display components

#### Shared Components

Reusable UI components used across both parent and child interfaces:
- Progress indicators
- App display cards
- Time input controls
- Dashboard elements

#### Modifiers

Custom SwiftUI view modifiers:
- Accessibility enhancements
- Consistent styling applications
- Platform-specific adaptations

#### Shared Views

Common utility views:
- Loading states
- Error displays
- Empty state placeholders

### ViewModels Directory

```
ViewModels/
├── Parent/
│   ├── ParentDashboardViewModel.swift
│   ├── LearningTargetViewModel.swift
│   ├── RewardSetupViewModel.swift
│   └── AnalyticsViewModel.swift
├── Child/
│   ├── ChildProgressViewModel.swift
│   ├── RewardGalleryViewModel.swift
│   └── AchievementViewModel.swift
├── Tracking/
│   ├── TrackingViewModel.swift
│   └── AppUsageViewModel.swift
├── Rewards/
│   └── RewardViewModel.swift
└── Shared/
    ├── FamilyViewModel.swift
    └── UserViewModel.swift
```

#### Parent ViewModels

View models supporting parent-only functionality:
- Dashboard data aggregation
- Learning target management
- Reward configuration
- Analytics data processing

#### Child ViewModels

View models for child-facing features:
- Progress tracking display
- Reward gallery management
- Achievement data handling

#### Shared ViewModels

Common view models used across both interfaces:
- Family data coordination
- User profile management
- Cross-cutting concerns

### Services Directory

```
Services/
├── TrackingService.swift
├── RewardService.swift
├── FamilyService.swift
├── CloudKitService.swift
├── AnalyticsService.swift
├── NotificationService.swift
├── AuthenticationService.swift
└── DataService.swift
```

#### TrackingService

Core service for app usage tracking:
- Screen Time API integration
- Usage data collection
- Background tracking management
- Permission handling

#### RewardService

Manages the reward system logic:
- Reward calculation algorithms
- Reward claiming processing
- Unlock condition evaluation
- Status synchronization

#### FamilyService

Handles family account operations:
- Family creation and management
- User role validation
- Device synchronization coordination
- Access control enforcement

#### CloudKitService

Manages all CloudKit operations:
- Data synchronization
- Conflict resolution
- Offline support
- Security and privacy compliance

#### AnalyticsService

Handles analytics data collection:
- Event tracking
- Usage statistics compilation
- Performance metrics
- Privacy-compliant reporting

#### NotificationService

Manages local and remote notifications:
- Notification scheduling
- Permission management
- Content customization
- Delivery tracking

#### AuthenticationService

Handles user authentication:
- Apple Sign-In integration
- Credential management
- Session handling
- Biometric authentication

#### DataService

Core data management service:
- Core Data stack management
- Data migration handling
- Query optimization
- Backup and restore

### Utilities Directory

```
Utilities/
├── Constants.swift
├── Extensions/
├── Helpers/
├── Managers/
└── Enums/
```

#### Constants.swift

Global constants used throughout the application:
- Configuration values
- API endpoints
- UI metrics
- Business logic parameters

#### Extensions/

Swift extensions for system types:
- Date formatting extensions
- Collection utility extensions
- String manipulation helpers
- Numeric calculation extensions

#### Helpers/

Utility classes and structs:
- Date calculation utilities
- String formatting helpers
- Image processing utilities
- File management helpers

#### Managers/

Singleton-style managers for shared resources:
- Location manager wrapper
- Network connectivity manager
- Battery monitoring
- Permission managers

#### Enums/

Shared enumeration types:
- App categorization enums
- State management enums
- Error type definitions
- Configuration options

### Extensions Directory

```
Extensions/
├── Foundation/
│   ├── Date+Extensions.swift
│   ├── String+Extensions.swift
│   └── Collection+Extensions.swift
├── SwiftUI/
│   ├── View+Modifiers.swift
│   └── Color+Extensions.swift
└── UIKit/
    └── UIView+Extensions.swift
```

#### Foundation Extensions

Extensions to Foundation framework types:
- Date manipulation and formatting
- String processing and validation
- Collection operations and utilities

#### SwiftUI Extensions

Extensions to SwiftUI framework:
- Custom view modifiers
- Color palette extensions
- Animation utilities
- Layout helpers

#### UIKit Extensions

Extensions for UIKit interoperability:
- UIView customization helpers
- UIViewController utilities
- Bridge between UIKit and SwiftUI

### Protocols Directory

```
Protocols/
├── Services/
│   ├── TrackingServiceProtocol.swift
│   ├── RewardServiceProtocol.swift
│   └── CloudKitServiceProtocol.swift
├── ViewModels/
│   ├── TrackingViewModelProtocol.swift
│   └── RewardViewModelProtocol.swift
├── Models/
│   ├── Identifiable.swift
│   └── Codable.swift
└── Utilities/
    └── Observable.swift
```

#### Service Protocols

Interfaces for all service classes:
- Defines service contracts
- Enables dependency injection
- Facilitates testing
- Supports multiple implementations

#### ViewModel Protocols

Interfaces for view model classes:
- Standardizes view model interfaces
- Enables mock implementations for testing
- Defines data binding contracts
- Supports protocol-oriented programming

#### Model Protocols

Core protocols for data models:
- Identifiable for unique object identification
- Codable for serialization support
- Custom protocols for domain-specific behavior

#### Utility Protocols

Shared utility interfaces:
- Observable for custom observation patterns
- Validation protocols
- Configuration protocols

### Resources Directory

```
Resources/
├── Localizable.strings
├── PrivacyPolicy.txt
├── TermsOfService.txt
└── SampleData/
    ├── SampleUsageData.json
    └── SampleRewardData.json
```

#### Localizable.strings

Localization strings for internationalization:
- User-facing text strings
- Error messages
- Button titles
- Navigation labels

#### Legal Documents

Legal and compliance documents:
- Privacy policy text
- Terms of service
- Usage agreements
- Compliance disclosures

#### SampleData/

Sample data for development and testing:
- Mock usage data for previews
- Sample reward definitions
- Test family profiles
- Development-only data

## Test Directories

### Unit Tests

```
ScreenTimeRewardSystemTests/
├── Models/
├── ViewModels/
├── Services/
├── Utilities/
└── Extensions/
```

#### Models Tests

Unit tests for data models:
- Data structure validation
- Business logic testing
- Codable compliance verification
- Initialization tests

#### ViewModels Tests

Unit tests for view models:
- State management validation
- Data binding tests
- Business logic verification
- Error handling tests

#### Services Tests

Unit tests for service classes:
- API integration tests
- Business logic validation
- Error condition testing
- Performance tests

#### Utilities Tests

Unit tests for utility functions:
- Extension method validation
- Helper function testing
- Calculation accuracy tests
- Edge case coverage

### UI Tests

```
ScreenTimeRewardSystemUITests/
├── Parent/
├── Child/
├── Fl flops/
└── Accessibility/
```

#### Parent UI Tests

UI tests for parent functionality:
- Dashboard navigation tests
- Configuration workflow tests
- Settings modification tests
- Analytics view tests

#### Child UI Tests

UI tests for child functionality:
- Progress view interaction tests
- Reward claiming workflows
- Achievement display tests
- Navigation flow tests

#### Flows Tests

End-to-end user flow tests:
- Complete setup workflows
- Tracking to reward flows
- Family account creation
- Data synchronization scenarios

#### Accessibility Tests

Accessibility compliance tests:
- VoiceOver navigation
- Dynamic type support
- Color contrast validation
- Switch control testing

## Documentation Directory

```
Documentation/
├── architecture/
├── prd/
├── front-end-spec.md
├── technical-feasibility-study.md
├── technical-feasibility-testing-plan.md
├── technical-feasibility-checklist.md
└── project-brief.md
```

All project documentation is organized in this directory:
- Architecture documents
- Product requirements
- Technical specifications
- Feasibility studies
- Design specifications

This source tree structure provides a clear organization for all project files, making it easy for developers to locate and understand the purpose of each component. The modular approach supports scalability and maintainability as the project grows.