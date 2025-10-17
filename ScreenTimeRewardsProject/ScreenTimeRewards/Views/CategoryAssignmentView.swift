import SwiftUI
import FamilyControls
import ManagedSettings

struct CategoryAssignmentView: View {
    @Environment(\.dismiss) var dismiss
    let selection: FamilyActivitySelection
    @Binding var categoryAssignments: [ApplicationToken: AppUsage.AppCategory]
    @Binding var rewardPoints: [ApplicationToken: Int]
    var onSave: () -> Void

    @State private var localCategoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    @State private var localRewardPoints: [ApplicationToken: Int] = [:]

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Assign apps to Learning or Reward categories for tracking")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Selected Apps (\(selection.applications.count))")) {
                    ForEach(Array(selection.applications.enumerated()), id: \.element.token) { index, app in
                        if let token = app.token {
                            VStack(alignment: .leading, spacing: 8) {
                                // Use Label(token) to show actual app name and icon
                                if #available(iOS 15.2, *) {
                                    Label(token)
                                        .font(.headline)
                                } else {
                                    // Fallback for older iOS versions
                                    Text("App \(index)")
                                        .font(.headline)
                                }

                                // Category picker - only two options now
                                Picker("Category", selection: Binding(
                                    get: { localCategoryAssignments[token] ?? .learning },
                                    set: { localCategoryAssignments[token] = $0 }
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

                                // Reward points input
                                HStack {
                                    Text("Reward Points:")
                                    Spacer()
                                    Stepper(
                                        "\(localRewardPoints[token] ?? 10)",
                                        value: Binding(
                                            get: { localRewardPoints[token] ?? 10 },
                                            set: { localRewardPoints[token] = $0 }
                                        ),
                                        in: 0...100,
                                        step: 5
                                    )
                                    .frame(width: 120)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    categorySummary
                }
                
                Section {
                    rewardPointsSummary
                }
            }
            .navigationTitle("Assign Categories & Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Monitor") {
                        categoryAssignments = localCategoryAssignments
                        rewardPoints = localRewardPoints
                        onSave()
                        dismiss()
                    }
                    .fontWeightCompatible(.semibold)
                }
            }
            .onAppear {
                initializeAssignments()
            }
        }
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
            
            ForEach(Array(localRewardPoints.keys), id: \.self) { token in
                if let app = selection.applications.first(where: { $0.token == token }),
                   let points = localRewardPoints[token] {
                    HStack {
                        if #available(iOS 15.2, *) {
                            Label(app.token!)
                                .font(.caption)
                        } else {
                            Text(app.localizedDisplayName ?? "Unknown App")
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
        // Initialize with existing assignments or defaults
        for app in selection.applications {
            if let token = app.token {
                localCategoryAssignments[token] = categoryAssignments[token] ?? .learning
                localRewardPoints[token] = rewardPoints[token] ?? getDefaultRewardPoints(for: localCategoryAssignments[token] ?? .learning)
            }
        }
    }
    
    private func getDefaultRewardPoints(for category: AppUsage.AppCategory) -> Int {
        switch category {
        case .learning:
            return 20
        case .reward:
            return 10
        }
    }

    private func categoryIcon(for category: AppUsage.AppCategory) -> String {
        switch category {
        case .learning: return "📚"
        case .reward: return "🏆"
        }
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