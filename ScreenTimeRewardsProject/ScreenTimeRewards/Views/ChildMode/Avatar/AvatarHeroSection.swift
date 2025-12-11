//
//  AvatarHeroSection.swift
//  ScreenTimeRewards
//
//  Hero section displaying the avatar with name and evolution progress
//

import SwiftUI

struct AvatarHeroSection: View {
    @ObservedObject var avatarService: AvatarService
    @Environment(\.colorScheme) var colorScheme

    var onAvatarTap: (() -> Void)?

    @State private var showEvolutionCelebration = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Avatar display
            AvatarView(
                avatarState: avatarService.currentAvatarState,
                size: .hero,
                showMood: true,
                isInteractive: true,
                onTap: onAvatarTap
            )

            // Avatar name and stage
            VStack(spacing: AppTheme.Spacing.tiny) {
                Text(avatarName)
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text(stageName)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(stageColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(stageColor.opacity(0.15))
                    )
            }

            // Evolution progress
            if !avatarService.isMaxLevel {
                evolutionProgressBar
            } else {
                maxLevelBadge
            }
        }
        .padding(.vertical, AppTheme.Spacing.regular)
        .onChange(of: avatarService.pendingEvolution) { newEvolution in
            if newEvolution != nil {
                showEvolutionCelebration = true
            }
        }
        .sheet(isPresented: $showEvolutionCelebration) {
            if let evolution = avatarService.pendingEvolution {
                EvolutionCelebrationView(
                    evolution: evolution,
                    avatarState: avatarService.currentAvatarState
                ) {
                    showEvolutionCelebration = false
                    avatarService.clearPendingEvolution()
                }
            }
        }
    }

    // MARK: - Evolution Progress

    private var evolutionProgressBar: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.progressTrack(for: colorScheme))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [stageColor, nextStageColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * avatarService.progressToNextLevel, height: 8)
                        .animation(.spring(response: 0.5), value: avatarService.progressToNextLevel)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, AppTheme.Spacing.large)

            // Progress text
            if let minutesLeft = avatarService.minutesToNextLevel {
                Text(progressText(minutesLeft: minutesLeft))
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
    }

    private var maxLevelBadge: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "crown.fill")
                .foregroundColor(.orange)
            Text("Max Level Reached!")
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
        )
    }

    // MARK: - Computed Properties

    private var avatarName: String {
        avatarService.currentAvatarState?.avatarDefinition?.name ?? "Your Buddy"
    }

    private var stageName: String {
        avatarService.currentAvatarState?.currentEvolutionStage?.name ?? "Stage 1"
    }

    private var currentLevel: Int {
        avatarService.currentEvolutionLevel
    }

    private var stageColor: Color {
        switch currentLevel {
        case 1: return AppTheme.sunnyYellow
        case 2: return AppTheme.vibrantTeal
        case 3: return AppTheme.playfulCoral
        case 4: return .orange
        default: return AppTheme.sunnyYellow
        }
    }

    private var nextStageColor: Color {
        switch currentLevel {
        case 1: return AppTheme.vibrantTeal
        case 2: return AppTheme.playfulCoral
        case 3: return .orange
        default: return .orange
        }
    }

    private func progressText(minutesLeft: Int) -> String {
        if minutesLeft >= 60 {
            let hours = minutesLeft / 60
            let mins = minutesLeft % 60
            if mins == 0 {
                return "\(hours)h of learning until next evolution"
            }
            return "\(hours)h \(mins)m until next evolution"
        }
        return "\(minutesLeft)m of learning until next evolution"
    }
}

// MARK: - Evolution Celebration View

struct EvolutionCelebrationView: View {
    let evolution: EvolutionStage
    let avatarState: AvatarState?
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showStars = false

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            // Stars background
            if showStars {
                ForEach(0..<20, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: CGFloat.random(in: 8...20)))
                        .foregroundColor(.yellow.opacity(Double.random(in: 0.3...0.8)))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Celebration text
                Text("EVOLUTION!")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.white)
                    .scaleEffect(showContent ? 1 : 0.5)
                    .opacity(showContent ? 1 : 0)

                // Avatar
                AvatarView(
                    avatarState: avatarState,
                    size: .hero,
                    showMood: false,
                    isInteractive: false
                )
                .scaleEffect(showContent ? 1.2 : 0.8)

                // Stage name
                VStack(spacing: 8) {
                    Text("You are now a")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))

                    Text(evolution.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(stageColor)
                }
                .opacity(showContent ? 1 : 0)

                // Message
                Text(evolution.unlockMessage)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showContent ? 1 : 0)

                Spacer()

                // Continue button
                Button(action: onDismiss) {
                    Text("Awesome!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(stageColor)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(showContent ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.5)) {
                showStars = true
            }
        }
    }

    private var stageColor: Color {
        switch evolution.level {
        case 1: return AppTheme.sunnyYellow
        case 2: return AppTheme.vibrantTeal
        case 3: return AppTheme.playfulCoral
        case 4: return .orange
        default: return AppTheme.sunnyYellow
        }
    }
}

// MARK: - Preview

#Preview("Hero Section") {
    AvatarHeroSection(avatarService: AvatarService.shared)
        .padding()
        .background(Color.gray.opacity(0.1))
}
