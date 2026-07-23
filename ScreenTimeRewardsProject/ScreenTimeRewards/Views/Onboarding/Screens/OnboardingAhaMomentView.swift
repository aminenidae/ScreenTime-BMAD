import SwiftUI

/// "See it work" aha moment — a canned, auto-playing animation of the FULL core loop:
/// learning earns time → a reward app unlocks → the earned time is used up → the app
/// locks itself again automatically. Front-of-funnel, after the value slides.
/// Illustrative only (no real data).
struct OnboardingAhaMomentView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase {
        case learning     // earning time
        case unlocked     // reward just unlocked
        case playing      // reward time counting down
        case timeUp       // locked again automatically
    }

    @State private var phase: Phase = .learning
    @State private var learnProgress: CGFloat = 0    // 0...1, learning bar fills
    @State private var earnedMinutes: Int = 0
    @State private var rewardProgress: CGFloat = 0   // 1 = full earned time, 0 = used up
    @State private var rewardMinutesLeft: Int = 0
    @State private var isActive = true

    private let goalMinutes = 30

    private var rewardActive: Bool { phase == .unlocked || phase == .playing }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingBackButton(action: onBack)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 24)

            Text("You set it up once. The app handles the rest.")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Text("Learning earns time. Reward apps unlock — then lock again automatically when it's up.")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            Spacer()

            demoCard

            Spacer()

            Button(action: onContinue) {
                Text("Got It")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: 400)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            isActive = true
            AppAnalytics.shared.trackOnboarding(.onboardingScreenViewed, parameters: ["screen_name": "aha_moment"])
            startAnimation()
        }
        .onDisappear { isActive = false }
    }

    private var demoCard: some View {
        VStack(spacing: 18) {
            // 1) Learning in progress
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .foregroundColor(AppTheme.accentText(for: colorScheme))
                    Text("Reading")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text("\(Int(learnProgress * CGFloat(goalMinutes)))/\(goalMinutes) min")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                progressBar(fraction: learnProgress, color: AppTheme.vibrantTeal)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.card(for: colorScheme)))

            Text("\(earnedMinutes) min of reward time earned")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(AppTheme.accentText(for: colorScheme))

            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            // 2/3/4) Reward: locked → unlocked → counting down → locked again
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(rewardActive ? AppTheme.playfulCoral : Color.gray.opacity(0.35))
                            .frame(width: 54, height: 54)
                        Image(systemName: rewardActive ? "gamecontroller.fill" : "lock.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 22))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Games")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Text(rewardStatusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(rewardStatusColor)
                    }

                    Spacer()

                    if phase == .unlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppTheme.playfulCoral)
                            .font(.system(size: 24))
                            .transition(.scale.combined(with: .opacity))
                    } else if phase == .timeUp {
                        Image(systemName: "lock.fill")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 20))
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // Reward-time meter: full on unlock, drains as it's used, gone at time's up.
                if rewardActive {
                    progressBar(fraction: rewardProgress, color: AppTheme.playfulCoral)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.card(for: colorScheme)))
            .scaleEffect(phase == .unlocked ? 1.0 : 0.98)

            // Second-phase summary — mirrors the "earned" line above the reward card.
            Text(secondPhaseText)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(phase == .timeUp ? AppTheme.accentText(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(phase == .playing || phase == .timeUp ? 1 : 0)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 32)
    }

    private var secondPhaseText: String {
        phase == .timeUp
            ? "Time's up — the app locks itself"
            : "\(rewardMinutesLeft) min of reward time left"
    }

    private func progressBar(fraction: CGFloat, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 10)
    }

    private var rewardStatusText: String {
        switch phase {
        case .learning: return "Locked"
        case .unlocked: return "Unlocked!"
        case .playing:  return "\(rewardMinutesLeft) min left"
        case .timeUp:   return "Time's up — locked again"
        }
    }

    private var rewardStatusColor: Color {
        switch phase {
        case .unlocked, .playing: return AppTheme.playfulCoral
        default: return AppTheme.textSecondary(for: colorScheme)
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        if reduceMotion {
            // Respect reduced-motion: show the unlocked payoff statically, no play/loop.
            phase = .unlocked
            learnProgress = 1
            earnedMinutes = goalMinutes
            rewardProgress = 1
            rewardMinutesLeft = goalMinutes
            return
        }
        runCycle()
    }

    private func runCycle() {
        guard isActive else { return }

        // Phase 1 — learning: bar fills, earned minutes tick up, reward locked.
        phase = .learning
        earnedMinutes = 0
        rewardProgress = 0
        rewardMinutesLeft = 0
        learnProgress = 0
        withAnimation(.easeInOut(duration: 2.0)) { learnProgress = 1 }
        for minute in 1...goalMinutes {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 * Double(minute) / Double(goalMinutes)) {
                guard isActive, phase == .learning else { return }
                earnedMinutes = minute
            }
        }

        // Phase 2 — unlocked: reward flips open, full reward-time meter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            guard isActive else { return }
            rewardMinutesLeft = goalMinutes
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                phase = .unlocked
                rewardProgress = 1
            }
        }

        // Phase 3 — playing: earned time counts down, meter drains.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.3)) { phase = .playing }
            withAnimation(.easeInOut(duration: 2.0)) { rewardProgress = 0 }
            for step in 1...goalMinutes {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 * Double(step) / Double(goalMinutes)) {
                    guard isActive, phase == .playing else { return }
                    rewardMinutesLeft = goalMinutes - step
                }
            }
        }

        // Phase 4 — time's up: locks again automatically.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.7) {
            guard isActive else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { phase = .timeUp }
        }

        // Hold, then loop the whole story.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.2) {
            runCycle()
        }
    }
}

#Preview {
    OnboardingAhaMomentView(onContinue: {}, onBack: {})
}
