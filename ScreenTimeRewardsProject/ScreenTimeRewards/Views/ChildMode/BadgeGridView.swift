import SwiftUI

struct BadgeGridView: View {
    let badges: [Badge]

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(badges) { badge in
                badgeCard(for: badge)
            }
        }
        .padding(.horizontal, 16)
    }

    private func badgeCard(for badge: Badge) -> some View {
        let isUnlocked = badge.isUnlocked

        return VStack(spacing: 8) {
            // Badge icon container
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isUnlocked ? Colors.primaryLight : Colors.lockedBackground)

                Image(systemName: badge.iconName ?? "star.fill")
                    .font(.system(size: 50))
                    .foregroundColor(isUnlocked ? Colors.primary : Colors.lockedIcon)

                // Lock overlay for locked badges
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Colors.lockedIconDark)
                }
            }
            .aspectRatio(1.0, contentMode: .fit)

            // Badge info
            VStack(spacing: 2) {
                Text(badge.badgeName ?? "Badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let unlockedAt = badge.unlockedAt, isUnlocked {
                    Text("Unlocked \(formattedDate(unlockedAt))")
                        .font(.system(size: 12))
                        .foregroundColor(Colors.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(badge.badgeDescription ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .opacity(isUnlocked ? 1.0 : 0.4)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Design Tokens
extension BadgeGridView {
    struct Colors {
        static let primary = Color(hex: "019863")
        static let primaryLight = Color(hex: "019863").opacity(0.2)
        static let textPrimary = Color(uiColor: .label)
        static let textSecondary = Color(uiColor: .secondaryLabel)
        static let lockedBackground = Color(uiColor: .secondarySystemBackground)
        static let lockedIcon = Color(uiColor: .secondaryLabel)
        static let lockedIconDark = Color(uiColor: .tertiaryLabel)
    }
}

