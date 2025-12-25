import SwiftUI

struct StreakMilestoneCelebration: View {
    let milestone: Int
    let bonusMinutes: Int
    let appName: String
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    // Simple state for a basic particle effect if we implemented one
    @State private var particles: [Particle] = []

    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Celebration card
            VStack(spacing: 24) {
                // Trophy/flame icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.sunnyYellow.opacity(0.3),
                                    AppTheme.sunnyYellow.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 64))
                        .foregroundColor(AppTheme.sunnyYellow)
                        .shadow(color: AppTheme.sunnyYellow.opacity(0.5), radius: 20)
                }
                .scaleEffect(scale)
                .opacity(opacity)

                // Milestone text
                VStack(spacing: 8) {
                    Text("\(milestone) DAY STREAK")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(2)
                        .foregroundColor(AppTheme.sunnyYellow)

                    Text("FOR \(appName.uppercased())!")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(AppTheme.vibrantTeal)

                    Text("You earned \(bonusMinutes) bonus minutes!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: .light))
                        .padding(.top, 4)
                }
                .opacity(opacity)

                // Awesome button
                Button {
                    dismiss()
                } label: {
                    Text("AWESOME!")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(AppTheme.vibrantTeal)
                        )
                }
                .opacity(opacity)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white) // Fixed to white as per plan "fill(Color.white)"
            )
            .padding(24)
            .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
            // Trigger confetti here if available
        }
    }
    
    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    
    // Placeholder struct for particles
    struct Particle: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        var color: Color
    }
}
