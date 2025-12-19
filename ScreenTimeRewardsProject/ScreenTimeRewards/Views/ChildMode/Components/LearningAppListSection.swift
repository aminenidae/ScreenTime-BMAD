import SwiftUI
import FamilyControls
import ManagedSettings

/// Section displaying learning apps with usage times and earning progress
struct LearningAppListSection: View {
    let snapshots: [LearningAppSnapshot]
    let totalSeconds: TimeInterval

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = true

    // Design colors
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)

    private var totalMinutes: Int {
        Int(totalSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            sectionHeader

            // App list
            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        learningAppRow(snapshot: snapshot)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: isExpanded)
                    }
                }
            }

            // Empty state
            if snapshots.isEmpty {
                emptyState
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(tealColor.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: "book.fill")
                    .font(.system(size: 18))
                    .foregroundColor(tealColor)

                // Title
                Text("LEARNING APPS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(tealColor)

                Spacer()

                // Total time badge
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                    Text("\(totalMinutes) MIN")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(tealColor.opacity(0.6))

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealColor.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
    }

    private func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        HStack(spacing: 12) {
            // App icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tealColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(tealColor)
                    )
            }

            // App name
            VStack(alignment: .leading, spacing: 2) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(tealColor)
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(tealColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Usage time
            Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tealColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tealColor.opacity(0.05))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundColor(tealColor.opacity(0.4))

            Text("No learning apps used today")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(tealColor.opacity(0.6))

            Text("Start using your learning apps to earn reward time!")
                .font(.system(size: 13))
                .foregroundColor(tealColor.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // With apps
            LearningAppListSection(
                snapshots: [],
                totalSeconds: 2700  // 45 minutes
            )

            // Empty state
            LearningAppListSection(
                snapshots: [],
                totalSeconds: 0
            )
        }
        .padding()
    }
    .background(AppTheme.background(for: .light))
}
