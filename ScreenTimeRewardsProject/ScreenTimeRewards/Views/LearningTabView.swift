import SwiftUI
import FamilyControls
import ManagedSettings

// Combined struct to prevent race condition in sheet presentation
private struct LearningConfigSheetData: Identifiable {
    let snapshot: LearningAppSnapshot
    var config: AppScheduleConfiguration
    var id: String { snapshot.id }
}

struct LearningTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // App schedule configuration
    @StateObject private var scheduleService = AppScheduleService.shared

    // Sheet state
    @State private var selectedLearningSnapshot: LearningAppSnapshot?
    @State private var configSheetData: LearningConfigSheetData?  // Combined snapshot + config

    private var hasLearningApps: Bool {
        !viewModel.learningSnapshots.isEmpty
    }

    // Calculate daily goal from active challenges
    private var dailyGoalMinutes: Int {
        viewModel.activeChallenges.reduce(0) { sum, challenge in
            if let progress = viewModel.challengeProgress[challenge.challengeID ?? ""] {
                return sum + Int(progress.targetValue)
            }
            return sum
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabTopBar(title: "Learning Apps", style: topBarStyle) {
                    sessionManager.exitToSelection()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        if !viewModel.learningSnapshots.isEmpty {
                            selectedAppsSection
                        }

                        // Bottom padding for FAB
                        Color.clear.frame(height: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Floating Action Button
            addAppsButton
        }
        .refreshable {
            await viewModel.refresh()
        }
        // Detail view sheet (for configured apps)
        .sheet(item: $selectedLearningSnapshot) { snapshot in
            LearningAppDetailView(snapshot: snapshot)
        }
        // Configuration sheet
        .sheet(item: $configSheetData) { data in
            AppConfigurationSheet(
                token: data.snapshot.token,
                appName: data.snapshot.displayName,
                appType: .learning,
                configuration: Binding(
                    get: { data.config },
                    set: { newConfig in
                        configSheetData = LearningConfigSheetData(snapshot: data.snapshot, config: newConfig)
                    }
                ),
                onSave: { savedConfig in
                    try? scheduleService.saveSchedule(savedConfig)
                    // Re-sync blocking reasons (linked learning apps may affect reward apps)
                    viewModel.blockRewardApps()
                    configSheetData = nil
                },
                onCancel: {
                    configSheetData = nil
                }
            )
        }
        // NOTE: Picker and sheet presentation handled by MainTabView to avoid conflicts
    }

    // MARK: - Helpers

    private func isConfigured(_ snapshot: LearningAppSnapshot) -> Bool {
        scheduleService.schedules[snapshot.logicalID] != nil
    }

    private func configSummary(for snapshot: LearningAppSnapshot) -> String? {
        scheduleService.schedules[snapshot.logicalID]?.displaySummary
    }

    private func openConfigSheet(for snapshot: LearningAppSnapshot) {
        let existingConfig = scheduleService.schedules[snapshot.logicalID]
            ?? AppScheduleConfiguration.defaultLearning(logicalID: snapshot.logicalID)
        // Set combined data atomically to prevent race condition
        configSheetData = LearningConfigSheetData(snapshot: snapshot, config: existingConfig)
    }

    private func handleAppTap(_ snapshot: LearningAppSnapshot) {
        if isConfigured(snapshot) {
            // Direct to detail view (configuration accessible from there)
            selectedLearningSnapshot = snapshot
        } else {
            // Open config sheet directly
            openConfigSheet(for: snapshot)
        }
    }

    // MARK: - Summary Card
    var summaryCard: some View {
        HStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.learningPeachLight.opacity(0.5), AppTheme.learningPeach.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "book.fill")
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.learningPeach)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Goal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(dailyGoalMinutes)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)
                        .tracking(-0.5)

                    Text("minutes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.bottom, 4)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Selected Apps Section
    var selectedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.learningPeach)

                Text("Learning Apps")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
            let columns = horizontalSizeClass == .regular ? [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ] : [
                GridItem(.flexible())
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.learningSnapshots) { snapshot in
                    learningAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - App Row
    @ViewBuilder
    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        // Standardized icon sizes (50% reduction)
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24
        let configured = isConfigured(snapshot)

        Button {
            handleAppTap(snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(iconScale)
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: fallbackIconSize))
                                    .foregroundColor(.gray)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if #available(iOS 15.2, *) {
                            Label(snapshot.token)
                                .labelStyle(.titleOnly)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        } else {
                            Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        // Show different content based on configuration status
                        if configured {
                            // Configured: show usage time and config summary
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.learningPeach)

                                Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.learningPeach)

                                if let summary = configSummary(for: snapshot) {
                                    Text("•")
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    Text(summary)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            // Unconfigured: show warning
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)

                                Text("Tap to configure")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    // Chevron indicator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(configured ? AppTheme.textSecondary(for: colorScheme) : .orange)
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(configured ? Color.clear : Color.orange.opacity(0.5), lineWidth: configured ? 0 : 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Apps Button (FAB)
    var addAppsButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.background(for: colorScheme).opacity(0),
                    AppTheme.background(for: colorScheme)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                viewModel.presentPickerWithRetry(for: .learning)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Manage Learning apps")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppTheme.learningPeach)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(AppTheme.background(for: colorScheme))
        }
    }

}

// MARK: - Design Tokens
private extension LearningTabView {
    var topBarStyle: TabTopBarStyle {
        TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.learningPeach,
            iconBackground: AppTheme.card(for: colorScheme),
            dividerColor: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06)
        )
    }
}

struct LearningTabView_Previews: PreviewProvider {
    static var previews: some View {
        LearningTabView()
            .environmentObject(AppUsageViewModel())
            .environmentObject(SessionManager.shared)
    }
}
