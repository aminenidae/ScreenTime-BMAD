//
//  AvatarView.swift
//  ScreenTimeRewards
//
//  Displays the avatar with current evolution stage, mood, and accessories
//

import SwiftUI

struct AvatarView: View {
    let avatarState: AvatarState?
    let size: AvatarSize
    var showMood: Bool = true
    var isInteractive: Bool = true
    var onTap: (() -> Void)?

    @State private var isAnimating = false
    @State private var bounceOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0

    enum AvatarSize: CGFloat {
        case small = 60      // For lists
        case medium = 100    // For cards
        case large = 140     // For showcases
        case hero = 180      // For main display

        var iconSize: CGFloat {
            switch self {
            case .small: return 28
            case .medium: return 44
            case .large: return 60
            case .hero: return 80
            }
        }

        var moodSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            case .hero: return 28
            }
        }

        var accessoryScale: CGFloat {
            switch self {
            case .small: return 0.5
            case .medium: return 0.7
            case .large: return 0.85
            case .hero: return 1.0
            }
        }
    }

    var body: some View {
        ZStack {
            // Background layer (if equipped)
            backgroundLayer

            // Main avatar
            avatarBody
                .offset(y: bounceOffset)

            // Mood indicator
            if showMood {
                moodIndicator
            }

            // Effect overlay (if equipped)
            effectOverlay
        }
        .frame(width: size.rawValue, height: size.rawValue)
        .onTapGesture {
            if isInteractive {
                triggerTapAnimation()
                onTap?()
            }
        }
        .onAppear {
            startIdleAnimation()
        }
    }

    // MARK: - Avatar Body

    private var avatarBody: some View {
        ZStack {
            // Base circle with gradient
            Circle()
                .fill(avatarGradient)
                .frame(width: size.rawValue * 0.85, height: size.rawValue * 0.85)
                .shadow(color: stageColor.opacity(0.3), radius: 8, y: 4)

            // Avatar icon
            Image(systemName: currentStageAsset)
                .font(.system(size: size.iconSize, weight: .bold))
                .foregroundStyle(stageGradient)
                .rotationEffect(.degrees(rotationAngle))

            // Hat accessory
            if let hat = equippedHat {
                Image(systemName: hat.asset)
                    .font(.system(size: size.iconSize * 0.5 * size.accessoryScale))
                    .foregroundColor(hat.rarity.color)
                    .offset(y: -size.rawValue * 0.25)
            }

            // Glasses accessory
            if let glasses = equippedGlasses {
                Image(systemName: glasses.asset)
                    .font(.system(size: size.iconSize * 0.35 * size.accessoryScale))
                    .foregroundColor(glasses.rarity.color)
                    .offset(y: -size.rawValue * 0.02)
            }
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        if let bg = equippedBackground {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [bg.rarity.color.opacity(0.3), bg.rarity.color.opacity(0.1)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.rawValue * 0.5
                    )
                )
                .frame(width: size.rawValue, height: size.rawValue)
        }
    }

    // MARK: - Effect Overlay

    @ViewBuilder
    private var effectOverlay: some View {
        if let effect = equippedEffect {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: effect.asset)
                    .font(.system(size: size.iconSize * 0.25))
                    .foregroundColor(effect.rarity.color)
                    .offset(
                        x: CGFloat.random(in: -size.rawValue * 0.3...size.rawValue * 0.3),
                        y: CGFloat.random(in: -size.rawValue * 0.3...size.rawValue * 0.3)
                    )
                    .opacity(isAnimating ? 0.8 : 0.4)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever()
                        .delay(Double(index) * 0.3),
                        value: isAnimating
                    )
            }
        }
    }

    // MARK: - Mood Indicator

    private var moodIndicator: some View {
        Image(systemName: currentMood.sfSymbol)
            .font(.system(size: size.moodSize, weight: .semibold))
            .foregroundColor(moodColor)
            .padding(4)
            .background(
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )
            .offset(x: size.rawValue * 0.35, y: size.rawValue * 0.3)
    }

    // MARK: - Computed Properties

    private var currentStageAsset: String {
        avatarState?.currentEvolutionStage?.asset ?? "star.fill"
    }

    private var currentMood: AvatarMood {
        avatarState?.mood ?? .happy
    }

    private var currentLevel: Int {
        Int(avatarState?.currentStageLevel ?? 1)
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

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [stageColor.opacity(0.2), stageColor.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stageGradient: LinearGradient {
        LinearGradient(
            colors: [stageColor, stageColor.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var moodColor: Color {
        switch currentMood {
        case .happy, .excited, .celebrating: return AppTheme.sunnyYellow
        case .neutral: return .gray
        case .sleepy: return .purple.opacity(0.7)
        case .sad: return .blue
        }
    }

    // MARK: - Equipped Accessories

    private var equippedHat: AvatarAccessory? {
        guard let hatID = avatarState?.equippedAccessories.hat else { return nil }
        return AvatarCatalog.accessory(for: hatID)
    }

    private var equippedGlasses: AvatarAccessory? {
        guard let glassesID = avatarState?.equippedAccessories.glasses else { return nil }
        return AvatarCatalog.accessory(for: glassesID)
    }

    private var equippedBackground: AvatarAccessory? {
        guard let bgID = avatarState?.equippedAccessories.background else { return nil }
        return AvatarCatalog.accessory(for: bgID)
    }

    private var equippedEffect: AvatarAccessory? {
        guard let effectID = avatarState?.equippedAccessories.effect else { return nil }
        return AvatarCatalog.accessory(for: effectID)
    }

    // MARK: - Animations

    private func startIdleAnimation() {
        isAnimating = true

        // Subtle floating animation
        withAnimation(
            .easeInOut(duration: 2)
            .repeatForever(autoreverses: true)
        ) {
            bounceOffset = -4
        }
    }

    private func triggerTapAnimation() {
        // Quick bounce
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bounceOffset = -12
        }

        // Subtle rotation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            rotationAngle = 10
        }

        // Reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                rotationAngle = 0
            }
        }
    }
}

// MARK: - Preview Provider

#Preview("Avatar Sizes") {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            AvatarView(avatarState: nil, size: .small)
            AvatarView(avatarState: nil, size: .medium)
        }
        HStack(spacing: 20) {
            AvatarView(avatarState: nil, size: .large)
            AvatarView(avatarState: nil, size: .hero)
        }
    }
    .padding()
}
