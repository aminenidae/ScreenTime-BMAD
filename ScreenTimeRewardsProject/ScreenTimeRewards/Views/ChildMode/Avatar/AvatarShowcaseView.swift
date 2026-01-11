//
//  AvatarShowcaseView.swift
//  ScreenTimeRewards
//
//  Full showcase view for the avatar with stats and customization access
//

import SwiftUI

struct AvatarShowcaseView: View {
    @ObservedObject var avatarService: AvatarService
    @Environment(\.colorScheme) var colorScheme

    @State private var showCustomization = false
    @State private var showAvatarSelection = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                // Avatar hero display
                avatarHeroCard

                // Stats cards
                statsSection

                // Quick actions
                actionsSection

                Spacer(minLength: AppTheme.Spacing.huge)
            }
            .padding(.top, AppTheme.Spacing.regular)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("My Buddy")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCustomization) {
            AvatarCustomizationView(avatarService: avatarService)
        }
        .sheet(isPresented: $showAvatarSelection) {
            AvatarSelectionView(avatarService: avatarService)
        }
    }

    // MARK: - Avatar Hero Card

    private var avatarHeroCard: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Large avatar with animation
            AvatarView(
                avatarState: avatarService.currentAvatarState,
                size: .hero,
                showMood: true,
                isInteractive: true
            )
            .scaleEffect(1.1)

            // Name and stage
            VStack(spacing: AppTheme.Spacing.tiny) {
                Text(avatarName)
                    .font(AppTheme.Typography.title2)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(stageColor)
                    Text(stageName)
                        .foregroundColor(stageColor)
                        .fontWeight(.semibold)
                }
                .font(AppTheme.Typography.subheadline)
            }

            // Evolution progress
            if !avatarService.isMaxLevel {
                evolutionProgress
            } else {
                maxLevelIndicator
            }
        }
        .padding(AppTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(
                    LinearGradient(
                        colors: [
                            stageColor.opacity(0.15),
                            stageColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, AppTheme.Spacing.regular)
    }

    private var evolutionProgress: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [stageColor, nextStageColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * avatarService.progressToNextLevel, height: 12)
                        .animation(.spring(response: 0.5), value: avatarService.progressToNextLevel)
                }
            }
            .frame(height: 12)

            // Progress text
            if let minutesLeft = avatarService.minutesToNextLevel {
                Text(progressText(minutesLeft: minutesLeft))
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.large)
    }

    private var maxLevelIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .foregroundColor(.orange)
            Text("Maximum Level!")
                .fontWeight(.bold)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
        )
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Text("Stats")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.regular)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppTheme.Spacing.medium
            ) {
                StatCard(
                    title: "Total Learning",
                    value: formatMinutes(avatarService.totalLearningMinutes),
                    icon: "book.fill",
                    color: AppTheme.vibrantTeal
                )

                StatCard(
                    title: "Evolution Level",
                    value: "Level \(avatarService.currentEvolutionLevel)",
                    icon: "arrow.up.circle.fill",
                    color: stageColor
                )

                StatCard(
                    title: "Accessories",
                    value: "\(unlockedAccessoriesCount)",
                    icon: "sparkles",
                    color: AppTheme.playfulCoral
                )

                StatCard(
                    title: "Mood",
                    value: currentMoodText,
                    icon: moodIcon,
                    color: AppTheme.sunnyYellow
                )
            }
            .padding(.horizontal, AppTheme.Spacing.regular)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Customize button
            Button(action: { showCustomization = true }) {
                HStack {
                    Image(systemName: "paintbrush.fill")
                    Text("Customize Accessories")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(AppTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.card(for: colorScheme))
                        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, y: 1)
                )
            }

            // Change avatar button
            Button(action: { showAvatarSelection = true }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Change Avatar")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(AppTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.playfulCoral)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.card(for: colorScheme))
                        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, y: 1)
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.regular)
    }

    // MARK: - Computed Properties

    private var avatarName: String {
        avatarService.currentAvatarState?.avatarDefinition?.name ?? "Your Buddy"
    }

    private var stageName: String {
        avatarService.currentAvatarState?.currentEvolutionStage?.name ?? "Stage 1"
    }

    private var stageColor: Color {
        AppTheme.Evolution.color(for: avatarService.currentEvolutionLevel)
    }

    private var nextStageColor: Color {
        AppTheme.Evolution.color(for: avatarService.currentEvolutionLevel + 1)
    }

    private var unlockedAccessoriesCount: Int {
        avatarService.currentAvatarState?.unlockedAccessoryIDs.count ?? 0
    }

    private var currentMoodText: String {
        avatarService.currentAvatarState?.mood.rawValue.capitalized ?? "Happy"
    }

    private var moodIcon: String {
        avatarService.currentAvatarState?.mood.sfSymbol ?? "face.smiling.fill"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }

    private func progressText(minutesLeft: Int) -> String {
        if minutesLeft >= 60 {
            let hours = minutesLeft / 60
            return "\(hours)h until next evolution"
        }
        return "\(minutesLeft)m until next evolution"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, y: 1)
        )
    }
}

// MARK: - Avatar Selection View

struct AvatarSelectionView: View {
    @ObservedObject var avatarService: AvatarService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    Text("Choose your buddy!")
                        .font(AppTheme.Typography.title2)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.top)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppTheme.Spacing.large
                    ) {
                        ForEach(AvatarCatalog.allAvatars) { avatar in
                            AvatarSelectionCard(
                                avatar: avatar,
                                isSelected: avatarService.currentAvatarState?.avatarID == avatar.id,
                                isUnlocked: avatarService.unlockedAvatarIDs.contains(avatar.id)
                            ) {
                                Task {
                                    if await avatarService.selectAvatar(avatar.id) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("Select Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AvatarSelectionCard: View {
    let avatar: AvatarDefinition
    let isSelected: Bool
    let isUnlocked: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.Evolution.stage1.opacity(0.3),
                                    AppTheme.Evolution.stage2.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: avatar.baseAsset)
                        .font(.system(size: 44))
                        .foregroundColor(isUnlocked ? AppTheme.Evolution.stage1 : .gray)

                    if !isUnlocked {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 100, height: 100)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }

                    if isSelected {
                        Circle()
                            .stroke(AppTheme.vibrantTeal, lineWidth: 3)
                            .frame(width: 104, height: 104)

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .background(Circle().fill(.white))
                            }
                            Spacer()
                        }
                        .frame(width: 100, height: 100)
                    }
                }

                Text(avatar.name)
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text(avatar.category.displayName)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}

// MARK: - Preview

#Preview("Avatar Showcase") {
    NavigationView {
        AvatarShowcaseView(avatarService: AvatarService.shared)
    }
}
