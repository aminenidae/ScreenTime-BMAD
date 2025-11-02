import SwiftUI
import CoreData

struct RemoteUsageSummaryView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Activity")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if viewModel.categorySummaries.isEmpty && !viewModel.isLoading {
                    EmptyStateView()
                } else {
                    CategoryUsageView(viewModel: viewModel)
                }
                
                // Total Summary
                if !viewModel.categorySummaries.isEmpty {
                    TotalUsageSummary(summaries: viewModel.categorySummaries)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Child's Usage")
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No usage data yet")
                .font(.headline)
            Text("Activity will appear here when your child uses monitored apps")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

private struct CategoryUsageView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel

    var body: some View {
        if viewModel.categorySummaries.isEmpty {
            Text("No usage data yet")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
                .onAppear {
                    #if DEBUG
                    print("[RemoteUsageSummaryView] ⚠️ Category summaries array is EMPTY")
                    print("[RemoteUsageSummaryView] Usage records count: \(viewModel.usageRecords.count)")
                    #endif
                }
        } else {
            ForEach(viewModel.categorySummaries) { summary in
                NavigationLink(destination: CategoryDetailView(summary: summary)) {
                    CategoryUsageCard(summary: summary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .onAppear {
                #if DEBUG
                print("[RemoteUsageSummaryView] ✅ Displaying \(viewModel.categorySummaries.count) category cards")
                for summary in viewModel.categorySummaries {
                    print("[RemoteUsageSummaryView]   Card: \(summary.category) - \(summary.appCount) apps")
                }
                #endif
            }
        }
    }
}

private struct TotalUsageSummary: View {
    let summaries: [CategoryUsageSummary]

    var totalTime: Int {
        summaries.reduce(0) { $0 + $1.totalSeconds }
    }

    var totalPoints: Int {
        summaries.reduce(0) { $0 + $1.totalPoints }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Total Summary")
                .font(.headline)

            HStack(spacing: 40) {
                VStack {
                    Text("Total Screen Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSeconds(totalTime))
                        .font(.title3)
                        .fontWeight(.bold)
                }

                VStack {
                    Text("Total Points")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalPoints)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct RemoteUsageSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()
        
        return RemoteUsageSummaryView(viewModel: viewModel)
            .padding()
    }
}