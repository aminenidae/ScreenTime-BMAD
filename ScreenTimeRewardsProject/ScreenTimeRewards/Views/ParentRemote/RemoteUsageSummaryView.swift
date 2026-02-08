import SwiftUI
import CoreData

struct RemoteUsageSummaryView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Activity")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.horizontal)

                if viewModel.categorySummaries.isEmpty && !viewModel.isLoading {
                    EmptyStateView()
                } else {
                    CategoryUsageView(viewModel: viewModel)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Child's Usage")
    }
}

private struct EmptyStateView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            Text("No usage data yet")
                .font(.headline)
            Text("Activity will appear here when your child uses monitored apps")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

private struct CategoryUsageView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if viewModel.categorySummaries.isEmpty {
            Text("No usage data yet")
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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

struct RemoteUsageSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ParentRemoteViewModel()
        
        return RemoteUsageSummaryView(viewModel: viewModel)
            .padding()
    }
}