import SwiftUI
import FamilyControls
import ManagedSettings

/// Section for learning apps that aren't linked to any reward app's unlock requirements.
/// Shown at the bottom of the child dashboard so the child can still see their usage,
/// but it's visually separated from the reward unlock cards.
struct BonusLearningSection: View {
    let snapshots: [LearningAppSnapshot]
    let totalSeconds: TimeInterval

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = true
    @State private var selectedApp: LearningAppSnapshot?

    private var totalMinutes: Int {
        Int(totalSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        Button {
                            selectedApp = snapshot
                        } label: {
                            learningAppRow(snapshot: snapshot)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: isExpanded)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.1), lineWidth: 1)
                )
        )
        .sheet(item: $selectedApp) { app in
            LearningAppDetailView(snapshot: app, showConfiguration: false)
        }
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(colorScheme == .light ? AppTheme.vibrantTeal : AppTheme.lightCream)

                Text("BONUS LEARNING")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                    Text("\(totalMinutes) MIN")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.lightCream.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
    }

    private func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        HStack(spacing: 12) {
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.35)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.vibrantTeal.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.lightCream)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(TimeFormatting.formatSecondsCompact(snapshot.totalSeconds))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.vibrantTeal.opacity(0.05))
        )
    }
}
