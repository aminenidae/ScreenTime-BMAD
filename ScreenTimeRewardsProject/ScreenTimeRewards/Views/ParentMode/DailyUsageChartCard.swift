import SwiftUI
import Charts

struct DailyUsageChartCard: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    private let daysToShow = 7

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Weekly Usage Trend")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Time period label
                Text("Last 7 Days")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AppTheme.textSecondary(for: colorScheme).opacity(0.1))
                    )
            }

            // Chart
            if #available(iOS 16.0, *) {
                chartView
                    .frame(height: 200)
            } else {
                // Fallback for iOS < 16
                Text("Charts require iOS 16+")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(height: 200)
            }

            // Legend
            HStack(spacing: AppTheme.Spacing.large) {
                legendItem(
                    color: AppTheme.vibrantTeal,
                    label: "Learning",
                    value: totalLearningMinutes
                )

                legendItem(
                    color: AppTheme.playfulCoral,
                    label: "Reward",
                    value: totalRewardMinutes
                )
            }
        }
        .padding(AppTheme.Spacing.regular)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }

    @available(iOS 16.0, *)
    private var chartView: some View {
        let learningData = viewModel.getChartDataForCategory(.learning, lastDays: daysToShow)
        let rewardData = viewModel.getChartDataForCategory(.reward, lastDays: daysToShow)

        return Chart {
            // Learning bars
            ForEach(learningData, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.minutes)
                )
                .foregroundStyle(AppTheme.vibrantTeal.gradient)
                .position(by: .value("Category", "Learning"))
            }

            // Reward bars
            ForEach(rewardData, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.minutes)
                )
                .foregroundStyle(AppTheme.playfulCoral.gradient)
                .position(by: .value("Category", "Reward"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(dayLabel(for: date))
                            .font(AppTheme.Typography.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme).opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text("\(minutes)m")
                            .font(AppTheme.Typography.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme).opacity(0.2))
            }
        }
        .chartLegend(.hidden) // We have our own legend
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.5))
                )
        }
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("\(value)m")
                .font(AppTheme.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
            return "Yest."
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE" // Mon, Tue, etc.
            return formatter.string(from: date)
        }
    }

    private var totalLearningMinutes: Int {
        viewModel.getChartDataForCategory(.learning, lastDays: daysToShow)
            .reduce(0) { $0 + $1.minutes }
    }

    private var totalRewardMinutes: Int {
        viewModel.getChartDataForCategory(.reward, lastDays: daysToShow)
            .reduce(0) { $0 + $1.minutes }
    }
}

// MARK: - Preview

#Preview {
    DailyUsageChartCard()
        .environmentObject(AppUsageViewModel())
        .padding()
        .background(Color.gray.opacity(0.1))
}
