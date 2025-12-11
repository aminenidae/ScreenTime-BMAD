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
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // Swipeable pages
                    TabView(selection: $selectedTab) {
                        ParentDashboardView()
                            .tag(0)

                        LearningTabView()
                            .tag(1)

                        RewardsTabView()
                            .tag(2)

                        SettingsTabView()
                            .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Custom tab indicator at bottom
                    ParentTabIndicator(selectedTab: $selectedTab)
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

            HiddenUsageReportView()
        }
    }

    // MARK: - Child Mode with Bottom Tab Bar
    private var childModeView: some View {
        ZStack {
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

            HiddenUsageReportView()
        }
    }
}

// MARK: - Parent Tab Indicator
struct ParentTabIndicator: View {
    @Binding var selectedTab: Int

    private let tabs: [(String, String)] = [
        ("Dashboard", "DashboardIcon"),
        ("Learning", "LearningIcon"),
        ("Rewards", "RewardsIcon"),
        ("Settings", "SettingsIcon")
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
                        Image(tabs[index].1)
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)

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
