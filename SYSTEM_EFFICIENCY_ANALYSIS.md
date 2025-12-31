# System Efficiency Analysis Report

**Project**: ScreenTime Rewards System
**Analysis Date**: 2025-12-31
**Branch**: `claude/audit-dependencies-mju97s01ed8mc7nh-JKVEt`

---

## Executive Summary

This analysis identifies performance bottlenecks, resource inefficiencies, and optimization opportunities in the ScreenTime Rewards codebase. The most critical issue is **multiple ViewModel instances** causing duplicate data loading and state synchronization problems.

| Category | Severity | Issues Found |
|----------|----------|--------------|
| Architecture | **Critical** | 1 |
| Memory Management | Medium | 2 |
| Persistence | Medium | 3 |
| UI Performance | Medium | 2 |
| Concurrency | Low | 2 |
| Code Duplication | Low | 1 |

---

## 1. Critical Issues

### 1.1 Multiple ViewModel Instances (CRITICAL)

**Location**:
- `Views/LearningTabView.swift:6`
- `Views/RewardsTabView.swift:6`
- `Views/AppUsageView.swift:6`

**Problem**:
```swift
// Each view creates its own instance
struct LearningTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()  // Instance 1
}

struct RewardsTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()  // Instance 2
}

struct AppUsageView: View {
    @StateObject private var viewModel = AppUsageViewModel()  // Instance 3
}
```

**Impact**:
- **3x memory usage** for ViewModel data
- **3x notification subscriptions** to `usageDidChangeNotification`
- **State desynchronization** between tabs (adding app in Learning tab not visible in Rewards)
- **3x data loading** on app launch
- **3x Combine pipeline allocations**

**Recommendation**:
```swift
// Option 1: Use @EnvironmentObject (recommended)
@main
struct ScreenTimeRewardsApp: App {
    @StateObject private var viewModel = AppUsageViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
        }
    }
}

struct LearningTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    // ...
}

// Option 2: Singleton pattern (if EnvironmentObject not suitable)
class AppUsageViewModel: ObservableObject {
    static let shared = AppUsageViewModel()
    // ...
}
```

**Effort**: Medium
**Priority**: P0 - Fix immediately

---

## 2. Memory Management Issues

### 2.1 Excessive @Published Properties

**Location**: `ViewModels/AppUsageViewModel.swift:32-58`

**Problem**:
```swift
class AppUsageViewModel: ObservableObject {
    @Published var appUsages: [AppUsage] = []           // 1
    @Published var isMonitoring = false                  // 2
    @Published var learningTime: TimeInterval = 0        // 3
    @Published var rewardTime: TimeInterval = 0          // 4
    @Published var totalRewardPoints: Int = 0            // 5
    @Published var learningRewardPoints: Int = 0         // 6
    @Published var rewardRewardPoints: Int = 0           // 7
    @Published var errorMessage: String?                 // 8
    @Published var familySelection: FamilyActivitySelection = .init()  // 9
    @Published var thresholdMinutes: [AppUsage.AppCategory: Int] = [:] // 10
    @Published var isFamilyPickerPresented = false       // 11
    @Published var isAuthorizationGranted = false        // 12
    @Published var isCategoryAssignmentPresented = false // 13
    @Published var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:] // 14
    @Published var rewardPoints: [ApplicationToken: Int] = [:]  // 15
    @Published private(set) var sortedApplications: [Application] = []  // 16
    @Published var pickerError: String?                  // 17
    @Published var pickerLoadingTimeout = false          // 18
    @Published var pickerRetryCount = 0                  // 19
    @Published private(set) var learningSnapshots: [LearningAppSnapshot] = []  // 20
    @Published private(set) var rewardSnapshots: [RewardAppSnapshot] = []       // 21
    // 21 published properties!
}
```

**Impact**:
- Each @Published property triggers SwiftUI view updates
- Cascade updates when multiple properties change together
- Potential for excessive recomputations

**Recommendation**:
```swift
// Group related state into sub-objects
struct PickerState {
    var error: String?
    var loadingTimeout = false
    var retryCount = 0
}

struct UsageState {
    var learningTime: TimeInterval = 0
    var rewardTime: TimeInterval = 0
    var totalRewardPoints: Int = 0
    var learningRewardPoints: Int = 0
    var rewardRewardPoints: Int = 0
}

class AppUsageViewModel: ObservableObject {
    @Published var pickerState = PickerState()  // 1 update instead of 3
    @Published var usageState = UsageState()    // 1 update instead of 5
    // ... reduced to ~10 @Published properties
}
```

