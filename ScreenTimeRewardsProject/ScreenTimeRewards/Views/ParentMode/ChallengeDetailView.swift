import SwiftUI
import CoreData
import FamilyControls
import ManagedSettings

struct ChallengeDetailView: View {
    let challenge: Challenge
    let progress: ChallengeProgress?
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel

    @State private var showingEndAlert = false
    @State private var showingPauseAlert = false
    @State private var showingEditBuilder = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Challenge Status Card
                    challengeStatusCard
                        .padding(.horizontal, DesignTokens.horizontalPadding)
                        .padding(.top, DesignTokens.sectionTopPadding)

                    // Today's Progress Section
                    VStack(alignment: .leading, spacing: DesignTokens.sectionContentSpacing) {
                        Text("Today's Progress")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                            .padding(.top, DesignTokens.sectionHeaderTopPadding)
                            .padding(.bottom, DesignTokens.sectionHeaderBottomPadding)

                        progressCard
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                    }

                    // Metadata Grid
                    metadataGrid
                        .padding(.horizontal, DesignTokens.horizontalPadding)
                        .padding(.top, DesignTokens.sectionTopPadding)

                    // Learning Apps Section
                    VStack(alignment: .leading, spacing: DesignTokens.sectionContentSpacing) {
                        Text("Learning Apps")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                            .padding(.top, DesignTokens.sectionHeaderTopPadding)
                            .padding(.bottom, DesignTokens.sectionHeaderBottomPadding)

                        learningAppsList
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                    }

                    // Reward Apps Section
                    VStack(alignment: .leading, spacing: DesignTokens.sectionContentSpacing) {
                        Text("Reward Apps")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                            .padding(.top, DesignTokens.sectionHeaderTopPadding)
                            .padding(.bottom, DesignTokens.sectionHeaderBottomPadding)

                        rewardAppsList
                            .padding(.horizontal, DesignTokens.horizontalPadding)
                    }

