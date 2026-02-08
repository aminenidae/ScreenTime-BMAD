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
    @State private var editedIconURLs: [String: String] = [:]
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var focusedAppID: String?
    @StateObject private var searchService = AppStoreSearchService.shared

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
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

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
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

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
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("LEARNING APPS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text("\(learningApps.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
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
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
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

            // Autocomplete Text Field
            AppNameAutocompleteField(
                text: bindingForLearning(app),
                placeholder: "Enter app name (e.g., Khan Academy)...",
                isFocused: focusedAppID == app.logicalID,
                accentColor: AppTheme.vibrantTeal,
                onFocus: { focusedAppID = app.logicalID },
                onSelectApp: { appInfo in
                    editedNames[app.logicalID] = appInfo.trackName
                    editedIconURLs[app.logicalID] = appInfo.artworkUrl100
                    focusedAppID = nil
                }
            )
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

            // Autocomplete Text Field
            AppNameAutocompleteField(
                text: bindingForReward(app),
                placeholder: "Enter app name (e.g., YouTube)...",
                isFocused: focusedAppID == app.logicalID,
                accentColor: AppTheme.playfulCoral,
                onFocus: { focusedAppID = app.logicalID },
                onSelectApp: { appInfo in
                    editedNames[app.logicalID] = appInfo.trackName
                    editedIconURLs[app.logicalID] = appInfo.artworkUrl100
                    focusedAppID = nil
                }
            )
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

    private func getExistingIconURL(for logicalID: String) -> String? {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "logicalID == %@", logicalID)
        fetchRequest.fetchLimit = 1

        if let config = try? context.fetch(fetchRequest).first {
            return config.iconURL
        }
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

        // Pre-populate editedNames and editedIconURLs with current values
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

            // Also load existing iconURL to preserve it during subsequent saves
            if let existingIconURL = getExistingIconURL(for: app.logicalID) {
                editedIconURLs[app.logicalID] = existingIconURL
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

            // Also load existing iconURL to preserve it during subsequent saves
            if let existingIconURL = getExistingIconURL(for: app.logicalID) {
                editedIconURLs[app.logicalID] = existingIconURL
            }
        }

        #if DEBUG
        print("[PairingConfigView] 🔍 Final editedNames count: \(editedNames.count)")
        print("[PairingConfigView] 🔍 editedNames: \(editedNames)")
        print("[PairingConfigView] 🔍 editedIconURLs count: \(editedIconURLs.count)")
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

        // Update existing UsageRecords with new displayNames
        updateUsageRecordDisplayNames()

        // Also save to CloudKit for cross-device sync
        saveToCloudKit()

        // Reload edited names to reflect saved changes
        loadCurrentNames()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            showSaveConfirmation = true
        }
    }
    
    // MARK: - Update UsageRecords

    /// Update all existing UsageRecords with new displayNames
    /// This ensures historical records show the custom name set by the user
    private func updateUsageRecordDisplayNames() {
        let context = PersistenceController.shared.container.viewContext
        var updatedCount = 0

        for (logicalID, newName) in editedNames {
            guard !newName.isEmpty else { continue }

            let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "logicalID == %@", logicalID)

            do {
                let records = try context.fetch(fetchRequest)
                for record in records {
                    if record.displayName != newName {
                        record.displayName = newName
                        record.isSynced = false  // Re-upload to CloudKit with new name
                        updatedCount += 1
                    }
                }
            } catch {
                #if DEBUG
                print("[PairingConfigView] ❌ Error updating UsageRecords for \(logicalID): \(error)")
                #endif
            }
        }

        if updatedCount > 0 {
            do {
                try context.save()
                #if DEBUG
                print("[PairingConfigView] ✅ Updated displayName in \(updatedCount) UsageRecords")
                #endif
            } catch {
                #if DEBUG
                print("[PairingConfigView] ❌ Error saving UsageRecords: \(error)")
                #endif
            }
        }
    }

    // MARK: - CloudKit Sync

    /// Save app names to Core Data for automatic CloudKit sync
    private func saveToCloudKit() {
        // First, lookup missing iconURLs asynchronously, then save
        Task {
            await lookupMissingIconURLs()
            await MainActor.run {
                performSaveToCloudKit()
            }
        }
    }

    /// Lookup iconURLs from App Store for apps that don't have them
    private func lookupMissingIconURLs() async {
        // Collect all logicalIDs that need lookup
        let allLogicalIDs = learningApps.map { $0.logicalID } + rewardApps.map { $0.logicalID }

        for logicalID in allLogicalIDs {
            guard let name = editedNames[logicalID], !name.isEmpty else { continue }

            // Skip if already has iconURL
            if editedIconURLs[logicalID] != nil { continue }

            // Also check if there's an existing iconURL in Core Data
            if getExistingIconURL(for: logicalID) != nil { continue }

            #if DEBUG
            print("[PairingConfigView] 🔍 Looking up iconURL for: \(name)")
            #endif

            // Auto-lookup from App Store
            do {
                let results = try await AppStoreSearchService.shared.searchApps(query: name)
                if let firstMatch = results.first {
                    await MainActor.run {
                        editedIconURLs[logicalID] = firstMatch.artworkUrl100
                    }
                    #if DEBUG
                    print("[PairingConfigView]   ✅ Found iconURL: \(firstMatch.artworkUrl100)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[PairingConfigView]   ⚠️ Failed to lookup: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Perform the actual save to Core Data and CloudKit
    private func performSaveToCloudKit() {
        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        #if DEBUG
        print("[PairingConfigView] 💾 Saving app names to CloudKit...")
        #endif

        // IMPORTANT: Update ALL existing AppConfigurations to use the current deviceID
        // This fixes a bug where apps saved with an old deviceID won't be found by the parent
        let allConfigsFetch: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        if let allConfigs = try? context.fetch(allConfigsFetch) {
            var updatedCount = 0
            for config in allConfigs {
                if config.deviceID != deviceID {
                    config.deviceID = deviceID
                    config.lastModified = Date()
                    updatedCount += 1
                }
            }
            #if DEBUG
            if updatedCount > 0 {
                print("[PairingConfigView] 🔄 Updated deviceID for \(updatedCount) existing app configurations")
            }
            #endif
        }

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
            config.iconURL = editedIconURLs[app.logicalID]
            config.lastModified = Date()

            #if DEBUG
            print("[PairingConfigView]   ✅ Saved learning app: \(newName) (\(app.logicalID)), iconURL: \(editedIconURLs[app.logicalID] ?? "none")")
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
            config.iconURL = editedIconURLs[app.logicalID]
            config.lastModified = Date()

            #if DEBUG
            print("[PairingConfigView]   ✅ Saved reward app: \(newName) (\(app.logicalID)), iconURL: \(editedIconURLs[app.logicalID] ?? "none")")
            #endif
        }
        
        // Save context - NSPersistentCloudKitContainer will sync to CloudKit automatically
        do {
            try context.save()
            #if DEBUG
            print("[PairingConfigView] 💾 Core Data saved successfully")
            #endif

            // Immediately upload to parent's CloudKit zone (don't wait for NSPersistentCloudKitContainer)
            Task {
                do {
                    try await CloudKitSyncService.shared.uploadAppConfigurationsToParent()
                    #if DEBUG
                    print("[PairingConfigView] ✅ Uploaded configurations to parent zone")
                    #endif
                } catch {
                    #if DEBUG
                    print("[PairingConfigView] ⚠️ Failed to upload to parent: \(error.localizedDescription)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("[PairingConfigView] ❌ Error saving to Core Data: \(error)")
            #endif
        }
    }
}

// MARK: - App Name Autocomplete Field

/// A text field with autocomplete suggestions from the App Store
struct AppNameAutocompleteField: View {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let accentColor: Color
    let onFocus: () -> Void
    let onSelectApp: (AppStoreAppInfo) -> Void

    @ObservedObject private var searchService = AppStoreSearchService.shared
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Text input
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .focused($isTextFieldFocused)
                    .onChange(of: text) { newValue in
                        // Always search when text changes (debouncing happens in service)
                        searchService.search(query: newValue)
                    }
                    .onChange(of: isTextFieldFocused) { focused in
                        if focused {
                            onFocus()
                            // Trigger search with current text when focused
                            if !text.isEmpty {
                                searchService.search(query: text)
                            }
                        }
                    }

                if searchService.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !text.isEmpty {
                    Button(action: {
                        text = ""
                        searchService.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.inputBackground(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                (isFocused || isTextFieldFocused) ? accentColor : AppTheme.border(for: colorScheme),
                                lineWidth: (isFocused || isTextFieldFocused) ? 2 : 1
                            )
                    )
            )

            // Suggestions dropdown - shows when we have results
            if !searchService.searchResults.isEmpty && isTextFieldFocused {
                VStack(spacing: 0) {
                    ForEach(Array(searchService.searchResults.prefix(5).enumerated()), id: \.element.id) { index, appInfo in
                        Button(action: {
                            text = appInfo.trackName
                            onSelectApp(appInfo)
                            searchService.clearSearch()
                            isTextFieldFocused = false
                        }) {
                            HStack(spacing: 12) {
                                // App icon
                                AsyncImage(url: URL(string: appInfo.artworkUrl60)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    case .failure:
                                        Image(systemName: "app.fill")
                                            .foregroundColor(.gray)
                                    case .empty:
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    @unknown default:
                                        Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                // App name
                                Text(appInfo.trackName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if index < min(4, searchService.searchResults.count - 1) {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.card(for: colorScheme))
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchService.searchResults.isEmpty)
    }
}

// MARK: - Preview

#Preview {
    PairingConfigView()
        .environmentObject(AppUsageViewModel())
}
