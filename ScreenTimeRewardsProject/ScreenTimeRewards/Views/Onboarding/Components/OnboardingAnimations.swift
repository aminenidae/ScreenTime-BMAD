import SwiftUI

// MARK: - Confetti Animation
struct OnboardingConfettiView: View {
    @State private var confettiPieces: [OnboardingConfettiPiece] = []
    let isActive: Bool

    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                OnboardingConfettiShape(color: piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .position(piece.position)
                    .rotationEffect(piece.rotation)
                    .opacity(piece.opacity)
            }
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                generateConfetti()
            } else {
                confettiPieces.removeAll()
            }
        }
    }

    private func generateConfetti() {
        confettiPieces = (0..<50).map { _ in
            OnboardingConfettiPiece(
                color: [.red, .blue, .green, .yellow, .orange, .purple, .pink].randomElement()!,
                size: CGFloat.random(in: 8...15),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -50
                ),
                rotation: Angle(degrees: Double.random(in: 0...360))
            )
        }

        // Animate confetti falling
        for (index, _) in confettiPieces.enumerated() {
            withAnimation(
                .easeIn(duration: Double.random(in: 2...3))
                    .delay(Double.random(in: 0...0.5))
            ) {
                confettiPieces[index].position.y = UIScreen.main.bounds.height + 50
                confettiPieces[index].opacity = 0
                confettiPieces[index].rotation = Angle(degrees: Double.random(in: 360...720))
            }
        }

        // Clean up after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            confettiPieces.removeAll()
        }
    }
}

private struct OnboardingConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var rotation: Angle
    var opacity: Double = 1.0
}

private struct OnboardingConfettiShape: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
    }
}

// MARK: - Floating Animation
struct FloatingElement: View {
    let emoji: String
    let fromY: CGFloat
    let toY: CGFloat
    @Binding var isAnimating: Bool

    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: 60))
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: offset + fromY)
            .onChange(of: isAnimating) { newValue in
                if newValue {
                    startAnimation()
                } else {
                    resetAnimation()
                }
            }
    }

    private func startAnimation() {
        // Phase 1: Appear and grow
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            scale = 1.0
            opacity = 1.0
        }

        // Phase 2: Float up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.8)) {
                offset = toY - fromY
            }
        }
    }

    private func resetAnimation() {
        offset = 0
        scale = 0.1
        opacity = 0
    }
}

// MARK: - Pulse Animation
struct PulsingButton<Content: View>: View {
    let content: Content
    let shouldPulse: Bool

    @State private var isPulsing = false

    init(shouldPulse: Bool = true, @ViewBuilder content: () -> Content) {
        self.shouldPulse = shouldPulse
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .shadow(color: AppTheme.vibrantTeal.opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? 20 : 10)
            .onAppear {
                if shouldPulse {
                    startPulsing()
                }
            }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

// MARK: - Number Counter Animation
struct AnimatedNumberCounter: View {
    let targetNumber: Int
    @Binding var currentNumber: Int
    let duration: Double

    var body: some View {
        Text("\(currentNumber)")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundColor(AppTheme.sunnyYellow)
            .contentTransition(.numericText())
            .onChange(of: targetNumber) { newValue in
                animateCount(to: newValue)
            }
    }

    private func animateCount(to target: Int) {
        let steps = 10
        let stepDuration = duration / Double(steps)
        let increment = (target - currentNumber) / steps

        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                withAnimation(.easeOut) {
                    if step == steps {
                        currentNumber = target
                    } else {
                        currentNumber += increment
                    }
                }
            }
        }
    }
}

// MARK: - Unlock Animation
struct UnlockAnimation: View {
    @Binding var isUnlocked: Bool
    let iconName: String

    var body: some View {
        ZStack {
            // App icon
            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : .gray)
                .scaleEffect(isUnlocked ? 1.2 : 1.0)

            // Lock overlay
            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.9))
                    )
                    .offset(x: 20, y: 20)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isUnlocked)
    }
}

// MARK: - Treasure Chest Animation
struct TreasureChestAnimation: View {
    @Binding var isOpen: Bool

    var body: some View {
        ZStack {
            // Chest bottom
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.brown, Color.brown.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 100, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow, lineWidth: 3)
                )

            // Chest lid
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.brown, Color.brown.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 100, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow, lineWidth: 3)
                )
                .offset(y: isOpen ? -50 : -20)
                .rotationEffect(.degrees(isOpen ? -30 : 0), anchor: .bottom)

            // Glow when open
            if isOpen {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.sunnyYellow.opacity(0.6), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .offset(y: -10)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isOpen)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        Text("Animations Preview")
            .font(.headline)

        TreasureChestAnimation(isOpen: .constant(true))

        UnlockAnimation(isUnlocked: .constant(false), iconName: "gamecontroller.fill")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