**Effort**: Medium
**Priority**: P2

---

### 2.2 Timer Lifecycle Management

**Location**: `Services/ScreenTimeService.swift:86,900`

**Problem**:
```swift
private var monitoringRestartTimer: Timer?
private let restartInterval: TimeInterval = 120  // 2 minutes

// Timer created but invalidation not guaranteed in all paths
monitoringRestartTimer = Timer.scheduledTimer(withTimeInterval: restartInterval, repeats: true) { [weak self] _ in
    self?.restartMonitoringCycle()
}
```

**Impact**:
- Timer may continue running after monitoring stops
- Potential memory leak if timer holds strong reference cycle
- Wasted CPU cycles if timer fires when not needed

**Recommendation**:
```swift
func stopMonitoring() {
    monitoringRestartTimer?.invalidate()
    monitoringRestartTimer = nil
    // ... rest of cleanup
}

deinit {
    monitoringRestartTimer?.invalidate()
}
```

**Effort**: Low
**Priority**: P2

---

## 3. Persistence Efficiency Issues

### 3.1 Deprecated `.synchronize()` Calls

**Locations** (8 occurrences):
- `DeviceActivityMonitorExtension.swift:50,104`
- `ScreenTimeService.swift:116,143,673,848,880`
- `UsagePersistence.swift:185,192`

**Problem**:
```swift
defaults.set(encoded, forKey: "persistedApps_v3")
defaults.synchronize()  // Deprecated and unnecessary
```

**Impact**:
- Unnecessary disk I/O
- Blocks calling thread
- Apple deprecated this in iOS 12

**Recommendation**:
```swift
// Simply remove synchronize() calls
defaults.set(encoded, forKey: "persistedApps_v3")
// iOS handles synchronization automatically
```

**Effort**: Low
**Priority**: P1

---

### 3.2 Repeated JSON Encoding/Decoding

**Location**: `UsagePersistence.swift:183-192`

**Problem**:
```swift
// Every single save encodes the entire dictionary
func saveApp(_ app: PersistedApp) {
    cachedApps[app.logicalID] = app
    persistApps()  // Encodes ALL apps, not just the changed one
}

func recordUsage(logicalID: LogicalAppID, additionalSeconds: Int, ...) {
    // ... modify app
    persistApps()  // Encodes ALL apps again
}
```

**Impact**:
- With 20 apps, every usage update encodes all 20 apps
- JSON encoding is CPU-intensive
- Disk writes for every small change

**Recommendation**:
```swift
// Option 1: Debounced persistence
private var persistenceWorkItem: DispatchWorkItem?

func saveApp(_ app: PersistedApp) {
    cachedApps[app.logicalID] = app
    schedulePersistence()
}

private func schedulePersistence() {
    persistenceWorkItem?.cancel()
    persistenceWorkItem = DispatchWorkItem { [weak self] in
        self?.persistApps()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: persistenceWorkItem!)
}

// Option 2: Batch updates
func recordUsageBatch(updates: [(LogicalAppID, Int, Int)]) {
    for (id, seconds, points) in updates {
        // Modify in-memory only
    }
    persistApps()  // Single write for batch
}
```

**Effort**: Medium
**Priority**: P2

---

### 3.3 Extension Duplicates Persistence Logic

**Location**: `DeviceActivityMonitorExtension.swift:10-67`

**Problem**:
```swift
// Extension has its own copy of PersistedApp and persistence logic
private struct ExtensionUsagePersistence {
    struct PersistedApp: Codable {  // Duplicated from UsagePersistence
        // ... same fields
    }

    func recordUsage(...) {  // Duplicated logic
        // ... similar implementation
    }
}
```

**Impact**:
- Maintenance burden (changes needed in 2 places)
- Potential for divergence between implementations
- Code bloat in extension binary

**Recommendation**:
Move shared types to a Swift Package or shared framework:
```
ScreenTimeShared/
├── Models/
│   └── PersistedApp.swift
└── Persistence/
    └── UsagePersistence.swift
```

**Effort**: High
**Priority**: P3

---

## 4. UI Performance Issues

### 4.1 Redundant Reduce Operations

**Location**: `ViewModels/AppUsageViewModel.swift:564-607`

