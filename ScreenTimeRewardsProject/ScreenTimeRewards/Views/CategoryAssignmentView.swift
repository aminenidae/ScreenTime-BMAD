import SwiftUI
import FamilyControls
import ManagedSettings

struct CategoryAssignmentEntry: Identifiable {
    let token: ApplicationToken
    let displayName: String
    let sortKey: String
    var id: String { sortKey }
}

struct CategoryAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    // Task M: Access the ViewModel through environment
    @EnvironmentObject var viewModel: AppUsageViewModel

    let selection: FamilyActivitySelection
    @Binding var categoryAssignments: [ApplicationToken: AppUsage.AppCategory]
    @Binding var rewardPoints: [ApplicationToken: Int]
    let fixedCategory: AppUsage.AppCategory?
    let usageTimes: [ApplicationToken: TimeInterval]
    var onSave: () -> Void
    var onCancel: () -> Void = {}

    @State private var localCategoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    @State private var localRewardPoints: [ApplicationToken: Int] = [:]
    
    // Task M: Use @Published state for duplicate assignment errors instead of NotificationCenter
    @State private var duplicateAssignmentError: String?

    private let usagePersistence = UsagePersistence()

    private var pointsSummaryTitle: String {
        switch fixedCategory {
        case .learning:
            return "Learning Points Summary"
        case .reward:
            return "Reward Points Summary"
        case .none:
            return "Reward Points Summary"
        }
    }

    private var totalPointsLabel: String {
        switch fixedCategory {
        case .learning:
            return "Total Learning Points:"
        case .reward:
            return "Total Reward Points:"
        case .none:
            return "Total Reward Points:"
        }
    }

    private var applicationEntries: [CategoryAssignmentEntry] {
        // Task 0: When fixedCategory is set, build entries from the passed selection
        // The selection now includes the pending tokens from the picker, but can still carry
        // cached applications from other tabs. Filter by the active token set so each sheet
        // only shows the apps relevant to the current category.
        let tokenSet = Set(selection.applicationTokens)

        // When the selection contains explicit tokens (e.g., filtered learning/reward lists)
        // prefer those. Otherwise fall back to any hydrated applications we received from the
        // picker to keep manual categorization working.
        let baseTokens: [ApplicationToken]
        if !tokenSet.isEmpty {
            baseTokens = Array(tokenSet)
        } else {
            baseTokens = selection.applications.compactMap { $0.token }
        }

        let entries = baseTokens.compactMap { token -> CategoryAssignmentEntry? in
            let sortKey = usagePersistence.getTokenArchiveHash(for: token)

            // Pull the localized name from the selection when available, otherwise fall back
            // to cached names from the ViewModel/service.
            let selectionName = selection.applications.first { $0.token == token }?.localizedDisplayName
            let displayName = selectionName
                ?? viewModel.resolvedDisplayName(for: token)
                ?? "Unknown App"

            return CategoryAssignmentEntry(token: token, displayName: displayName, sortKey: sortKey)
        }

        return entries.sorted { $0.sortKey < $1.sortKey }
    }

    var body: some View {
        NavigationView {
            List {
                headerSection
                // Task M: Add duplicate assignment error display using @Published state
                if let error = duplicateAssignmentError {
                    errorSection(error)
                }
                applicationsSection
                Section { categorySummary }
                Section { rewardPointsSummary }
            }
            .navigationTitle("Assign Categories & Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: initializeAssignments)
            // Task M: Listen for duplicate assignment errors through @Published state
            // Removed NotificationCenter observer since we're using @Published state directly
        }
    }
    
    // Task M: Add error section to display duplicate assignment errors
    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Assignment Conflict")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.orange.opacity(0.1))
    }

    private var categorySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category Summary")
                .font(.headline)

            ForEach([AppUsage.AppCategory.learning, AppUsage.AppCategory.reward], id: \.self) { category in
                let count = localCategoryAssignments.values.filter { $0 == category }.count
                if count > 0 {
                    HStack {
                        Text(categoryIcon(for: category))
                        Text(category.rawValue)
                        Spacer()
                        Text("\(count) app\(count == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var rewardPointsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pointsSummaryTitle)
                .font(.headline)
                
            let totalPoints = localRewardPoints.values.reduce(0, +)
            HStack {
                Text(totalPointsLabel)
                Spacer()
                Text("\(totalPoints)")
                    .foregroundColor(.secondary)
            }
            
            ForEach(applicationEntries) { entry in
                if let points = localRewardPoints[entry.token] {
                    HStack {
                        if #available(iOS 15.2, *) {
                            Label(entry.token)
                                .font(.caption)
                        } else {
                            Text(entry.displayName)
                                .font(.caption)
                        }
                        Spacer()
                        Text("\(points) pts")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func initializeAssignments() {
        for entry in applicationEntries {
            // When fixedCategory is set, use that category for all entries
            // Otherwise, use existing assignments or default to .learning
            let category = fixedCategory ?? categoryAssignments[entry.token] ?? .learning
            localCategoryAssignments[entry.token] = category
            localRewardPoints[entry.token] = rewardPoints[entry.token] ?? getDefaultRewardPoints(for: category)
        }
    }

    private func getDefaultRewardPoints(for category: AppUsage.AppCategory) -> Int {
        switch category {
        case .learning:
            return 5  // Learning: minimum 5 points
        case .reward:
            return 50  // Reward: minimum 50 points
        }
    }

    private func pointsRange(for category: AppUsage.AppCategory) -> (min: Int, max: Int, step: Int) {
        switch category {
        case .learning:
            return (5, 500, 5)  // Learning: 5-500, step by 5
        case .reward:
            return (50, 1000, 10)  // Reward: 50-1000, step by 10
        }
    }

    private func pointsLabel(for category: AppUsage.AppCategory) -> String {
        switch category {
        case .learning:
            return "Earn per minute:"
        case .reward:
            return "Cost per minute:"
        }
    }

    private func categoryIcon(for category: AppUsage.AppCategory) -> String {
        switch category {
        case .learning: return "📚"
        case .reward: return "🏆"
        }
    }

    /// Format usage time for display
    private func formatUsageTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            let seconds = Int(timeInterval) % 60
            return "\(seconds)s"
        }
    }
}

// MARK: - Subviews
private extension CategoryAssignmentView {
    var headerSection: some View {
        Section {
            if let category = fixedCategory {
                Text("Set points per minute for these \(category.rawValue.lowercased()) apps")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Assign apps to Learning or Reward categories for tracking")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    var applicationsSection: some View {
        Section(header: Text("Selected Apps (\(applicationEntries.count))")) {
            ForEach(Array(applicationEntries.enumerated()), id: \.element.id) { index, entry in
                appRow(for: entry, index: index)
            }
        }
    }

    @ViewBuilder
    func appRow(for entry: CategoryAssignmentEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow(for: entry, index: index)
            if fixedCategory == nil {
                categoryPicker(for: entry)
            }
            usageRow(for: entry)
            pointsRow(for: entry)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func headerRow(for entry: CategoryAssignmentEntry, index: Int) -> some View {
        HStack {
            if #available(iOS 15.2, *) {
                Label(entry.token)
                    .font(.headline)
            } else {
                Text(entry.displayName.isEmpty ? "App \(index)" : entry.displayName)
                    .font(.headline)
            }
            
            Spacer()
            
            // Task M: Add indicator for apps that have been previously removed and re-added
            if let logicalID = usagePersistence.logicalID(for: usagePersistence.getTokenArchiveHash(for: entry.token)),
               let persistedApp = usagePersistence.app(for: logicalID),
               persistedApp.totalSeconds == 0 && persistedApp.earnedPoints == 0 {
                // Check if this is a re-added app by looking at the creation date
                // If the app was created recently but has zero usage, it's likely a re-added app
                let timeSinceCreation = Date().timeIntervalSince(persistedApp.createdAt)
                if timeSinceCreation < 60 { // Created within the last minute
                    Text("NEW")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
        }
    }

    @ViewBuilder
    func categoryPicker(for entry: CategoryAssignmentEntry) -> some View {
        Picker("Category", selection: Binding(
            get: { localCategoryAssignments[entry.token] ?? .learning },
            set: { 
                localCategoryAssignments[entry.token] = $0
                // Task M: Validate assignments immediately when category changes using @Published state
                validateAssignments()
            }
        )) {
            ForEach([AppUsage.AppCategory.learning, AppUsage.AppCategory.reward], id: \.self) { category in
                HStack {
                    Text(categoryIcon(for: category))
                    Text(category.rawValue)
                }
                .tag(category)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    func usageRow(for entry: CategoryAssignmentEntry) -> some View {
        if let usageTime = usageTimes[entry.token], usageTime > 0 {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Used: \(formatUsageTime(usageTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            // Task M: Show message for apps with zero usage (newly added or reset)
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("No usage recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    func pointsRow(for entry: CategoryAssignmentEntry) -> some View {
        let category = fixedCategory ?? localCategoryAssignments[entry.token] ?? .learning
        let (minPoints, maxPoints, stepValue) = pointsRange(for: category)
        HStack {
            Text(pointsLabel(for: category))
            Spacer()
            Stepper(
                "\(localRewardPoints[entry.token] ?? minPoints)",
                value: Binding(
                    get: { localRewardPoints[entry.token] ?? minPoints },
                    set: { 
                        localRewardPoints[entry.token] = $0
                        // Task M: Validate assignments immediately when points change using @Published state
                        validateAssignments()
                    }
                ),
                in: minPoints...maxPoints,
                step: stepValue
            )
            .frame(width: 140)
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: handleCancel)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save & Monitor", action: handleSave)
                .fontWeightCompatible(.semibold)
        }
    }

    // Task M: Add validation method with detailed instrumentation
    private func validateAssignments() {
        #if DEBUG
        print("[CategoryAssignmentView] 🔍 VALIDATION TRIGGERED")
        print("[CategoryAssignmentView]   Local assignments count: \(localCategoryAssignments.count)")
        for (token, category) in localCategoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[CategoryAssignmentView]     Local: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        
        print("[CategoryAssignmentView]   Stored assignments count: \(categoryAssignments.count)")
        for (token, category) in categoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[CategoryAssignmentView]     Stored: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif
        
        // Validate local assignments and update error state through @Published property
        let isValid = viewModel.validateLocalAssignments(localCategoryAssignments)
        if !isValid, let error = viewModel.duplicateAssignmentError {
            duplicateAssignmentError = error
        } else {
            duplicateAssignmentError = nil
        }
    }

    func handleSave() {
        #if DEBUG
        print("[CategoryAssignmentView] 🔄 HANDLE SAVE STARTED")
        print("[CategoryAssignmentView]   Fixed category: \(fixedCategory?.rawValue ?? "nil")")
        print("[CategoryAssignmentView]   Application entries count: \(applicationEntries.count)")
        print("[CategoryAssignmentView]   Local assignments count: \(localCategoryAssignments.count)")
        for (token, category) in localCategoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[CategoryAssignmentView]     Local: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        
        print("[CategoryAssignmentView]   Stored assignments count: \(categoryAssignments.count)")
        for (token, category) in categoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[CategoryAssignmentView]     Stored: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif
        
        // Task M: Validate assignments before saving using @Published state
        if !viewModel.validateLocalAssignments(localCategoryAssignments) {
            // Validation failed due to duplicates - don't dismiss the sheet
            // The error message will be shown in the UI through @Published state
            if let error = viewModel.duplicateAssignmentError {
                duplicateAssignmentError = error
            }
            
            #if DEBUG
            print("[CategoryAssignmentView] ❌ VALIDATION FAILED - DUPLICATE ASSIGNMENTS DETECTED")
            #endif
            
            return
        }
        
        #if DEBUG
        print("[CategoryAssignmentView] ✅ VALIDATION PASSED - NO DUPLICATE ASSIGNMENTS")
        #endif
        
        // Task N: Preserve Category Assignments Across Sheets
        // Create a copy of the current assignments to merge into
        var mergedCategoryAssignments = categoryAssignments
        var mergedRewardPoints = rewardPoints
        
        #if DEBUG
        let initialLearningCount = mergedCategoryAssignments.filter { $0.value == .learning }.count
        let initialRewardCount = mergedCategoryAssignments.filter { $0.value == .reward }.count
        print("[CategoryAssignmentView] 🔄 Preserving category assignments across sheets")
        print("[CategoryAssignmentView]   Initial counts - Learning: \(initialLearningCount), Reward: \(initialRewardCount)")
        print("[CategoryAssignmentView]   Current selection has \(applicationEntries.count) apps")
        #endif
        
        if let fixedCategory = fixedCategory {
            // When fixedCategory is specified (Learning or Reward tabs), only update assignments for apps in the current selection
            // Preserve existing assignments for apps not in the current selection
            for entry in applicationEntries {
                mergedCategoryAssignments[entry.token] = fixedCategory
                if let points = localRewardPoints[entry.token] {
                    mergedRewardPoints[entry.token] = points
                }
            }
        } else {
            // When no fixedCategory is specified (manual categorization), update all local assignments
            // But still preserve assignments for tokens not in the current selection
            for (token, category) in localCategoryAssignments {
                mergedCategoryAssignments[token] = category
            }
            for (token, points) in localRewardPoints {
                mergedRewardPoints[token] = points
            }
        }
        
        #if DEBUG
        let finalLearningCount = mergedCategoryAssignments.filter { $0.value == .learning }.count
        let finalRewardCount = mergedCategoryAssignments.filter { $0.value == .reward }.count
        print("[CategoryAssignmentView]   Final counts - Learning: \(finalLearningCount), Reward: \(finalRewardCount)")
        print("[CategoryAssignmentView]   ✅ Preserved \(abs(finalLearningCount - initialLearningCount)) learning apps")
        print("[CategoryAssignmentView]   ✅ Preserved \(abs(finalRewardCount - initialRewardCount)) reward apps")
        
        // Detailed logging of what changed
        print("[CategoryAssignmentView]   MERGE DETAILS:")
        for (token, category) in mergedCategoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            if let oldCategory = categoryAssignments[token] {
                if oldCategory != category {
                    print("[CategoryAssignmentView]     Updated: \(appName) (token: \(token.hashValue)) from \(oldCategory.rawValue) to \(category.rawValue)")
                }
            } else {
                print("[CategoryAssignmentView]     Added: \(appName) (token: \(token.hashValue)) as \(category.rawValue)")
            }
        }
        
        // Check for removed assignments
        for (token, oldCategory) in categoryAssignments {
            if mergedCategoryAssignments[token] == nil {
                let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
                print("[CategoryAssignmentView]     Removed: \(appName) (token: \(token.hashValue)) previously \(oldCategory.rawValue)")
            }
        }
        #endif
        
        // Update the bindings with merged data
        categoryAssignments = mergedCategoryAssignments
        rewardPoints = mergedRewardPoints
        
        // Task 0: Clear the pending selection after successful save
        viewModel.pendingSelection = FamilyActivitySelection()
        
        #if DEBUG
        print("[CategoryAssignmentView] 🔄 HANDLE SAVE COMPLETED")
        print("[CategoryAssignmentView]   Final stored assignments count: \(categoryAssignments.count)")
        for (token, category) in categoryAssignments {
            let appName = selection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[CategoryAssignmentView]     Final: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif
        
        onSave()
        dismiss()
    }

    func handleCancel() {
        onCancel()
        dismiss()
    }
}

// Extension for iOS version compatibility
extension View {
    /// Applies font weight compatible with different iOS versions
    @ViewBuilder
    func fontWeightCompatible(_ weight: Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(weight)
        } else {
            // For iOS 15, we can't use fontWeight, so we'll use a different approach
            // For semibold, we can use a custom font weight or just the default styling
            self
        }
    }
}
