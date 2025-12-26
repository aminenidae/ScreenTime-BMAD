import SwiftUI
import FamilyControls
import CoreData

struct PairingConfigView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var viewModel: AppUsageViewModel

    private var usagePersistence: UsagePersistence {
        viewModel.usagePersistence
    }
    @State private var editedNames: [String: String] = [:]
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var focusedAppID: String?

    private var learningApps: [LearningAppSnapshot] {
        viewModel.learningSnapshots
    }

    private var rewardApps: [RewardAppSnapshot] {
        viewModel.rewardSnapshots
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Educational Header
                        educationalHeaderCard

                        // Learning Apps Section
                        if !learningApps.isEmpty {
                            learningAppsSection
                        }

                        // Reward Apps Section
                        if !rewardApps.isEmpty {
                            rewardAppsSection
                        }

                        // Empty State
                        if learningApps.isEmpty && rewardApps.isEmpty {
                            emptyStateView
                        }

                        // Bottom padding
                        Color.clear.frame(height: 24)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Pairing Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? AppTheme.lightCream : AppTheme.vibrantTeal)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveChanges) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark
                                    ? (hasChanges ? AppTheme.lightCream : AppTheme.lightCream.opacity(0.5))
                                    : (hasChanges ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.5)))
                        }
                    }
                    .disabled(isSaving || !hasChanges)
                }
            }
            .alert("Changes Saved", isPresented: $showSaveConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("App names have been saved and will sync to the parent device.")
            }
        }
        .onAppear {
            loadCurrentNames()
        }
    }

    // MARK: - Educational Header

    private var educationalHeaderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("WHY MANUAL NAMING?")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Text("Apple's privacy protections prevent apps from automatically seeing the names of installed applications on your child's device.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Tap each app and enter its name so you can monitor usage on your parent device.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Learning Apps Section

    private var learningAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("LEARNING APPS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text("\(learningApps.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                    )
            }
            .padding(.horizontal, 4)

            // App List
            VStack(spacing: 10) {
                ForEach(learningApps) { app in
                    learningAppRow(for: app)
                }
            }
        }
    }

    // MARK: - Reward Apps Section

    private var rewardAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.playfulCoral)

                Text("REWARD APPS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text("\(rewardApps.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.playfulCoral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.playfulCoral.opacity(0.15))
                    )
            }
            .padding(.horizontal, 4)

            // App List
            VStack(spacing: 10) {
                ForEach(rewardApps) { app in
                    rewardAppRow(for: app)
                }
            }
        }
    }

    // MARK: - Learning App Row

    private func learningAppRow(for app: LearningAppSnapshot) -> some View {
        let needsNaming = viewModel.needsNaming(app.displayName)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // App Icon with badge overlay
                ZStack(alignment: .topTrailing) {
                    if #available(iOS 15.2, *) {
                        Label(app.token)
                            .labelStyle(.iconOnly)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.vibrantTeal.opacity(0.15))
                                .frame(width: 40, height: 40)

                            Image(systemName: "book.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.vibrantTeal)
                        }
                    }

                    // Show badge if app needs naming
                    if needsNaming {
                        NotificationBadge(size: 10)
                            .offset(x: 3, y: -3)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Display app name
                    if #available(iOS 15.2, *) {
                        Label(app.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    } else {
                        if let editedName = editedNames[app.logicalID], !editedName.isEmpty {
                            Text(editedName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else if !app.displayName.isEmpty && app.displayName != "Unknown App" {
                            Text(app.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else {
                            Text("Unnamed App")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .italic()
                        }
                    }

                    Text("Learning • \(app.pointsPerMinute) pts/min")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
                }

                Spacer()
            }

            // Text Field
            TextField("Enter app name (e.g., Khan Academy)...", text: bindingForLearning(app))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.inputBackground(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    focusedAppID == app.logicalID
                                        ? AppTheme.vibrantTeal
                                        : AppTheme.border(for: colorScheme),
                                    lineWidth: focusedAppID == app.logicalID ? 2 : 1
                                )
                        )
                )
                .onTapGesture {
                    focusedAppID = app.logicalID
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Reward App Row

    private func rewardAppRow(for app: RewardAppSnapshot) -> some View {
        let needsNaming = viewModel.needsNaming(app.displayName)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // App Icon with badge overlay
                ZStack(alignment: .topTrailing) {
                    if #available(iOS 15.2, *) {
                        Label(app.token)
                            .labelStyle(.iconOnly)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.playfulCoral.opacity(0.15))
                                .frame(width: 40, height: 40)

                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.playfulCoral)
                        }
                    }

                    // Show badge if app needs naming
                    if needsNaming {
                        NotificationBadge(size: 10)
                            .offset(x: 3, y: -3)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Display app name
                    if #available(iOS 15.2, *) {
                        Label(app.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    } else {
                        if let editedName = editedNames[app.logicalID], !editedName.isEmpty {
                            Text(editedName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else if !app.displayName.isEmpty && app.displayName != "Unknown App" {
                            Text(app.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else {
                            Text("Unnamed App")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .italic()
                        }
                    }

                    Text("Reward")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
                }

                Spacer()
            }

            // Text Field
            TextField("Enter app name (e.g., YouTube)...", text: bindingForReward(app))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.inputBackground(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    focusedAppID == app.logicalID
                                        ? AppTheme.playfulCoral
                                        : AppTheme.border(for: colorScheme),
                                    lineWidth: focusedAppID == app.logicalID ? 2 : 1
                                )
                        )
                )
                .onTapGesture {
                    focusedAppID = app.logicalID
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.playfulCoral.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))

            Text("No Apps Configured")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Configure learning and reward apps on this child device first.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: saveChanges) {
            HStack {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))

                    Text("Save App Names")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.vibrantTeal)
            )
        }
        .disabled(isSaving || !hasChanges)
        .opacity(hasChanges ? 1.0 : 0.5)
    }

    // MARK: - Helper Functions

    private func getCurrentDisplayName(for logicalID: String) -> String? {
        #if DEBUG
        print("[PairingConfigView] 🔍 getCurrentDisplayName(logicalID: \(logicalID))")
        #endif
        
        if let persistedApp = usagePersistence.app(for: logicalID) {
            #if DEBUG
            print("[PairingConfigView] 🔍   Found persisted app: '\(persistedApp.displayName)'")
            #endif
            return persistedApp.displayName
        }
        
        #if DEBUG
        print("[PairingConfigView] 🔍   No persisted app found")
        #endif
        return nil
    }

    private func bindingForLearning(_ app: LearningAppSnapshot) -> Binding<String> {
        Binding(
            get: {
                editedNames[app.logicalID] ?? ""
            },
            set: { newValue in
                editedNames[app.logicalID] = newValue
            }
        )
    }

    private func bindingForReward(_ app: RewardAppSnapshot) -> Binding<String> {
        Binding(
            get: {
                editedNames[app.logicalID] ?? ""
            },
            set: { newValue in
                editedNames[app.logicalID] = newValue
            }
        )
    }

    private func loadCurrentNames() {
        #if DEBUG
        print("[PairingConfigView] 🔍 loadCurrentNames() called")
        print("[PairingConfigView] 🔍 Learning apps count: \(learningApps.count)")
        print("[PairingConfigView] 🔍 Reward apps count: \(rewardApps.count)")
        #endif
        
        // Pre-populate editedNames with current values, but skip "Unknown App" entries
        for app in learningApps {
            #if DEBUG
            print("[PairingConfigView] 🔍 Checking learning app - logicalID: \(app.logicalID)")
            print("[PairingConfigView] 🔍   Snapshot displayName: '\(app.displayName)'")
            #endif
            
            if let displayName = getCurrentDisplayName(for: app.logicalID) {
                #if DEBUG
                print("[PairingConfigView] 🔍   Persisted displayName: '\(displayName)'")
                print("[PairingConfigView] 🔍   isEmpty: \(displayName.isEmpty)")
                print("[PairingConfigView] 🔍   hasPrefix('Unknown App'): \(displayName.hasPrefix("Unknown App"))")
                #endif
                
                if !displayName.isEmpty && !displayName.hasPrefix("Unknown App") {
                    editedNames[app.logicalID] = displayName
                    #if DEBUG
                    print("[PairingConfigView] ✅ Loaded name '\(displayName)' for logicalID: \(app.logicalID)")
                    #endif
                } else {
                    #if DEBUG
                    print("[PairingConfigView] ⚠️ Skipped loading name (empty or Unknown App)")
                    #endif
                }
            } else {
                #if DEBUG
                print("[PairingConfigView] ⚠️ No persisted app found for logicalID: \(app.logicalID)")
                #endif
            }
        }
        
        for app in rewardApps {
            #if DEBUG
            print("[PairingConfigView] 🔍 Checking reward app - logicalID: \(app.logicalID)")
            print("[PairingConfigView] 🔍   Snapshot displayName: '\(app.displayName)'")
            #endif
            
            if let displayName = getCurrentDisplayName(for: app.logicalID) {
                #if DEBUG
                print("[PairingConfigView] 🔍   Persisted displayName: '\(displayName)'")
                print("[PairingConfigView] 🔍   isEmpty: \(displayName.isEmpty)")
                print("[PairingConfigView] 🔍   hasPrefix('Unknown App'): \(displayName.hasPrefix("Unknown App"))")
                #endif
                
                if !displayName.isEmpty && !displayName.hasPrefix("Unknown App") {
                    editedNames[app.logicalID] = displayName
                    #if DEBUG
                    print("[PairingConfigView] ✅ Loaded name '\(displayName)' for logicalID: \(app.logicalID)")
                    #endif
                } else {
                    #if DEBUG
                    print("[PairingConfigView] ⚠️ Skipped loading name (empty or Unknown App)")
                    #endif
                }
            } else {
                #if DEBUG
                print("[PairingConfigView] ⚠️ No persisted app found for logicalID: \(app.logicalID)")
                #endif
            }
        }
        
        #if DEBUG
        print("[PairingConfigView] 🔍 Final editedNames count: \(editedNames.count)")
        print("[PairingConfigView] 🔍 editedNames: \(editedNames)")
        #endif
    }

    private var hasChanges: Bool {
        // Check learning apps
        for app in learningApps {
            let newName = editedNames[app.logicalID] ?? ""
            let oldName = getCurrentDisplayName(for: app.logicalID) ?? ""
            if newName != oldName {
                return true
            }
        }

        // Check reward apps
        for app in rewardApps {
            let newName = editedNames[app.logicalID] ?? ""
            let oldName = getCurrentDisplayName(for: app.logicalID) ?? ""
            if newName != oldName {
                return true
            }
        }

        return false
    }

    private func saveChanges() {
        isSaving = true

        // Update learning apps
        for app in learningApps {
            if let newName = editedNames[app.logicalID],
               !newName.isEmpty {

                // Get existing app or create a new one
                let existingApp = usagePersistence.app(for: app.logicalID)

                let updatedApp = UsagePersistence.PersistedApp(
                    logicalID: app.logicalID,
                    displayName: newName,
                    category: existingApp?.category ?? "learning",
                    rewardPoints: existingApp?.rewardPoints ?? app.pointsPerMinute,
                    totalSeconds: existingApp?.totalSeconds ?? Int(app.totalSeconds),
                    earnedPoints: existingApp?.earnedPoints ?? app.earnedPoints,
                    createdAt: existingApp?.createdAt ?? Date(),
                    lastUpdated: Date(),
                    todaySeconds: existingApp?.todaySeconds ?? 0,
                    todayPoints: existingApp?.todayPoints ?? 0,
                    lastResetDate: existingApp?.lastResetDate ?? Calendar.current.startOfDay(for: Date()),
                    dailyHistory: existingApp?.dailyHistory ?? [],
                    todayHourlySeconds: existingApp?.todayHourlySeconds ?? Array(repeating: 0, count: 24),
                    todayHourlyPoints: existingApp?.todayHourlyPoints ?? Array(repeating: 0, count: 24)
                )

                usagePersistence.saveApp(updatedApp)

                #if DEBUG
                if existingApp == nil {
                    print("[PairingConfigView] Created new persisted app for '\(newName)' with logicalID: \(app.logicalID)")
                } else {
                    print("[PairingConfigView] Updated displayName for '\(newName)' with logicalID: \(app.logicalID)")
                }
                #endif
            }
        }

        // Update reward apps
        for app in rewardApps {
            if let newName = editedNames[app.logicalID],
               !newName.isEmpty {

                // Get existing app or create a new one
                let existingApp = usagePersistence.app(for: app.logicalID)

                let updatedApp = UsagePersistence.PersistedApp(
                    logicalID: app.logicalID,
                    displayName: newName,
                    category: existingApp?.category ?? "reward",
                    rewardPoints: existingApp?.rewardPoints ?? app.pointsPerMinute,
                    totalSeconds: existingApp?.totalSeconds ?? Int(app.totalSeconds),
                    earnedPoints: existingApp?.earnedPoints ?? app.earnedPoints,
                    createdAt: existingApp?.createdAt ?? Date(),
                    lastUpdated: Date(),
                    todaySeconds: existingApp?.todaySeconds ?? 0,
                    todayPoints: existingApp?.todayPoints ?? 0,
                    lastResetDate: existingApp?.lastResetDate ?? Calendar.current.startOfDay(for: Date()),
                    dailyHistory: existingApp?.dailyHistory ?? [],
                    todayHourlySeconds: existingApp?.todayHourlySeconds ?? Array(repeating: 0, count: 24),
                    todayHourlyPoints: existingApp?.todayHourlyPoints ?? Array(repeating: 0, count: 24)
                )

                usagePersistence.saveApp(updatedApp)

                #if DEBUG
                if existingApp == nil {
                    print("[PairingConfigView] Created new persisted app for '\(newName)' with logicalID: \(app.logicalID)")
                } else {
                    print("[PairingConfigView] Updated displayName for '\(newName)' with logicalID: \(app.logicalID)")
                }
                #endif
            }
        }

        // Also save to CloudKit for cross-device sync
        saveToCloudKit()

        // Reload edited names to reflect saved changes
        loadCurrentNames()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            showSaveConfirmation = true
        }
    }
    
    // MARK: - CloudKit Sync
    
    /// Save app names to Core Data for automatic CloudKit sync
    private func saveToCloudKit() {
        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID
        
        #if DEBUG
        print("[PairingConfigView] 💾 Saving app names to CloudKit...")
        #endif
        
        // Save learning apps to CloudKit
        for app in learningApps {
            guard let newName = editedNames[app.logicalID], !newName.isEmpty else { continue }
            
            // Find or create AppConfiguration entity
            let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "logicalID == %@", app.logicalID)
            
            let config: AppConfiguration
            if let existing = try? context.fetch(fetchRequest).first {
                config = existing
            } else {
                config = AppConfiguration(context: context)
                config.logicalID = app.logicalID
                config.tokenHash = app.tokenHash
                config.category = "learning"
                config.deviceID = deviceID
                config.pointsPerMinute = Int16(app.pointsPerMinute)
                config.isEnabled = true
                config.blockingEnabled = false
                config.dateAdded = Date()
            }
            
            config.displayName = newName
            config.lastModified = Date()
            
            #if DEBUG
            print("[PairingConfigView]   ✅ Saved learning app: \(newName) (\(app.logicalID))")
            #endif
        }
        
        // Save reward apps to CloudKit
        for app in rewardApps {
            guard let newName = editedNames[app.logicalID], !newName.isEmpty else { continue }
            
            // Find or create AppConfiguration entity
            let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "logicalID == %@", app.logicalID)
            
            let config: AppConfiguration
            if let existing = try? context.fetch(fetchRequest).first {
                config = existing
            } else {
                config = AppConfiguration(context: context)
                config.logicalID = app.logicalID
                config.tokenHash = app.tokenHash
                config.category = "reward"
                config.deviceID = deviceID
                config.pointsPerMinute = Int16(app.pointsPerMinute)
                config.isEnabled = true
                config.blockingEnabled = false
                config.dateAdded = Date()
            }
            
            config.displayName = newName
            config.lastModified = Date()
            
            #if DEBUG
            print("[PairingConfigView]   ✅ Saved reward app: \(newName) (\(app.logicalID))")
            #endif
        }
        
        // Save context - NSPersistentCloudKitContainer will sync to CloudKit automatically
        do {
            try context.save()
            #if DEBUG
            print("[PairingConfigView] 💾 Core Data saved successfully - CloudKit will sync within 60 seconds")
            #endif
        } catch {
            #if DEBUG
            print("[PairingConfigView] ❌ Error saving to Core Data: \(error)")
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    PairingConfigView()
        .environmentObject(AppUsageViewModel())
}
