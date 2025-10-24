import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Receive shared view model
    
    var body: some View {
        TabView {
            RewardsTabView()
                .tabItem {
                    Label("Rewards", systemImage: "gamecontroller.fill")
                }

            LearningTabView()
                .tabItem {
                    Label("Learning", systemImage: "book.fill")
                }
        }
        .environmentObject(viewModel)  // Task 0: Pass shared view model to tabs
        .sheet(isPresented: $viewModel.isCategoryAssignmentPresented) {
            // Task 0: Consolidated sheet based on activePickerContext
            Group {
                if viewModel.currentPickerContext == .learning {
                    CategoryAssignmentView(
                        selection: viewModel.getSelectionForCategoryAssignment(),  // Task 0: Use pending selection when available
                        categoryAssignments: $viewModel.categoryAssignments,
                        rewardPoints: $viewModel.rewardPoints,
                        fixedCategory: .learning,
                        usageTimes: viewModel.getUsageTimes(),
                        onSave: {
                            viewModel.onCategoryAssignmentSave()
                            viewModel.startMonitoring()
                        },
                        onCancel: {
                            viewModel.cancelCategoryAssignment()
                        }
                    )
                } else {
                    CategoryAssignmentView(
                        selection: viewModel.getSelectionForCategoryAssignment(),  // Task 0: Use pending selection when available
                        categoryAssignments: $viewModel.categoryAssignments,
                        rewardPoints: $viewModel.rewardPoints,
                        fixedCategory: .reward,  // Auto-categorize as Reward
                        usageTimes: viewModel.getUsageTimes(),  // Pass usage times for display
                        onSave: {
                            viewModel.onCategoryAssignmentSave()

                            // Immediately shield (block) reward apps
                            viewModel.blockRewardApps()

                            // Start monitoring usage
                            viewModel.startMonitoring()
                        },
                        onCancel: {
                            viewModel.cancelCategoryAssignment()
                        }
                    )
                }
            }
            .environmentObject(viewModel)  // Task M: Pass ViewModel reference to CategoryAssignmentView
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AppUsageViewModel())  // Provide a view model for previews
    }
}