                    // Bottom padding for fixed action buttons
                    Color.clear
                        .frame(height: 160)
                }
            }
            .background(colorScheme == .dark ? Colors.backgroundDark : Colors.backgroundLight)

            // Fixed Action Buttons at bottom
            actionButtons
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(challenge.title ?? "Challenge")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    #if DEBUG
                    print("[ChallengeDetailView] 📝 Edit button tapped for challenge: \(challenge.title ?? "Untitled")")
                    #endif
                    showingEditBuilder = true
                }) {
                    Text("Edit")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? Colors.primaryDark : Colors.primary)
                }
            }
        }
        .sheet(isPresented: $showingEditBuilder) {
            EditChallengeBuilderWrapper(
                challenge: challenge,
                isPresented: $showingEditBuilder
            )
            .environmentObject(appUsageViewModel)
        }
        .onChange(of: showingEditBuilder) { newValue in
            #if DEBUG
            print("[ChallengeDetailView] 🔄 showingEditBuilder changed to: \(newValue)")
            #endif
        }
    }

    // MARK: - Challenge Status Card
    private var challengeStatusCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // Status Text Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)

                Text(challenge.isActive ? "Active" : "Inactive")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(challenge.isActive ? (colorScheme == .dark ? Colors.secondaryDark : Colors.secondary) : (colorScheme == .dark ? .gray : Colors.textBody))

                Text(challenge.isActive ? "The challenge is currently in progress." : "The challenge is not active.")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Icon Circle
            ZStack {
                Circle()
                    .fill((challenge.isActive ? (colorScheme == .dark ? Colors.secondaryDark : Colors.secondary) : (colorScheme == .dark ? Color.gray : Colors.textBody)).opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: challenge.isActive ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(challenge.isActive ? (colorScheme == .dark ? Colors.secondaryDark : Colors.secondary) : (colorScheme == .dark ? Color.gray : Colors.textBody))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius)
                .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Progress Card
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(progressHeadlineText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)

                Spacer()

                Text("\(Int(progressPercentageValue))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
            }

            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.progressBarCornerRadius)
                        .fill(colorScheme == .dark ? Colors.progressBackgroundDark : Colors.progressBackground)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: DesignTokens.progressBarCornerRadius)
                        .fill(colorScheme == .dark ? Colors.secondaryDark : Colors.secondary)
                        .frame(width: geometry.size.width * CGFloat(progressBarFraction), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius)
                .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Metadata Grid
    private var metadataGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            metadataCard(
                icon: "target",
                title: "Target",
                value: "\(targetProgressValue) \(progressUnitDisplay)"
            )

            metadataCard(
                icon: "chart.bar.xaxis",
                title: "Current Progress",
                value: progressHeadlineText
            )

            metadataCard(
                icon: "calendar",
                title: "Schedule",
                value: scheduleText
            )

            metadataCard(
                icon: "gift.fill",
                title: "Reward Unlocks",
                value: rewardPlanText
            )
        }
    }

    private func metadataCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(colorScheme == .dark ? Colors.primaryDark : Colors.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)

                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.metadataCardCornerRadius)
                .strokeBorder(colorScheme == .dark ? Colors.borderDark : Colors.border, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.metadataCardCornerRadius)
                        .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                )
        )
    }

    // MARK: - Learning Apps List
    private var learningAppsList: some View {
        VStack(spacing: 12) {
            if learningAppTokens.isEmpty {
                Text("All configured learning apps count toward this challenge.")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.textBody.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ForEach(learningAppTokens, id: \.hashValue) { token in
                    appListRow(token: token)
                }
            }
        }
    }

    // MARK: - Reward Apps List
    private var rewardAppsList: some View {
        VStack(spacing: 12) {
            if rewardAppTokens.isEmpty {
                Text("No reward apps selected. Add rewards to motivate your learner.")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.textBody.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ForEach(rewardAppTokens, id: \.hashValue) { token in
                    appListRow(token: token)
                }

                Text(rewardBonusDescription)
                    .font(.system(size: 13))
                    .foregroundColor(Colors.textBody.opacity(0.7))
                    .padding(.top, 4)
            }
        }
    }

    private func appListRow(token: ApplicationToken) -> some View {
        // Standardized icon sizes to match Learning tab
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24

        // Get usage data for this app
        let dailyUsage = getDailyUsageMinutes(for: token)

        return HStack(spacing: 16) {
            // App Icon - Standardized smaller size to match Learning tab
            if #available(iOS 15.2, *) {
                Label(token)
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

            // App Info
            VStack(alignment: .leading, spacing: 2) {
                // App Name
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                        .lineLimit(1)
                } else {
                    Text("App")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                        .lineLimit(1)
                }

                // Daily Usage Time
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(colorScheme == .dark ? Colors.secondaryDark : Colors.secondary)

                    Text(dailyUsage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius)
                .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    // Helper to get daily usage time for an app
    private func getDailyUsageMinutes(for token: ApplicationToken) -> String {
        // Use the same hash calculation as snapshots (via ScreenTimeService)
        let service = ScreenTimeService.shared
        let tokenHash = service.usagePersistence.tokenHash(for: token)

        // Look up in learning snapshots
        if let snapshot = appUsageViewModel.learningSnapshots.first(where: { $0.tokenHash == tokenHash }) {
            let minutes = Int(snapshot.totalSeconds / 60)
            return "\(minutes) min today"
        }

        // Look up in reward snapshots
        if let snapshot = appUsageViewModel.rewardSnapshots.first(where: { $0.tokenHash == tokenHash }) {
            let minutes = Int(snapshot.totalSeconds / 60)
            return "\(minutes) min today"
        }

        return "0 min today"
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                showingEndAlert = true
            }) {
                Text("End Challenge Now")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                            .fill(colorScheme == .dark ? Colors.dangerDark : Colors.danger)
                    )
            }
            .alert("End Challenge?", isPresented: $showingEndAlert) {
                Button("Cancel", role: .cancel) { }
                Button("End", role: .destructive) {
                    endChallenge()
                }
            } message: {
                Text("This will permanently end the challenge. Progress will be saved but the challenge will no longer be active.")
            }

            Button(action: {
                showingPauseAlert = true
            }) {
                Text(challenge.isActive ? "Pause Challenge" : "Resume Challenge")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.primaryDark : Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                            .fill((colorScheme == .dark ? Colors.primaryDark : Colors.primary).opacity(0.2))
                    )
            }
            .alert(challenge.isActive ? "Pause Challenge?" : "Resume Challenge?", isPresented: $showingPauseAlert) {
                Button("Cancel", role: .cancel) { }
                Button(challenge.isActive ? "Pause" : "Resume") {
                    togglePauseChallenge()
                }
            } message: {
                Text(challenge.isActive ? "The challenge will be temporarily paused. You can resume it later." : "The challenge will become active again.")
            }

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Exit")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                            .strokeBorder(colorScheme == .dark ? Colors.borderDark : Colors.border, lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                                    .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                            )
                    )
            }
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill((colorScheme == .dark ? Colors.backgroundDark : Colors.backgroundLight).opacity(0.8))
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(colorScheme == .dark ? Colors.borderDark : Colors.border)
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    // MARK: - Helper Methods
    private func endChallenge() {
        challenge.isActive = false
        if let endDate = challenge.endDate, endDate > Date() {
            challenge.endDate = Date()
        } else if challenge.endDate == nil {
            challenge.endDate = Date()
        }

        do {
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            print("Error ending challenge: \(error)")
        }
    }

    private func togglePauseChallenge() {
        challenge.isActive.toggle()

        do {
            try viewContext.save()
        } catch {
            print("Error toggling challenge pause state: \(error)")
        }
    }

    // MARK: - Computed Properties
    private var currentProgressValue: Int {
        Int(progress?.currentValue ?? 0)
    }

    private var targetProgressValue: Int {
        Int(progress?.targetValue ?? challenge.targetValue)
    }

    private var remainingProgressValue: Int {
        max(targetProgressValue - currentProgressValue, 0)
    }

    private var progressPercentageValue: Double {
        min(progress?.progressPercentage ?? 0, 100)
    }

    private var progressBarFraction: Double {
        progressPercentageValue / 100.0
    }

    private var progressUnitDisplay: String {
        return "min"
    }

    private var progressHeadlineText: String {
        "\(currentProgressValue) / \(targetProgressValue) \(progressUnitDisplay)"
    }

    private var scheduleText: String {
        let dayText: String
        let days = challenge.scheduledActiveDays

        if days.isEmpty || days.count == 7 {
            dayText = "Every day"
        } else {
            dayText = days
                .sorted()
                .map { weekdayLabel(for: $0) }
                .joined(separator: ", ")
        }

        if let startTime = challenge.startTime, let endTime = challenge.endTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "\(dayText), \(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
        }

        return dayText
    }

    private var rewardSummaryText: String {
        let count = rewardAppTokens.count
        if count == 0 {
            return "No reward apps"
        } else if count == 1 {
            return "1 app"
        } else {
            return "\(count) apps"
        }
    }

    private var rewardPlanText: String {
        let count = rewardAppTokens.count
        if count == 0 {
            return "No reward apps"
        } else if count == 1 {
            return "1 app to unlock"
        } else {
            return "\(count) apps to unlock"
        }
    }

    private var rewardBonusDescription: String {
        let count = rewardAppTokens.count
        if count == 0 {
            return "No reward unlocks"
        }
        return "\(count) app\(count == 1 ? "" : "s") unlock for \(rewardUnlockMinutes) min"
    }

    private var learningAppTokens: [ApplicationToken] {
        let ids = challenge.targetAppIDs
        if ids.isEmpty { return [] }
        return ids.compactMap { learningTokenLookup[$0] }
    }

    private var rewardAppTokens: [ApplicationToken] {
        let ids = challenge.rewardAppIDs
        if ids.isEmpty { return [] }
        return ids.compactMap { rewardTokenLookup[$0] }
    }

    private var learningTokenLookup: [String: ApplicationToken] {
        appUsageViewModel.learningSnapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.logicalID] = snapshot.token
        }
    }

    private var rewardTokenLookup: [String: ApplicationToken] {
        appUsageViewModel.rewardSnapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.logicalID] = snapshot.token
        }
    }

    private func weekdayLabel(for index: Int) -> String {
        let formatter = DateFormatter()
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        let safeIndex = ((index % symbols.count) + symbols.count) % symbols.count
        return symbols[safeIndex]
    }

    private var rewardUnlockMinutes: Int {
        challenge.rewardUnlockMinutes()
    }

    private var rewardRatioDescription: String {
        challenge.learningToRewardRatio?.formattedDescription ?? LearningToRewardRatio.default.formattedDescription
    }

    private var rewardUnlockMinutesDescription: String {
        let minutes = rewardUnlockMinutes
        return "≈ \(minutes) min reward per completion"
    }
}

