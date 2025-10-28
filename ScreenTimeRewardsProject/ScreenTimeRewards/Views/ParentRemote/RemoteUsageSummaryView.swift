import SwiftUI
import CoreData

struct RemoteUsageSummaryView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Summary")
                .font(.headline)
            
            if viewModel.usageRecords.isEmpty && !viewModel.isLoading {
                EmptyStateView()
            } else {
                UsageStatsView(viewModel: viewModel)
                RecentActivityView(viewModel: viewModel)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No usage data available")
                .foregroundColor(.gray)
            Text("Check back later when your child has used apps")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

private struct UsageStatsView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                StatCard(
                    title: "Learning Time",
                    value: formatTime(totalLearningSeconds),
                    icon: "book",
                    color: .blue
                )
                
                StatCard(
                    title: "Reward Time",
                    value: formatTime(totalRewardSeconds),
                    icon: "gamecontroller",
                    color: .green
                )
            }
            
            HStack {
                StatCard(
                    title: "Learning Points",
                    value: String(totalLearningPoints),
                    icon: "star",
                    color: .orange
                )
                
                StatCard(
                    title: "Reward Points",
                    value: String(totalRewardPoints),
                    icon: "gift",
                    color: .purple
                )
            }
        }
    }
    
    private var totalLearningSeconds: Int32 {
        viewModel.dailySummaries.reduce(0) { $0 + $1.totalLearningSeconds }
    }
    
    private var totalRewardSeconds: Int32 {
        viewModel.dailySummaries.reduce(0) { $0 + $1.totalRewardSeconds }
    }
    
    private var totalLearningPoints: Int32 {
        viewModel.dailySummaries.reduce(0) { $0 + $1.totalPointsEarned }
    }
    
    private var totalRewardPoints: Int32 {
        // This would need to be calculated differently based on your data model
        // For now, we'll use a placeholder
        return 0
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

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(Circle())
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}

private struct RecentActivityView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.medium)
            
            if viewModel.usageRecords.isEmpty {
                Text("No recent activity")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(viewModel.usageRecords.prefix(5), id: \.recordID) { record in
                    ActivityRow(record: record)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let record: UsageRecord
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName ?? "Unknown App")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let sessionStart = record.sessionStart,
                   let sessionEnd = record.sessionEnd {
                    Text(formatDateRange(start: sessionStart, end: sessionEnd))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(record.totalSeconds))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if record.earnedPoints > 0 {
                    Text("\(record.earnedPoints) pts")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func formatDuration(_ seconds: Int32) -> String {
        let minutes = seconds / 60
        if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
}

struct RemoteUsageSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()
        
        // Note: In a real preview, we would need a proper Core Data context
        // For now, we'll just show the view without mock data
        
        return RemoteUsageSummaryView(viewModel: viewModel)
            .padding()
    }
}