import SwiftUI

struct CompletionCelebrationView: View {
    let title: String
    let subtitle: String
    let buttonText: String
    let onDismiss: () -> Void

    @State private var animate = false

    var body: some View {
        ZStack {
            // Purple overlay background - #4B0082 at 80% opacity
            DesignTokens.overlayBackground
                .ignoresSafeArea()
                .transition(.opacity)

            // Confetti overlay
            confettiOverlay

            // Modal content
            VStack(spacing: 16) {
                // Trophy Icon - 120px in HTML
                Image(systemName: "trophy.fill")
                    .font(.system(size: 120))
                    .foregroundColor(DesignTokens.accent)

                // Headline - 32px, bold, white
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Body text - 16px, white at 90% opacity
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                // Button with top padding
                Button(action: onDismiss) {
                    Text(buttonText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.buttonTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DesignTokens.primary)
                        .cornerRadius(12)
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: 343) // max-w-sm approximates to ~343pt
            .padding(.horizontal, 16)
            .scaleEffect(animate ? 1 : 0.8)
            .opacity(animate ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    animate = true
                }
            }
        }
    }

    private var confettiOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<11, id: \.self) { index in
                    ConfettiPiece(
                        color: confettiColor(for: index),
                        xPosition: confettiXPosition(for: index, width: geometry.size.width),
                        duration: confettiDuration(for: index),
                        delay: confettiDelay(for: index),
                        animate: animate
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func confettiColor(for index: Int) -> Color {
        // Matches HTML: gold, teal, magenta, blue pattern
        let colors = [
            DesignTokens.accent,           // gold
            DesignTokens.primary,          // teal
            DesignTokens.confettiMagenta,  // magenta
            DesignTokens.confettiBlue      // blue
        ]

        let colorIndex: Int
        switch index {
        case 0: colorIndex = 0  // gold
        case 1: colorIndex = 1  // teal
        case 2: colorIndex = 2  // magenta
        case 3: colorIndex = 3  // blue
        case 4: colorIndex = 0  // gold
        case 5: colorIndex = 1  // teal
        case 6: colorIndex = 2  // magenta
        case 7: colorIndex = 3  // blue
        case 8: colorIndex = 0  // gold
        case 9: colorIndex = 1  // teal
        case 10: colorIndex = 2 // magenta
        default: colorIndex = 0
        }
        return colors[colorIndex]
    }

    private func confettiXPosition(for index: Int, width: CGFloat) -> CGFloat {
        let positions: [CGFloat] = [0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.15, 0.85]
        return width * positions[index]
    }

    private func confettiDuration(for index: Int) -> Double {
        let durations: [Double] = [4, 6, 5, 4.5, 7, 5.5, 6.5, 4, 5, 7, 6]
        return durations[index]
    }

    private func confettiDelay(for index: Int) -> Double {
        let delays: [Double] = [0.5, 1.5, 0, 2, 1, 2.5, 0.2, 3, 1.8, 3.5, 4]
        return delays[index]
    }
}

// Confetti piece view that animates falling
struct ConfettiPiece: View {
    let color: Color
    let xPosition: CGFloat
    let duration: Double
    let delay: Double
    let animate: Bool

    @State private var yOffset: CGFloat = -50
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 8, height: 16)
            .opacity(opacity * 0.8)
            .rotationEffect(.degrees(rotation))
            .position(x: xPosition, y: yOffset)
            .onChange(of: animate) { newValue in
                if newValue {
                    withAnimation(
                        Animation.linear(duration: duration)
                            .delay(delay)
                            .repeatForever(autoreverses: false)
                    ) {
                        yOffset = UIScreen.main.bounds.height + 100
                        rotation = 720
                        opacity = 0
                    }
                }
            }
    }
}

// Design tokens extracted from HTML/CSS
extension CompletionCelebrationView {
    struct DesignTokens {
        // Colors from Tailwind config
        static let primary = Color(hex: "#00C49A")         // Teal
        static let accent = Color(hex: "#FFD700")          // Gold
        static let overlayBackground = Color(hex: "#4B0082").opacity(0.8)  // Purple at 80%
        static let buttonTextColor = Color(hex: "#111811") // Near black

        // Additional confetti colors
        static let confettiMagenta = Color(hex: "#FF00FF")
        static let confettiBlue = Color(hex: "#007BFF")
    }
}

