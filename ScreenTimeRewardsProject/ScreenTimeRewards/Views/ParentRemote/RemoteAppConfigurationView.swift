import SwiftUI
import FamilyControls
import CoreData
import ManagedSettings

struct RemoteAppConfigurationView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var showingCategorySheet = false
    @State private var selectedApp: FullAppConfigDTO?
    @State private var tempCategory: AppUsage.AppCategory = .learning
    @State private var tempPoints: Int = 10

    /// Combined list of all app configurations from CloudKit
    private var allAppConfigs: [FullAppConfigDTO] {
        viewModel.childLearningAppsFullConfig + viewModel.childRewardAppsFullConfig
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Configuration")
                .font(.headline)

            if allAppConfigs.isEmpty && !viewModel.isLoading {
                EmptyConfigurationView()
            } else {
                AppConfigurationListView(
                    configurations: allAppConfigs,
                    onEdit: { config in
                        selectedApp = config
                        tempCategory = AppUsage.AppCategory(rawValue: config.category) ?? .learning
                        tempPoints = config.pointsPerMinute
                        showingCategorySheet = true
                    },
                    onToggleEnabled: { config in
                        // Toggle app enabled status
                        var mutableConfig = MutableAppConfigDTO(from: config)
                        mutableConfig.isEnabled = !config.isEnabled
                        Task {
                            await viewModel.sendConfigurationUpdate(mutableConfig)
                        }
                    },
                    onToggleBlocking: { config in
                        // Toggle app blocking
                        var mutableConfig = MutableAppConfigDTO(from: config)
                        mutableConfig.blockingEnabled = !config.blockingEnabled
                        Task {
                            await viewModel.sendConfigurationUpdate(mutableConfig)
                        }
                    }
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .sheet(isPresented: $showingCategorySheet) {
            if let app = selectedApp {
                CategoryAssignmentSheetDTO(
                    appConfiguration: app,
                    category: $tempCategory,
                    points: $tempPoints,
                    onSave: { category, points in
                        var mutableConfig = MutableAppConfigDTO(from: app)
                        mutableConfig.category = category.rawValue
                        mutableConfig.pointsPerMinute = points
                        Task {
                            await viewModel.sendConfigurationUpdate(mutableConfig)
                        }
                    }
                )
            }
        }
    }
}

private struct EmptyConfigurationView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "apps.iphone")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("No app configurations")
                .font(.headline)
                .foregroundColor(.gray)

            Text("Apps must be configured on the child's device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Why configure on child device?")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                Text("Apple's privacy protections prevent remote app configuration. The child needs to select and configure apps on their own device to protect their privacy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

private struct AppConfigurationListView: View {
    let configurations: [FullAppConfigDTO]
    let onEdit: (FullAppConfigDTO) -> Void
    let onToggleEnabled: (FullAppConfigDTO) -> Void
    let onToggleBlocking: (FullAppConfigDTO) -> Void
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
        let columns = horizontalSizeClass == .regular ? [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ] : [
            GridItem(.flexible())
        ]

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(configurations, id: \.logicalID) { config in
                AppConfigurationRowDTO(
                    configuration: config,
                    onEdit: { onEdit(config) },
                    onToggleEnabled: { onToggleEnabled(config) },
                    onToggleBlocking: { onToggleBlocking(config) }
                )
            }
        }
    }
}