**Problem**:
```swift
func refreshData() {
    appUsages = service.getAppUsages().sorted { $0.totalTime > $1.totalTime }
    updateCategoryTotals()      // Iterates appUsages with filter + reduce
    updateTotalRewardPoints()   // Iterates appUsages with reduce
    updateCategoryRewardPoints() // Iterates appUsages with filter + reduce (x2)
    updateSortedApplications()  // Another iteration
}

// 5 separate iterations over the same data!
```

**Impact**:
- O(5n) instead of O(n) for data updates
- Unnecessary allocations for intermediate filter results

**Recommendation**:
```swift
func refreshData() {
    appUsages = service.getAppUsages().sorted { $0.totalTime > $1.totalTime }

    // Single pass computation
    var learningTime: TimeInterval = 0
    var rewardTime: TimeInterval = 0
    var totalPoints = 0
    var learningPoints = 0
    var rewardPoints = 0

    for usage in appUsages {
        totalPoints += usage.earnedRewardPoints
        if usage.category == .learning {
            learningTime += usage.totalTime
            learningPoints += usage.earnedRewardPoints
        } else {
            rewardTime += usage.totalTime
            rewardPoints += usage.earnedRewardPoints
        }
    }

    self.learningTime = learningTime
    self.rewardTime = rewardTime
    self.totalRewardPoints = totalPoints
    self.learningRewardPoints = learningPoints
    self.rewardRewardPoints = rewardPoints

    updateSortedApplications()
}
```

**Effort**: Low
**Priority**: P2

---

### 4.2 Snapshot Deduplication in Every Update

**Location**: `ViewModels/AppUsageViewModel.swift:234-259`

**Problem**:
```swift
private func updateSnapshots() {
    var processedTokenHashes: Set<String> = []  // Created every update

    for application in sortedApplications {
        // ... hash lookup for every app
        if processedTokenHashes.contains(tokenHash) {
            continue  // O(1) but set grows
        }
        processedTokenHashes.insert(tokenHash)
        // ...
    }
}
```

**Impact**:
- Set allocation on every snapshot update
- Deduplication logic runs on every refresh

**Recommendation**:
```swift
// Deduplicate at source (when sortedApplications is built)
// or cache the deduplication result
private var deduplicatedApplications: [Application] = []

private func updateSortedApplications() {
    var seen = Set<String>()
    deduplicatedApplications = masterSelection.sortedApplications(using: service.usagePersistence)
        .filter { app in
            guard let token = app.token else { return false }
            let hash = service.usagePersistence.tokenHash(for: token)
            return seen.insert(hash).inserted
        }
    // ...
}
```

**Effort**: Low
**Priority**: P3

---

## 5. Concurrency Issues

### 5.1 Multiple DispatchQueue.main.async Calls

**Location**: Various files

**Problem**:
```swift
// Nested main queue dispatches
service.requestPermission { [weak self] result in
    DispatchQueue.main.async {  // First dispatch
        switch result {
        case .success:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {  // Second dispatch
                self.isFamilyPickerPresented = true
            }
        }
    }
}
```

**Impact**:
- Unnecessary queue hops if already on main
- Delayed UI updates
- Harder to reason about execution order

**Recommendation**:
```swift
// Use @MainActor for automatic main thread handling
@MainActor
func handlePermissionResult(_ result: Result<Void, Error>) {
    switch result {
    case .success:
        Task {
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            isFamilyPickerPresented = true
        }
    }
}
```

**Effort**: Medium
**Priority**: P3

---

### 5.2 Combine Subscription Not Cancelled on Deinit

**Location**: `ViewModels/AppUsageViewModel.swift:146-152`

**Problem**:
```swift
private var cancellables = Set<AnyCancellable>()

init() {
    NotificationCenter.default
        .publisher(for: ScreenTimeService.usageDidChangeNotification)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.usageDidChange()
        }
        .store(in: &cancellables)
}
// No explicit cleanup - relies on cancellables being deallocated
```

**Impact**:
- With multiple ViewModel instances, multiple subscriptions exist
- Potential for zombie subscriptions if deinit not called

**Recommendation**:
```swift
deinit {
    cancellables.removeAll()  // Explicit cleanup
}
```

**Effort**: Low
**Priority**: P3

---

## 6. Code Quality Issues

### 6.1 Reflection-Based Token Extraction

**Location**: `Shared/UsagePersistence.swift:213-234`

