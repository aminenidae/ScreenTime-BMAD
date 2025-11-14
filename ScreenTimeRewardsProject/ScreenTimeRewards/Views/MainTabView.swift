import SwiftUI
import FamilyControls

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    var isParentMode: Bool = false
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @AppStorage("hasCompletedChildOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = 0

    var body: some View {
        #if DEBUG
        let _ = print("[MainTabView] Rendering with isParentMode: \(isParentMode)")
        let _ = print("[MainTabView] sessionManager: \(sessionManager)")
        #endif

        if isParentMode {
            parentModeView
        } else {
            childModeView
        }
    }

    // MARK: - Parent Mode with Swipe Navigation
    private var parentModeView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom tab indicator
                ParentTabIndicator(selectedTab: $selectedTab)

                // Swipeable pages
                TabView(selection: $selectedTab) {
                    LearningTabView()
                        .tag(0)

                    RewardsTabView()
                        .tag(1)

                    ParentChallengesTabView()
                        .tag(2)

                    SettingsTabView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environmentObject(viewModel)
            .navigationViewStyle(.stack)
            .navigationBarHidden(true)
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

    // MARK: - Child Mode with Bottom Tab Bar
    private var childModeView: some View {
        NavigationView {
            VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environmentObject(viewModel)
            .navigationViewStyle(.stack)
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Parent Tab Indicator
struct ParentTabIndicator: View {
    @Binding var selectedTab: Int

    private let tabs: [(String, String)] = [
        ("Learning", "book.fill"),
        ("Rewards", "gamecontroller.fill"),
        ("Challenges", "trophy.fill"),
        ("Settings", "gearshape.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: tabs[index].1)
                            .font(.system(size: 20, weight: selectedTab == index ? .bold : .medium))
                            .foregroundColor(selectedTab == index ? AppTheme.vibrantTeal : .secondary)

                        Text(tabs[index].0)
                            .font(.system(size: 12, weight: selectedTab == index ? .semibold : .regular))
                            .foregroundColor(selectedTab == index ? AppTheme.vibrantTeal : .secondary)

                        // Active indicator
                        RoundedRectangle(cornerRadius: 2)
                            .fill(selectedTab == index ? AppTheme.vibrantTeal : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }
}
