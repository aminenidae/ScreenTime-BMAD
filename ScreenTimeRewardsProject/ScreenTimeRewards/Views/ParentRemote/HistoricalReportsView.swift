import SwiftUI
import CoreData

struct HistoricalReportsView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @State private var selectedDateRange: DateRange = .week
    
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
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct EmptyReportsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No historical data")
                .foregroundColor(.gray)
            Text("Reports will appear here after your child uses apps")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

private struct DailySummaryCard: View {
    let summary: DailySummary
    let date: Date
    
    var body: some View {
        VStack(spacing: 12) {
            Text(formatDate(date))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                StatItem(
                    title: "Learning",
                    value: formatTime(summary.totalLearningSeconds),
                    icon: "book",
                    color: .blue
                )
                
                StatItem(
                    title: "Reward",
                    value: formatTime(summary.totalRewardSeconds),
                    icon: "gamecontroller",
                    color: .green
                )
                
                StatItem(
                    title: "Points",
                    value: String(summary.totalPointsEarned),
                    icon: "star",
                    color: .orange
                )
            }
        }
        .frame(width: 120)
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 2)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func formatTime(_ seconds: Int32) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
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
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct WeeklyTrendChart: View {
    let dailySummaries: [DailySummary]
    
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
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    }
                    
                    // Data points and lines
                    if !dailySummaries.isEmpty {
                        let maxPoints = dailySummaries.map { $0.totalPointsEarned }.max() ?? 1
                        
                        ForEach(Array(dailySummaries.enumerated()), id: \.element.summaryID) { index, summary in
                            let x = CGFloat(index) * (chartWidth / CGFloat(dailySummaries.count - 1))
                            let y = chartHeight - (CGFloat(summary.totalPointsEarned) / CGFloat(maxPoints)) * chartHeight
                            
                            // Point
                            Circle()
                                .fill(Color.blue)
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
                                .stroke(Color.blue, lineWidth: 2)
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
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                                .frame(width: CGFloat(totalLearning) / CGFloat(totalTime) * 200, height: 20)
                            
                            Text("Learning")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                                .frame(width: CGFloat(totalReward) / CGFloat(totalTime) * 200, height: 20)
                            
                            Text("Reward")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        StatBadge(
                            title: "Learning",
                            value: formatTime(totalLearning),
                            color: .blue
                        )
                        
                        StatBadge(
                            title: "Reward",
                            value: formatTime(totalReward),
                            color: .green
                        )
                    }
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Int32) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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