// MARK: - Design Tokens
extension ChallengeDetailView {
    struct DesignTokens {
        static let horizontalPadding: CGFloat = 16
        static let sectionTopPadding: CGFloat = 16
        static let sectionHeaderTopPadding: CGFloat = 32
        static let sectionHeaderBottomPadding: CGFloat = 12
        static let sectionContentSpacing: CGFloat = 12
        static let cardCornerRadius: CGFloat = 12
        static let metadataCardCornerRadius: CGFloat = 8
        static let buttonCornerRadius: CGFloat = 8
        static let progressBarCornerRadius: CGFloat = 9999
    }

    struct Colors {
        // Primary Colors
        static let primary = Color(hex: "#005A9C")
        static let primaryDark = Color(hex: "#60A5FA")

        // Secondary Colors
        static let secondary = Color(hex: "#28A745")
        static let secondaryDark = Color(hex: "#4ADE80")

        // Background Colors
        static let backgroundLight = Color(hex: "#F8F9FA")
        static let backgroundDark = Color(hex: "#10221c")

        // Card Background
        static let cardBackground = Color.white
        static let cardBackgroundDark = Color(hex: "#1F2937")

        // Text Colors
        static let textHeading = Color(hex: "#343A40")
        static let textHeadingDark = Color(hex: "#F3F4F6")
        static let textBody = Color(hex: "#6C757D")
        static let textBodyDark = Color(hex: "#9CA3AF")

