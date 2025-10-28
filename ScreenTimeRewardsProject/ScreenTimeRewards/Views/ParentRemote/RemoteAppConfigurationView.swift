import SwiftUI
import FamilyControls
import CoreData

struct RemoteAppConfigurationView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var showingCategorySheet = false
    @State private var selectedApp: AppConfiguration?
    @State private var tempCategory: AppUsage.AppCategory = .learning
    @State private var tempPoints: Int = 10
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("App Configuration")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    // Add new app configuration
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if viewModel.appConfigurations.isEmpty && !viewModel.isLoading {
                EmptyConfigurationView()
            } else {
                AppConfigurationListView(
                    configurations: viewModel.appConfigurations,
                    onEdit: { config in
                        selectedApp = config
                        tempCategory = AppUsage.AppCategory(rawValue: config.category ?? "learning") ?? .learning
                        tempPoints = Int(config.pointsPerMinute)
                        showingCategorySheet = true
                    },
                    onToggleEnabled: { config in
                        // Toggle app enabled status
                        let updatedConfig = config
                        var mutableConfig = updatedConfig
                        mutableConfig.isEnabled = !config.isEnabled
                        Task {
                            await viewModel.sendConfigurationUpdate(mutableConfig)
                        }
                    },
                    onToggleBlocking: { config in
                        // Toggle app blocking
                        let updatedConfig = config
                        var mutableConfig = updatedConfig
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
                CategoryAssignmentSheet(
                    appConfiguration: app,
                    category: $tempCategory,
                    points: $tempPoints,
                    onSave: { category, points in
                        let updatedConfig = app
                        var mutableConfig = updatedConfig
                        mutableConfig.category = category.rawValue
                        mutableConfig.pointsPerMinute = Int16(points)
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
        VStack(spacing: 8) {
            Image(systemName: "apps.iphone")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No app configurations")
                .foregroundColor(.gray)
            Text("Apps will appear here once configured on the child device")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

private struct AppConfigurationListView: View {
    let configurations: [AppConfiguration]
    let onEdit: (AppConfiguration) -> Void
    let onToggleEnabled: (AppConfiguration) -> Void
    let onToggleBlocking: (AppConfiguration) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(configurations, id: \.logicalID) { config in
                AppConfigurationRow(
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.displayName ?? "Unknown App")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
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
            
            Spacer()
            
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
        .padding(.vertical, 8)
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

// Import AppUsage to access AppCategory enum
import Foundation

struct RemoteAppConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()
        
        // Note: In a real preview, we would need a proper Core Data context
        // For now, we'll just show the view without mock data
        
        return RemoteAppConfigurationView(viewModel: viewModel)
            .padding()
    }
}