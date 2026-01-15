import SwiftUI
import CoreData

struct HistoricalReportsView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var selectedDateRange: DateRange = .week
    @Environment(\.colorScheme) var colorScheme

    enum DateRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }

    /// Get filtered daily totals based on selected date range
    private var filteredDailyTotals: [(date: Date, learningSeconds: Int, rewardSeconds: Int)] {
        Array(viewModel.aggregatedDailyTotals.prefix(selectedDateRange.days))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Historical Reports")
                    .font(.headline)

                Spacer()

                Picker("Date Range", selection: $selectedDateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
            }

            if viewModel.childDailyUsageHistory.isEmpty && !viewModel.isLoading {
                EmptyReportsView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(filteredDailyTotals, id: \.date) { dayData in
                            DailyTotalCard(
                                date: dayData.date,
                                learningSeconds: dayData.learningSeconds,
                                rewardSeconds: dayData.rewardSeconds
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                UsageTrendChart(dailyTotals: filteredDailyTotals)

                CategoryBreakdownView(dailyTotals: filteredDailyTotals)
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        )
    }
}

private struct EmptyReportsView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            Text("No historical data")
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            Text("Reports will appear here after your child uses apps")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

private struct DailyTotalCard: View {
    let date: Date
    let learningSeconds: Int
    let rewardSeconds: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Text(formatDate(date))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            VStack(spacing: 8) {
                StatItem(
                    title: "Learning",
                    value: TimeFormatting.formatSeconds(learningSeconds),
                    icon: "book",
                    color: AppTheme.vibrantTeal
                )

                StatItem(
                    title: "Reward",
                    value: TimeFormatting.formatSeconds(rewardSeconds),
                    icon: "gamecontroller",
                    color: AppTheme.playfulCoral
                )

                StatItem(
                    title: "Total",
                    value: TimeFormatting.formatSeconds(learningSeconds + rewardSeconds),
                    icon: "clock",
                    color: AppTheme.textSecondary(for: colorScheme)
                )
            }
        }
        .frame(width: 120)
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.small)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
    }
}

private struct UsageTrendChart: View {
    let dailyTotals: [(date: Date, learningSeconds: Int, rewardSeconds: Int)]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Trend")
                .font(.headline)
                .fontWeight(.medium)

            GeometryReader { geometry in
                let chartWidth = geometry.size.width
                let chartHeight = geometry.size.height - 40 // Space for labels

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    ForEach(0..<5) { index in
                        Path { path in
                            let y = chartHeight - CGFloat(index) * (chartHeight / 4)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: chartWidth, y: y))
                        }
                        .stroke(AppTheme.border(for: colorScheme), lineWidth: 0.5)
                    }

                    // Data points and lines (show total time)
                    if !dailyTotals.isEmpty && dailyTotals.count > 1 {
                        let maxTime = dailyTotals.map { $0.learningSeconds + $0.rewardSeconds }.max() ?? 1
                        let sortedByDate = dailyTotals.sorted { $0.date < $1.date }

                        ForEach(Array(sortedByDate.enumerated()), id: \.element.date) { index, dayData in
                            let totalSeconds = dayData.learningSeconds + dayData.rewardSeconds
                            let x = CGFloat(index) * (chartWidth / CGFloat(sortedByDate.count - 1))
                            let y = chartHeight - (CGFloat(totalSeconds) / CGFloat(maxTime)) * chartHeight

                            // Point
                            Circle()
                                .fill(AppTheme.vibrantTeal)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: y)

                            // Line to next point
                            if index < sortedByDate.count - 1 {
                                let nextData = sortedByDate[index + 1]
                                let nextTotal = nextData.learningSeconds + nextData.rewardSeconds
                                let nextX = CGFloat(index + 1) * (chartWidth / CGFloat(sortedByDate.count - 1))
                                let nextY = chartHeight - (CGFloat(nextTotal) / CGFloat(maxTime)) * chartHeight

                                Path { path in
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: nextX, y: nextY))
                                }
                                .stroke(AppTheme.vibrantTeal, lineWidth: 2)
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
            }
            .frame(height: 200)
        }
    }
}

private struct CategoryBreakdownView: View {
    let dailyTotals: [(date: Date, learningSeconds: Int, rewardSeconds: Int)]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)
                .fontWeight(.medium)

            if !dailyTotals.isEmpty {
                let totalLearning = dailyTotals.reduce(0) { $0 + $1.learningSeconds }
                let totalReward = dailyTotals.reduce(0) { $0 + $1.rewardSeconds }
                let totalTime = totalLearning + totalReward

                if totalTime > 0 {
                    VStack(spacing: 8) {
                        HStack {
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                                .fill(AppTheme.vibrantTeal)
                                .frame(width: CGFloat(totalLearning) / CGFloat(totalTime) * 200, height: 20)

                            Text("Learning")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }

                        HStack {
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                                .fill(AppTheme.playfulCoral)
                                .frame(width: CGFloat(totalReward) / CGFloat(totalTime) * 200, height: 20)

                            Text("Reward")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }

                    HStack {
                        StatBadge(
                            title: "Learning",
                            value: TimeFormatting.formatSeconds(totalLearning),
                            color: AppTheme.vibrantTeal
                        )

                        StatBadge(
                            title: "Reward",
                            value: TimeFormatting.formatSeconds(totalReward),
                            color: AppTheme.playfulCoral
                        )
                    }
                }
            }
        }
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct HistoricalReportsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()

        return HistoricalReportsView(viewModel: viewModel)
            .padding()
    }
}
