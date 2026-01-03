import SwiftUI
import FamilyControls
import ManagedSettings

/// Sheet showing detailed per-app usage for a category on the child device.
/// Uses FamilyControls Label with ApplicationToken for actual app icons.
/// Observes the data adapter to update when data becomes available.
struct LocalAppUsageDetailSheet: View {
    enum CategoryType {
        case learning
        case reward

        var isLearning: Bool { self == .learning }
        var displayName: String { isLearning ? "Learning" : "Reward" }
    }

    let category: CategoryType
    @ObservedObject var dataAdapter: LocalDashboardDataAdapter

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var learningSnapshots: [LearningAppSnapshot] {
        dataAdapter.learningSnapshots
    }

    private var rewardSnapshots: [RewardAppSnapshot] {
        dataAdapter.rewardSnapshots
    }

    private var appCount: Int {
        category.isLearning ? learningSnapshots.count : rewardSnapshots.count
    }

    private var totalSeconds: Int {
        category.isLearning
            ? learningSnapshots.reduce(0) { $0 + Int($1.totalSeconds) }
            : rewardSnapshots.reduce(0) { $0 + Int($1.totalSeconds) }
    }

    private var categoryColor: Color {
        category.isLearning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    private var categoryIcon: String {
        category.isLearning ? "book.fill" : "gamecontroller.fill"
    }

    private var totalMinutes: Int {
        totalSeconds / 60
    }

    var body: some View {
        let _ = {
            #if DEBUG
            print("[LocalAppUsageDetailSheet] 🔄 body evaluated - appCount: \(appCount), category: \(category)")
            #endif
        }()

        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Summary header
                        summaryHeader

                        // App list
                        if appCount == 0 {
                            emptyState
                        } else {
                            appsList
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("\(category.displayName) Apps")
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
        .id(appCount)  // Force re-render when app count changes
        .onAppear {
            #if DEBUG
            print("[LocalAppUsageDetailSheet] ✅ onAppear - appCount: \(appCount)")
            print("[LocalAppUsageDetailSheet]   learningSnapshots: \(learningSnapshots.count)")
            print("[LocalAppUsageDetailSheet]   rewardSnapshots: \(rewardSnapshots.count)")
            #endif
        }
        .onChange(of: appCount) { newCount in
            #if DEBUG
            print("[LocalAppUsageDetailSheet] 🔔 appCount changed to: \(newCount)")
            #endif
        }
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

                Text("\(appCount) app\(appCount == 1 ? "" : "s") tracked")
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
            if category.isLearning {
                ForEach(sortedLearningApps) { snapshot in
                    LearningAppRow(snapshot: snapshot, categoryColor: categoryColor)
                }
            } else {
                ForEach(sortedRewardApps) { snapshot in
                    RewardAppRow(snapshot: snapshot, categoryColor: categoryColor)
                }
            }
        }
    }

    private var sortedLearningApps: [LearningAppSnapshot] {
        learningSnapshots.sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var sortedRewardApps: [RewardAppSnapshot] {
        rewardSnapshots.sorted { $0.totalSeconds > $1.totalSeconds }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: categoryIcon)
                .font(.system(size: 50))
                .foregroundColor(categoryColor.opacity(0.3))

            Text("No \(category.displayName.lowercased()) apps used today")
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

// MARK: - Learning App Row

private struct LearningAppRow: View {
    let snapshot: LearningAppSnapshot
    let categoryColor: Color

    @Environment(\.colorScheme) var colorScheme

    private var displayName: String {
        if snapshot.displayName.isEmpty || snapshot.displayName.hasPrefix("Unknown") {
            let appNumber = abs(snapshot.tokenHash.hashValue) % 100
            return "Privacy Protected App #\(appNumber)"
        }
        return snapshot.displayName
    }

    private var formattedTime: String {
        TimeFormatting.formatSecondsCompact(snapshot.totalSeconds)
    }

    /// Use cream color in dark mode for learning apps
    private var timeColor: Color {
        colorScheme == .dark ? AppTheme.lightCream : categoryColor
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon using FamilyControls Label
            appIconView

            Text(displayName)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .lineLimit(1)

            Spacer()

            // Usage time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedTime)
                    .font(.headline)
                    .foregroundColor(timeColor)

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

    @ViewBuilder
    private var appIconView: some View {
        if #available(iOS 15.2, *) {
            Label(snapshot.token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.35)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // Fallback for older iOS
            RoundedRectangle(cornerRadius: 10)
                .fill(categoryColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "book.fill")
                        .foregroundColor(categoryColor)
                )
        }
    }
}

// MARK: - Reward App Row

private struct RewardAppRow: View {
    let snapshot: RewardAppSnapshot
    let categoryColor: Color

    @Environment(\.colorScheme) var colorScheme

    private var displayName: String {
        if snapshot.displayName.isEmpty || snapshot.displayName.hasPrefix("Unknown") {
            let appNumber = abs(snapshot.tokenHash.hashValue) % 100
            return "Privacy Protected App #\(appNumber)"
        }
        return snapshot.displayName
    }

    private var formattedTime: String {
        TimeFormatting.formatSecondsCompact(snapshot.totalSeconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon using FamilyControls Label
            appIconView

            Text(displayName)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .lineLimit(1)

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

    @ViewBuilder
    private var appIconView: some View {
        if #available(iOS 15.2, *) {
            Label(snapshot.token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.35)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // Fallback for older iOS
            RoundedRectangle(cornerRadius: 10)
                .fill(categoryColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(categoryColor)
                )
        }
    }
}
