import SwiftUI

struct CircularProgressView: View {
    let title: String
    let current: Int
    let total: Int
    let color: Color
    let icon: String

    @Environment(\.colorScheme) var colorScheme

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(current) / Double(total), 1.0)
    }

    private var percentage: Int {
        Int(progress * 100)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2),
                        lineWidth: 14
                    )
                    .frame(width: 140, height: 140)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: 14,
                            lineCap: .round
                        )
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

                // Center content
                VStack(spacing: 2) {
                    Text("\(percentage)%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("\(current)/\(total)m")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            // Title
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}

struct CircularProgressView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            CircularProgressView(
                title: "Learning Goal",
                current: 45,
                total: 60,
                color: AppTheme.vibrantTeal,
                icon: "book.fill"
            )

            CircularProgressView(
                title: "Reward Earned",
                current: 15,
                total: 30,
                color: AppTheme.sunnyYellow,
                icon: "gamecontroller.fill"
            )
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
