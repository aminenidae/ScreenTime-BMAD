import SwiftUI
import FamilyControls

struct LearningAppDetailView: View {
    let snapshot: LearningAppSnapshot
    @State private var usage: AppUsage?
    @Environment(\.dismiss) private var dismiss
    private let service = ScreenTimeService.shared

    var body: some View {
        NavigationStack {
            AppUsageDetailContent(
                title: snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName,
                subtitle: "Learning app overview",
                accentColor: AppTheme.vibrantTeal,
                usage: usage,
                pointsPerMinute: snapshot.pointsPerMinute
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // App icon in center (principal position)
                ToolbarItem(placement: .principal) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(2.7)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        // Fallback for iOS < 15.2
                        Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                            .font(.headline)
                    }
                }

                // Keep existing Done button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            usage = service.getUsage(for: snapshot.token)
        }
    }
}

struct RewardAppDetailView: View {
    let snapshot: RewardAppSnapshot
    @State private var usage: AppUsage?
    @Environment(\.dismiss) private var dismiss
    private let service = ScreenTimeService.shared

    var body: some View {
        NavigationStack {
            AppUsageDetailContent(
                title: snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName,
                subtitle: "Reward app overview",
                accentColor: AppTheme.playfulCoral,
                usage: usage,
                pointsPerMinute: snapshot.pointsPerMinute
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // App icon in center (principal position)
                ToolbarItem(placement: .principal) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(2.7)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        // Fallback for iOS < 15.2
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.headline)
                    }
                }

                // Keep existing Done button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            usage = service.getUsage(for: snapshot.token)
        }
    }
}

// MARK: - Shared Content

private struct AppUsageDetailContent: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let usage: AppUsage?
    let pointsPerMinute: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                usageBreakdownCard
                insightsCard
                extraIdeasCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var usageBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Breakdown")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            HStack(spacing: 12) {
                UsagePill(
                    title: "Daily",
                    minutes: minutesText(for: usage?.last24HoursUsage ?? 0),
                    annotation: "\(pointsEarned(for: usage?.last24HoursUsage ?? 0)) pts",
                    accent: accentColor
                )
                UsagePill(
                    title: "Weekly",
                    minutes: minutesText(for: usage?.last7DaysUsage ?? 0),
                    annotation: "\(pointsEarned(for: usage?.last7DaysUsage ?? 0)) pts",
                    accent: accentColor.opacity(0.9)
                )
                UsagePill(
                    title: "Monthly",
                    minutes: minutesText(for: usage?.last30DaysUsage ?? 0),
                    annotation: "\(pointsEarned(for: usage?.last30DaysUsage ?? 0)) pts",
                    accent: accentColor.opacity(0.7)
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 4)
        )
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(spacing: 12) {
                insightRow(
                    icon: "bolt.fill",
                    title: "Points Earned Today",
                    value: "\(pointsEarned(for: usage?.last24HoursUsage ?? 0)) pts"
                )

                insightRow(
                    icon: "clock.arrow.circlepath",
                    title: "Average Session",
                    value: formattedDuration(usage?.averageSessionDuration ?? 0)
                )

                insightRow(
                    icon: "flame.fill",
                    title: "Longest Session",
                    value: formattedDuration(usage?.longestSessionDuration ?? 0)
                )

                insightRow(
                    icon: "calendar",
                    title: "Last Active",
                    value: usage?.lastAccess.formatted(date: .abbreviated, time: .shortened) ?? "No data"
                )

                insightRow(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "Sessions Today",
                    value: "\(usage?.sessionsTodayCount ?? 0)"
                )

                insightRow(
                    icon: "star.circle.fill",
                    title: "Total Points",
                    value: "\(usage?.earnedRewardPoints ?? 0) pts"
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 4)
        )
    }

    private var extraIdeasCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ideas to Explore")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("• Add a “focus score” that rewards consistent daily usage.\n• Track the best day of the week for this app.\n• Show how much challenge progress this app contributes.\n• Surface recommendations when usage trends downward.")
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.background(for: colorScheme).opacity(0.6))
        )
    }

    private func usageDuration(for interval: TimeInterval) -> Int {
        Int(interval / 60)
    }

    private func minutesText(for interval: TimeInterval) -> String {
        let minutes = usageDuration(for: interval)
        return minutes >= 60
            ? String(format: "%.1fh", Double(minutes) / 60.0)
            : "\(minutes)m"
    }

    private func pointsEarned(for interval: TimeInterval) -> Int {
        let minutes = usageDuration(for: interval)
        return minutes * max(pointsPerMinute, 0)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remaining = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remaining)m"
        }
        return "\(max(1, minutes))m"
    }

    private func insightRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.15))
                .foregroundColor(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text(value)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct UsagePill: View {
    let title: String
    let minutes: String
    let annotation: String
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(accent.opacity(0.8))

            Text(minutes)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(annotation)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
    }
}
