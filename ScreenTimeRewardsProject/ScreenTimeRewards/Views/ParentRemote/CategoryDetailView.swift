import SwiftUI

struct CategoryDetailView: View {
    let summary: CategoryUsageSummary

    @State private var selectedApp: UsageRecord?

    private let namingService = AppNameMappingService.shared

    var body: some View {
        List {
            Section(header: Text("Category Overview")) {
                HStack {
                    Text("Total Time")
                    Spacer()
                    Text(summary.formattedTime)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Total Points")
                    Spacer()
                    Text("\(summary.totalPoints)")
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Apps Monitored")
                    Spacer()
                    Text("\(summary.appCount)")
                        .fontWeight(.semibold)
                }
            }

            Section(header: Text("Individual Apps")) {
                ForEach(summary.apps.sorted { $0.totalSeconds > $1.totalSeconds }, id: \.recordID) { app in
                    Button(action: {
                        // Tap to edit name
                        selectedApp = app
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                // Use custom name if set, otherwise default
                                HStack(spacing: 6) {
                                    Text(displayName(for: app))
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    if namingService.hasCustomName(for: app.logicalID ?? "") {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "pencil.circle")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                HStack {
                                    Text(formatDate(app.sessionStart))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if let end = app.sessionEnd {
                                        Text("→ \(formatTime(end))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(formatSeconds(Int(app.totalSeconds)))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("\(app.earnedPoints) pts")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("App names are privacy-protected by iOS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.blue)
                        Text("Tap any app to give it a custom name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("\(summary.category) Apps")
        .sheet(item: $selectedApp) { app in
            AppNameEditorSheet(
                app: app,
                currentName: namingService.getCustomName(for: app.logicalID ?? "") ?? "",
                onSave: { newName in
                    if let logicalID = app.logicalID {
                        namingService.setCustomName(newName, for: logicalID)
                    }
                },
                onReset: {
                    if let logicalID = app.logicalID {
                        namingService.removeCustomName(for: logicalID)
                    }
                }
            )
        }
    }

    /// Get display name for an app (CloudKit synced name, local custom, or fallback)
    private func displayName(for app: UsageRecord) -> String {
        // 1. First check if CloudKit has a custom name from child device
        if let cloudKitName = app.displayName,
           !cloudKitName.isEmpty,
           !cloudKitName.hasPrefix("Unknown") {
            return cloudKitName
        }

        // 2. Check local custom name (parent's overrides)
        guard let logicalID = app.logicalID else {
            return "Unknown App"
        }
        if let customName = namingService.getCustomName(for: logicalID) {
            return customName
        }

        // 3. Fallback to privacy-protected naming
        let category = app.category ?? "Unknown"
        let appNumber = abs(logicalID.hashValue) % 100
        return "Privacy Protected \(category) App #\(appNumber)"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - App Name Editor Sheet
struct AppNameEditorSheet: View {
    let app: UsageRecord
    let currentName: String
    let onSave: (String) -> Void
    let onReset: () -> Void

    @State private var customName: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private var defaultName: String {
        let category = app.category ?? "Unknown"
        let appNumber = abs((app.logicalID ?? "").hashValue) % 100
        return "Privacy Protected \(category) App #\(appNumber)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Name:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(defaultName)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Custom Name")) {
                    TextField("Enter app name (e.g., Khan Academy)", text: $customName)
                        .focused($isTextFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            saveAndDismiss()
                        }

                    if !customName.isEmpty {
                        HStack {
                            Text("Preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(customName)
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Why name this app?")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        Text("Apple's privacy protections prevent apps from seeing actual app names. You can give this app a custom name to help you recognize it in future reports.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                if !currentName.isEmpty {
                    Section {
                        Button(role: .destructive, action: {
                            resetName()
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Default Name")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Name This App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                customName = currentName
                // Auto-focus keyboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private func saveAndDismiss() {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSave(trimmed)
            dismiss()
        }
    }

    private func resetName() {
        onReset()
        dismiss()
    }
}

struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryDetailView(
            summary: CategoryUsageSummary(
                category: "Learning",
                totalSeconds: 3600,
                appCount: 2,
                totalPoints: 120,
                apps: []
            )
        )
    }
}