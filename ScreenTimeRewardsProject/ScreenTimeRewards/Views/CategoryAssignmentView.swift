import SwiftUI
import FamilyControls

struct CategoryAssignmentView: View {
    @Environment(\.dismiss) var dismiss
    let selection: FamilyActivitySelection
    @Binding var categoryAssignments: [ApplicationToken: AppUsage.AppCategory]
    var onSave: () -> Void

    @State private var localAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Assign a category to each app for accurate tracking")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Selected Apps (\(selection.applications.count))")) {
                    ForEach(Array(selection.applications.enumerated()), id: \.element.token) { index, app in
                        if let token = app.token {
                            VStack(alignment: .leading, spacing: 8) {
                                // Use Label(token) to show actual app name and icon
                                Label(token)
                                    .font(.headline)

                                // Category picker
                                Picker("Category", selection: Binding(
                                    get: { localAssignments[token] ?? .other },
                                    set: { localAssignments[token] = $0 }
                                )) {
                                    ForEach(AppUsage.AppCategory.allCases, id: \.self) { category in
                                        HStack {
                                            Text(categoryIcon(for: category))
                                            Text(category.rawValue)
                                        }
                                        .tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    categorySummary
                }
            }
            .navigationTitle("Assign Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Monitor") {
                        categoryAssignments = localAssignments
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                initializeAssignments()
            }
        }
    }

    private var categorySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            ForEach(AppUsage.AppCategory.allCases, id: \.self) { category in
                let count = localAssignments.values.filter { $0 == category }.count
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

    private func initializeAssignments() {
        // Initialize with existing assignments or default to .other
        for app in selection.applications {
            if let token = app.token {
                localAssignments[token] = categoryAssignments[token] ?? .other
            }
        }
    }

    private func categoryIcon(for category: AppUsage.AppCategory) -> String {
        switch category {
        case .educational: return "📚"
        case .entertainment: return "🎬"
        case .games: return "🎮"
        case .social: return "💬"
        case .productivity: return "💼"
        case .utility: return "🔧"
        case .other: return "📱"
        }
    }
}
