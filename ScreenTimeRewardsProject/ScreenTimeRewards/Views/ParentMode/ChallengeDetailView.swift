import SwiftUI

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme

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
                Text("\(progressMinutes) of \(Int(challenge.targetValue)) minutes completed")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)

                Spacer()

                Text("\(progressPercentage)%")
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
                        .frame(width: geometry.size.width * CGFloat(progressPercentage) / 100.0, height: 8)
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
                icon: "timer",
                title: "Time Goal",
                value: "\(Int(challenge.targetValue)) minutes"
            )

            metadataCard(
                icon: "hourglass",
                title: "Time Remaining",
                value: "\(remainingMinutes) minutes left"
            )

            metadataCard(
                icon: "calendar",
                title: "Schedule",
                value: scheduleText
            )

            metadataCard(
                icon: "gift.fill",
                title: "Reward Unlocked",
                value: "\(rewardMinutes) minutes"
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
            if let jsonString = challenge.targetAppsJSON,
               let data = jsonString.data(using: .utf8),
               let targetApps = try? JSONDecoder().decode([String].self, from: data),
               !targetApps.isEmpty {
                ForEach(targetApps, id: \.self) { appID in
                    appListRow(appID: appID)
                }
            } else {
                appListRow(appID: "Khan Kids")
                appListRow(appID: "Duolingo")
            }
        }
    }

    // MARK: - Reward Apps List
    private var rewardAppsList: some View {
        VStack(spacing: 12) {
            if let jsonString = challenge.targetAppsJSON,
               let data = jsonString.data(using: .utf8),
               let rewardApps = try? JSONDecoder().decode([String].self, from: data),
               !rewardApps.isEmpty {
                ForEach(rewardApps, id: \.self) { appID in
                    appListRow(appID: appID)
                }
            } else {
                appListRow(appID: "Roblox")
                appListRow(appID: "Minecraft")
            }
        }
    }

    private func appListRow(appID: String) -> some View {
        HStack(spacing: 16) {
            // App Icon Placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "app.fill")
                        .foregroundColor(.gray)
                )

            Text(appID)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Colors.textHeadingDark : Colors.textHeading)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? Colors.textBodyDark : Colors.textBody)
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
                // End Challenge action
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

            Button(action: {
                // Pause Challenge action
            }) {
                Text("Pause Challenge")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? Colors.primaryDark : Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.buttonCornerRadius)
                            .fill((colorScheme == .dark ? Colors.primaryDark : Colors.primary).opacity(0.2))
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

    // MARK: - Computed Properties
    private var progressMinutes: Int {
        // Mock data - would be calculated from actual progress
        35
    }

    private var progressPercentage: Int {
        let percentage = (Double(progressMinutes) / Double(challenge.targetValue)) * 100
        return Int(min(percentage, 100))
    }

    private var remainingMinutes: Int {
        max(Int(challenge.targetValue) - progressMinutes, 0)
    }

    private var scheduleText: String {
        // Extract from challenge data or return default
        if let startDate = challenge.startDate, let endDate = challenge.endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "E h a"
            return "Weekdays, \(formatter.string(from: startDate))-\(formatter.string(from: endDate))"
        }
        return "Weekdays, 4-6 PM"
    }

    private var rewardMinutes: Int {
        // Calculate reward based on bonus percentage
        let baseReward = Int(challenge.targetValue) * Int(challenge.bonusPercentage) / 100
        return max(baseReward, 15)
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
