import SwiftUI

/// Sheet showing detailed per-app usage for a category (Learning or Reward).
/// Displayed when tapping the usage overview cards.
struct AppUsageDetailSheet: View {
    let category: AppUsageDetail.AppCategory
    let apps: [AppUsageDetail]

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var categoryColor: Color {
        category == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    private var categoryIcon: String {
        category == .learning ? "book.fill" : "gamecontroller.fill"
    }

    private var totalMinutes: Int {
        apps.reduce(0) { $0 + $1.todaySeconds } / 60
    }

    private var sortedApps: [AppUsageDetail] {
        apps.sorted { $0.todaySeconds > $1.todaySeconds }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Summary header
                        summaryHeader

                        // App list
                        if apps.isEmpty {
                            emptyState
                        } else {
                            appsList
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("\(category.rawValue) Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(categoryColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            // Category icon
            Image(systemName: categoryIcon)
                .font(.system(size: 28))
                .foregroundColor(categoryColor)
                .frame(width: 60, height: 60)
                .background(categoryColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Total")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(totalMinutes)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(categoryColor)

                    Text("minutes")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(categoryColor.opacity(0.7))
                        .padding(.bottom, 4)
                }

                Text("\(apps.count) app\(apps.count == 1 ? "" : "s") tracked")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    // MARK: - Apps List

    private var appsList: some View {
        VStack(spacing: 12) {
            ForEach(sortedApps) { app in
                AppUsageDetailRow(app: app, categoryColor: categoryColor)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: categoryIcon)
                .font(.system(size: 50))
                .foregroundColor(categoryColor.opacity(0.3))

            Text("No \(category.rawValue.lowercased()) apps used today")
                .font(.headline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("Start using your configured apps to see usage here")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - App Usage Row

private struct AppUsageDetailRow: View {
    let app: AppUsageDetail
    let categoryColor: Color

    @Environment(\.colorScheme) var colorScheme

    private var displayName: String {
        if app.displayName.isEmpty || app.displayName.hasPrefix("Unknown") {
            let appNumber = abs(app.id.hashValue) % 100
            return "Privacy Protected App #\(appNumber)"
        }
        return app.displayName
    }

    private var minutes: Int {
        app.todaySeconds / 60
    }

    private var formattedTime: String {
        TimeFormatting.formatSecondsCompact(TimeInterval(app.todaySeconds))
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            CachedAppIcon(
                iconURL: app.iconURL,
                identifier: app.id,
                size: 44,
                fallbackSymbol: app.category == .learning ? "book.fill" : "gamecontroller.fill"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Points badge
                    if app.earnedPoints > 0 {
                        Label("\(app.earnedPoints) pts", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(AppTheme.vibrantTeal)
                    }

                    // Points per minute
                    Text("\(app.pointsPerMinute) pts/min")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            // Usage time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedTime)
                    .font(.headline)
                    .foregroundColor(categoryColor)

                Text("today")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
        )
    }
}

// MARK: - Preview

#Preview("Learning Apps") {
    AppUsageDetailSheet(
        category: .learning,
        apps: [
            AppUsageDetail(id: "1", displayName: "Duolingo", category: .learning, todaySeconds: 1800, iconURL: nil, pointsPerMinute: 2, earnedPoints: 60),
            AppUsageDetail(id: "2", displayName: "Khan Academy", category: .learning, todaySeconds: 1200, iconURL: nil, pointsPerMinute: 3, earnedPoints: 60),
            AppUsageDetail(id: "3", displayName: "Brilliant", category: .learning, todaySeconds: 600, iconURL: nil, pointsPerMinute: 2, earnedPoints: 20)
        ]
    )
}

#Preview("Empty State") {
    AppUsageDetailSheet(
        category: .reward,
        apps: []
    )
}
