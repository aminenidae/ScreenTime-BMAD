//
//  ParentTabView.swift
//  ScreenTimeRewards
//
//  Tab bar container for parent device mode.
//  Provides Dashboard and Settings tabs.
//

import SwiftUI
import UIKit

/// Main tab view for parent device mode
struct ParentTabView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var viewModel = ParentRemoteViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            ParentRemoteDashboardView()
                .environmentObject(viewModel)
                .environmentObject(subscriptionManager)
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(0)

            // Settings Tab
            ParentSettingsView()
                .environmentObject(viewModel)
                .environmentObject(subscriptionManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .tint(AppTheme.vibrantTeal)
        .onAppear {
            // Configure tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Preview

#Preview("Parent Tab View") {
    ParentTabView()
        .environmentObject(SubscriptionManager.shared)
}
