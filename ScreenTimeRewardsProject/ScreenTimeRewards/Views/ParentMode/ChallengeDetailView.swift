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
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel

    @State private var showingEndAlert = false
    @State private var showingPauseAlert = false

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
                    // Edit action
                }) {
                    Text("Edit")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? Colors.primaryDark : Colors.primary)
                }
            }
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
        HStack(spacing: 16) {
            // Real App Icon using Label - larger size
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(2.5)
                    .frame(width: 64, height: 64)
                    .background(Color.clear)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }

            // Real App Name using Label - same style as Schedule text
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
                    .lineLimit(1)
            } else {
                Text("App")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius)
                .fill(colorScheme == .dark ? Colors.cardBackgroundDark : Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
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
        switch challenge.goalTypeEnum {
        case .pointsTarget:
            return "pts"
        case .streak:
            return "days"
        default:
            return "min"
        }
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
        let components = [
            rewardSummaryText,
            rewardRatioDescription,
            rewardUnlockMinutesDescription,
            "+\(challenge.bonusPercentage)% bonus"
        ]
        return components.joined(separator: "\n")
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