private struct AppConfigurationRow: View {
    let configuration: AppConfiguration
    let onEdit: () -> Void
    let onToggleEnabled: () -> Void
    let onToggleBlocking: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // App icon
                CachedAppIcon(
                    iconURL: configuration.iconURL,
                    identifier: configuration.logicalID ?? "unknown",
                    size: 44,
                    fallbackSymbol: (configuration.category ?? "learning").lowercased() == "learning" ? "book.fill" : "gamecontroller.fill"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(configuration.displayName ?? "Unknown App")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        CategoryTag(category: configuration.category ?? "learning")

                        if configuration.pointsPerMinute > 0 {
                            Text("\(configuration.pointsPerMinute) pts/min")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    // Enabled toggle
                    Toggle("", isOn: Binding(
                        get: { configuration.isEnabled },
                        set: { _ in onToggleEnabled() }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .green))

                    // Blocking toggle
                    Button(action: onToggleBlocking) {
                        Image(systemName: configuration.blockingEnabled ? "lock" : "lock.open")
                            .foregroundColor(configuration.blockingEnabled ? .red : .green)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Edit button
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .contentShape(Rectangle()) // Make entire row tappable
    }
}

private struct CategoryTag: View {
    let category: String

    var body: some View {
        Text(category.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.2))
            .foregroundColor(categoryColor)
            .cornerRadius(6)
    }

    private var categoryColor: Color {
        switch category.lowercased() {
        case "learning":
            return .blue
        case "reward":
            return .green
        default:
            return .gray
        }
    }
}

// MARK: - DTO-based Views (use CloudKit-fetched data with displayName/iconURL)

private struct AppConfigurationRowDTO: View {
    let configuration: FullAppConfigDTO
    let onEdit: () -> Void
    let onToggleEnabled: () -> Void
    let onToggleBlocking: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // App icon from CloudKit
                CachedAppIcon(
                    iconURL: configuration.iconURL,
                    identifier: configuration.logicalID,
                    size: 44,
                    fallbackSymbol: configuration.category.lowercased() == "learning" ? "book.fill" : "gamecontroller.fill"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(configuration.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        CategoryTag(category: configuration.category)

                        if configuration.pointsPerMinute > 0 {
                            Text("\(configuration.pointsPerMinute) pts/min")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    // Enabled toggle
                    Toggle("", isOn: Binding(
                        get: { configuration.isEnabled },
                        set: { _ in onToggleEnabled() }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .green))

                    // Blocking toggle
                    Button(action: onToggleBlocking) {
                        Image(systemName: configuration.blockingEnabled ? "lock" : "lock.open")
                            .foregroundColor(configuration.blockingEnabled ? .red : .green)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Edit button
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .contentShape(Rectangle())
    }
}

private struct CategoryAssignmentSheetDTO: View {
    let appConfiguration: FullAppConfigDTO
    @Binding var category: AppUsage.AppCategory
    @Binding var points: Int
    let onSave: (AppUsage.AppCategory, Int) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("App") {
                    HStack(spacing: 12) {
                        CachedAppIcon(
                            iconURL: appConfiguration.iconURL,
                            identifier: appConfiguration.logicalID,
                            size: 40,
                            fallbackSymbol: "app.fill"
                        )
                        Text(appConfiguration.displayName)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("Learning").tag(AppUsage.AppCategory.learning)
                        Text("Reward").tag(AppUsage.AppCategory.reward)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section("Points per Minute") {
                    HStack {
                        Text("Points")
                        Spacer()
                        TextField("Points", value: $points, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }
            .navigationTitle("Configure App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(category, points)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(points <= 0)
                }
            }
        }
    }
}

// MARK: - Legacy CoreData-based Views (kept for backward compatibility)

private struct CategoryAssignmentSheet: View {
    let appConfiguration: AppConfiguration
    @Binding var category: AppUsage.AppCategory
    @Binding var points: Int
    let onSave: (AppUsage.AppCategory, Int) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("App") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(appConfiguration.displayName ?? "Unknown App")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("Learning").tag(AppUsage.AppCategory.learning)
                        Text("Reward").tag(AppUsage.AppCategory.reward)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section("Points per Minute") {
                    HStack {
                        Text("Points")
                        Spacer()
                        TextField("Points", value: $points, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }
            .navigationTitle("Configure App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(category, points)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(points <= 0)
                }
            }
        }
    }
}

struct RemoteAppConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()
        
        // Note: In a real preview, we would need a proper Core Data context
        // For now, we'll just show the view without mock data
        
        return RemoteAppConfigurationView(viewModel: viewModel)
            .padding()
    }
}

