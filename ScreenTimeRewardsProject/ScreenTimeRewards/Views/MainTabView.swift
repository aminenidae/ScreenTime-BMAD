import SwiftUI
import FamilyControls

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Receive shared view model
    var isParentMode: Bool = false  // Add parameter to indicate parent mode
    @EnvironmentObject var sessionManager: SessionManager  // Add session manager
    
    var body: some View {
        #if DEBUG
        let _ = print("[MainTabView] Rendering with isParentMode: \(isParentMode)")
        let _ = print("[MainTabView] sessionManager: \(sessionManager)")
        #endif
        
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

                // Settings Tab (Parent Mode only) - Phase 2
                if isParentMode {
                    SettingsTabView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .navigationTitle("Settings")
                }

                // Challenges Tab (Parent Mode only)
                if isParentMode {
                    ParentChallengesTabView()
                        .tabItem {
                            Label("Challenges", systemImage: "trophy.fill")
                        }
                        .navigationTitle("Challenges")
                }

                // Challenges Tab (Child Mode only)
                if !isParentMode {
                    ChildChallengesTabView()
                        .tabItem {
                            Label("Challenges", systemImage: "star.fill")
                        }
                        .navigationTitle("Challenges")
                }
            }
            .environmentObject(viewModel)  // Task 0: Pass shared view model to tabs
            .navigationViewStyle(.stack)
            .navigationBarTitleDisplayMode(.inline)
            // REMOVE Exit button from toolbar (lines 31-42):
            // ToolbarItem removed - Exit Parent Mode button moved to Settings tab
        }
        .navigationViewStyle(.stack)
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { _ in
            viewModel.onPickerSelectionChange()
        }
        .onChange(of: viewModel.isFamilyPickerPresented) { isPresented in
            if !isPresented {
                viewModel.onFamilyPickerDismissed()
            }
        }
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