        // Border Colors
        static let border = Color(hex: "#E5E7EB")
        static let borderDark = Color(hex: "#374151")

        // Progress Bar
        static let progressBackground = Color(hex: "#E5E7EB")
        static let progressBackgroundDark = Color(hex: "#374151")

        // Danger Colors
        static let danger = Color(hex: "#DC2626")
        static let dangerDark = Color(hex: "#EF4444")
    }
}

// MARK: - Edit Challenge Builder Wrapper
struct EditChallengeBuilderWrapper: View {
    let challenge: Challenge
    @Binding var isPresented: Bool
    @StateObject private var challengeViewModel = ChallengeViewModel()
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel

    // Compute edit data once, not on every body evaluation
    private var editData: ChallengeBuilderData {
        var data = ChallengeBuilderData.fromChallenge(challenge)

        // Clear app IDs since we don't have tokens in edit mode
        // User will need to re-select apps
        data.selectedLearningAppIDs = []
        data.selectedRewardAppIDs = []

        return data
    }

    var body: some View {
        // IMPORTANT: Present the builder WITHOUT nested NavigationView
        // to avoid FamilyControls Label hierarchy conflicts
        ChallengeBuilderFlowView(
            viewModel: challengeViewModel,
            initialData: editData
        )
        .environmentObject(appUsageViewModel)
        .interactiveDismissDisabled(false)
        .onAppear {
            #if DEBUG
            print("[EditChallengeBuilderWrapper] ✅ Builder appeared for challenge: \(challenge.title ?? "Untitled")")
            print("[EditChallengeBuilderWrapper] 📝 Title: \(editData.title), Goal: \(editData.dailyMinutesGoal) min")
            print("[EditChallengeBuilderWrapper] 📝 Ratio: \(editData.learningToRewardRatio.formattedDescription)")
            print("[EditChallengeBuilderWrapper] 📝 Streak: \(editData.streakBonus.enabled), Target: \(editData.streakBonus.targetDays) days")
            print("[EditChallengeBuilderWrapper] ⚠️ App selections cleared - user must re-select apps")
            #endif
        }
        .onDisappear {
            #if DEBUG
            print("[EditChallengeBuilderWrapper] ❌ Builder disappeared")
            #endif
        }
    }
}
