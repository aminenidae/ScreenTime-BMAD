import SwiftUI
import CoreData
import Charts

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

            if #available(iOS 16.0, *) {
                chartView
                    .frame(height: 200)
            } else {
                Text("Charts require iOS 16+")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(height: 200)
            }
        }
    }

    @available(iOS 16.0, *)
    private var chartView: some View {
        let sortedData = dailyTotals.sorted { $0.date < $1.date }

        return Chart {
            ForEach(sortedData, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.learningSeconds / 60)
                )
                .foregroundStyle(AppTheme.vibrantTeal.gradient)
                .position(by: .value("Category", "Learning"))

                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.rewardSeconds / 60)
                )
                .foregroundStyle(AppTheme.playfulCoral.gradient)
                .position(by: .value("Category", "Reward"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(formatDateLabel(date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.vibrantTeal.opacity(0.15))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.vibrantTeal.opacity(0.15))
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.vibrantTeal.opacity(0.03))
                )
        }
    }

    private func formatDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
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
