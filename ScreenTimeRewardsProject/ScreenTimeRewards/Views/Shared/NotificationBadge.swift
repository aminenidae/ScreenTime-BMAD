import SwiftUI

/// A simple red dot notification badge similar to social media apps
/// Used to indicate items that need user attention (e.g., unnamed apps)
struct NotificationBadge: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(AppTheme.errorRed)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.2), radius: 2)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Small badge (default)
        NotificationBadge()

        // Medium badge
        NotificationBadge(size: 10)

        // Large badge
        NotificationBadge(size: 12)

        // On icon example
        ZStack(alignment: .topTrailing) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            NotificationBadge(size: 10)
                .offset(x: 4, y: -4)
        }
    }
    .padding()
}