**Problem**:
```swift
private func extractTokenData(_ token: ManagedSettings.ApplicationToken) -> Data? {
    let mirror = Mirror(reflecting: token)  // Slow reflection
    if let data = mirror.children.first(where: { $0.label == "data" })?.value as? Data {
        return data
    }
    // Nested reflection...
}
```

**Impact**:
- Mirror reflection is 10-100x slower than direct property access
- Fragile - depends on internal Apple structure
- Called for every token hash computation

**Recommendation**:
```swift
// Cache token hashes after first computation
private var tokenHashCache: [ObjectIdentifier: String] = [:]

func tokenHash(for token: ManagedSettings.ApplicationToken) -> String {
    let id = ObjectIdentifier(token)
    if let cached = tokenHashCache[id] {
        return cached
    }
    let hash = computeTokenHash(token)
    tokenHashCache[id] = hash
    return hash
}
```

**Effort**: Low
**Priority**: P2

---

## 7. Performance Metrics Summary

### Current State Estimates

| Operation | Current | Optimal | Improvement |
|-----------|---------|---------|-------------|
| App Launch (ViewModel init) | 3x | 1x | 66% reduction |
| Data Refresh (iterations) | 5n | 1n | 80% reduction |
| Persistence (per update) | Full encode | Debounced | 90% reduction |
| Token Hash (per call) | Reflection | Cached | 95% reduction |

### Memory Impact

| Component | Current | Optimal | Savings |
|-----------|---------|---------|---------|
| ViewModels | 3 instances | 1 instance | ~66% |
| Notification Subscribers | 3 | 1 | ~66% |
| Combine Pipelines | 3 | 1 | ~66% |

---

## 8. Recommendations Summary

### Immediate (P0)

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 1 | Share ViewModel via @EnvironmentObject | Critical | Medium |

### High Priority (P1)

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 2 | Remove deprecated `.synchronize()` calls | Medium | Low |

### Medium Priority (P2)

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 3 | Consolidate reduce operations | Medium | Low |
| 4 | Group @Published properties | Medium | Medium |
| 5 | Cache token hashes | Medium | Low |
| 6 | Debounce persistence writes | Medium | Medium |
| 7 | Ensure timer invalidation | Medium | Low |

### Low Priority (P3)

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 8 | Use @MainActor over DispatchQueue | Low | Medium |
| 9 | Deduplicate at source | Low | Low |
| 10 | Add explicit Combine cleanup | Low | Low |
| 11 | Extract shared code to package | Low | High |

---

## 9. Testing Recommendations

### Performance Testing

```swift
// Add performance tests for critical paths
func testRefreshDataPerformance() {
    let viewModel = AppUsageViewModel()
    // Seed with 50 apps

    measure {
        viewModel.refreshData()
    }
}

func testTokenHashPerformance() {
    let persistence = UsagePersistence()

    measure {
        for _ in 0..<1000 {
            _ = persistence.tokenHash(for: testToken)
        }
    }
}
```

### Memory Profiling

1. Use Instruments "Leaks" to verify no ViewModel leaks
2. Use "Allocations" to measure peak memory with single vs. multiple ViewModels
3. Profile Combine subscription counts

---

## Appendix A: Files Analyzed

```
ScreenTimeRewardsProject/
├── ScreenTimeRewards/
│   ├── ViewModels/
│   │   └── AppUsageViewModel.swift     ← CRITICAL issues
│   ├── Views/
│   │   ├── LearningTabView.swift       ← CRITICAL issues
│   │   ├── RewardsTabView.swift        ← CRITICAL issues
│   │   ├── AppUsageView.swift          ← CRITICAL issues
│   │   └── CategoryAssignmentView.swift
│   ├── Services/
│   │   └── ScreenTimeService.swift     ← Medium issues
│   └── Shared/
│       └── UsagePersistence.swift      ← Medium issues
└── ScreenTimeActivityExtension/
    └── DeviceActivityMonitorExtension.swift ← Low issues
```

---

## Appendix B: Code Metrics

| Metric | Value | Assessment |
|--------|-------|------------|
| @Published properties | 21 | High (recommend < 10) |
| .synchronize() calls | 8 | Should be 0 |
| ViewModel instances | 3 | Should be 1 |
| Reduce/filter iterations | 5 per refresh | Should be 1 |
| Debug print statements | 535 | OK (wrapped in #if DEBUG) |
| Weak self captures | 15 | Good |
| Timer instances | 1 | OK (ensure cleanup) |

---

*Report generated by system efficiency analysis*
