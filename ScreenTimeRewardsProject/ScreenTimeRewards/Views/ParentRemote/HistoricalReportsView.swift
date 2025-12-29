import SwiftUI
import CoreData

struct HistoricalReportsView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var selectedDateRange: DateRange = .week
    @Environment(\.colorScheme) var colorScheme
    
    enum DateRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }
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
            
            if viewModel.dailySummaries.isEmpty && !viewModel.isLoading {
                EmptyReportsView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.dailySummaries.prefix(selectedDateRange.days), id: \.summaryID) { summary in
                            if let date = summary.date {
                                DailySummaryCard(summary: summary, date: date)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                WeeklyTrendChart(dailySummaries: Array(viewModel.dailySummaries.prefix(selectedDateRange.days)))
                
                CategoryBreakdownView(dailySummaries: Array(viewModel.dailySummaries.prefix(selectedDateRange.days)))
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

private struct DailySummaryCard: View {
    let summary: DailySummary
    let date: Date
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
                    value: TimeFormatting.formatSeconds(summary.totalLearningSeconds),
                    icon: "book",
                    color: AppTheme.vibrantTeal
                )

                StatItem(
                    title: "Reward",
                    value: TimeFormatting.formatSeconds(summary.totalRewardSeconds),
                    icon: "gamecontroller",
                    color: AppTheme.playfulCoral
                )

                StatItem(
                    title: "Points",
                    value: String(summary.totalPointsEarned),
                    icon: "star",
                    color: AppTheme.sunnyYellow
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

private struct WeeklyTrendChart: View {
    let dailySummaries: [DailySummary]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Trend")
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
                    
                    // Data points and lines
                    if !dailySummaries.isEmpty {
                        let maxPoints = dailySummaries.map { $0.totalPointsEarned }.max() ?? 1
                        
                        ForEach(Array(dailySummaries.enumerated()), id: \.element.summaryID) { index, summary in
                            let x = CGFloat(index) * (chartWidth / CGFloat(dailySummaries.count - 1))
                            let y = chartHeight - (CGFloat(summary.totalPointsEarned) / CGFloat(maxPoints)) * chartHeight
                            
                            // Point
                            Circle()
                                .fill(AppTheme.sunnyYellow)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: y)

                            // Line to next point
                            if index < dailySummaries.count - 1 {
                                let nextSummary = dailySummaries[index + 1]
                                let nextX = CGFloat(index + 1) * (chartWidth / CGFloat(dailySummaries.count - 1))
                                let nextY = chartHeight - (CGFloat(nextSummary.totalPointsEarned) / CGFloat(maxPoints)) * chartHeight

                                Path { path in
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: nextX, y: nextY))
                                }
                                .stroke(AppTheme.sunnyYellow, lineWidth: 2)
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
    let dailySummaries: [DailySummary]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)
                .fontWeight(.medium)

            if !dailySummaries.isEmpty {
                let totalLearning = dailySummaries.reduce(0) { $0 + $1.totalLearningSeconds }
                let totalReward = dailySummaries.reduce(0) { $0 + $1.totalRewardSeconds }
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
        
        // Note: In a real preview, we would need a proper Core Data context
        // For now, we'll just show the view without mock data
        
        return HistoricalReportsView(viewModel: viewModel)
            .padding()
    }
}