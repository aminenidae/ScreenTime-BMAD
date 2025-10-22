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
    
    // Task M: Access the view model to get duplicate assignment errors
    @State private var duplicateAssignmentError: String?

    private let usagePersistence = UsagePersistence()

    private var applicationEntries: [CategoryAssignmentEntry] {
        selection.applications.compactMap { application in
            guard let token = application.token else { return nil }
            let sortKey = usagePersistence.getTokenArchiveHash(for: token)
            let name = application.localizedDisplayName ?? "Unknown App"
            return CategoryAssignmentEntry(token: token, displayName: name, sortKey: sortKey)
        }.sorted { $0.sortKey < $1.sortKey }
    }

    var body: some View {
        NavigationView {
            List {
                headerSection
                // Task M: Add duplicate assignment error display
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
            // Task M: Listen for duplicate assignment errors
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DuplicateAssignmentError"))) { notification in
                if let errorMessage = notification.object as? String {
                    duplicateAssignmentError = errorMessage
                }
            }
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
            Text("Reward Points Summary")
                .font(.headline)
                
            let totalPoints = localRewardPoints.values.reduce(0, +)
            HStack {
                Text("Total Reward Points:")
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
        if #available(iOS 15.2, *) {
            Label(entry.token)
                .font(.headline)
        } else {
            Text(entry.displayName.isEmpty ? "App \(index)" : entry.displayName)
                .font(.headline)
        }
    }

    @ViewBuilder
    func categoryPicker(for entry: CategoryAssignmentEntry) -> some View {
        Picker("Category", selection: Binding(
            get: { localCategoryAssignments[entry.token] ?? .learning },
            set: { localCategoryAssignments[entry.token] = $0 }
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
                    set: { localRewardPoints[entry.token] = $0 }
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

    func handleSave() {
        categoryAssignments = localCategoryAssignments
        rewardPoints = localRewardPoints
        
        // Task M: Validate assignments before saving
        if !viewModel.validateAndHandleAssignments() {
            // Validation failed due to duplicates - don't dismiss the sheet
            // The error message will be shown in the UI
            return
        }
        
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