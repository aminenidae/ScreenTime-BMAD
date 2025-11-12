import SwiftUI
import FamilyControls

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Receive shared view model
    var isParentMode: Bool = false  // Add parameter to indicate parent mode
    @EnvironmentObject var sessionManager: SessionManager  // Add session manager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    var body: some View {
        #if DEBUG
        let _ = print("[MainTabView] Rendering with isParentMode: \(isParentMode)")
        let _ = print("[MainTabView] sessionManager: \(sessionManager)")
        #endif
        
        NavigationView {
            VStack(spacing: 0) {
                TrialBannerView()

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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}
