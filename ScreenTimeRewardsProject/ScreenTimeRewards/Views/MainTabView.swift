import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Receive shared view model
    var isParentMode: Bool = false  // Add parameter to indicate parent mode
    @EnvironmentObject var sessionManager: SessionManager  // Add session manager
    
    var body: some View {
        NavigationView {
            TabView {
                RewardsTabView()
                    .tabItem {
                        Label("Rewards", systemImage: "gamecontroller.fill")
                    }
                    .navigationTitle("Rewards")

                LearningTabView()
                    .tabItem {
                        Label("Learning", systemImage: "book.fill")
                    }
                    .navigationTitle("Learning")
            }
            .environmentObject(viewModel)  // Task 0: Pass shared view model to tabs
            .navigationViewStyle(.stack)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Conditionally show Exit Parent Mode button
                if isParentMode {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Exit Parent Mode") {
                            sessionManager.exitToSelection()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
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
            .environmentObject(SessionManager.shared)  // Provide a session manager for previews
    }
}