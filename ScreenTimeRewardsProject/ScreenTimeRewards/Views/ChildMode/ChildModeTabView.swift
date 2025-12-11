//
//  ChildModeTabView.swift
//  ScreenTimeRewards
//
//  Tab-based navigation for the gamified child mode experience
//

import SwiftUI

struct ChildModeTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @StateObject private var avatarService = AvatarService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedTab: ChildTab = .home

    enum ChildTab: String, CaseIterable {
        case home = "home"
        case avatar = "avatar"
        case collection = "collection"

        var title: String {
            switch self {
            case .home: return "Home"
            case .avatar: return "My Buddy"
            case .collection: return "Collection"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .avatar: return "star.fill"
            case .collection: return "trophy.fill"
            }
        }

        var selectedIcon: String {
            switch self {
            case .home: return "house.fill"
            case .avatar: return "star.fill"
            case .collection: return "trophy.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab - Dashboard
            NavigationView {
                ChildDashboardView()
                    .environmentObject(viewModel)
                    .environmentObject(sessionManager)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label(ChildTab.home.title, systemImage: ChildTab.home.icon)
            }
            .tag(ChildTab.home)

            // Avatar Tab - Buddy showcase and customization
            NavigationView {
                AvatarShowcaseView(avatarService: avatarService)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label(ChildTab.avatar.title, systemImage: ChildTab.avatar.icon)
            }
            .tag(ChildTab.avatar)

            // Collection Tab - Badges and cards
            NavigationView {
                CollectionTabView(avatarService: avatarService)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label(ChildTab.collection.title, systemImage: ChildTab.collection.icon)
            }
            .tag(ChildTab.collection)
        }
        .tint(AppTheme.vibrantTeal)
        .task {
            // Load avatar state when view appears
            let deviceID = DeviceModeManager.shared.deviceID
            await avatarService.loadAvatarState(for: deviceID)
        }
        .onAppear {
            // Customize tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()

            if colorScheme == .dark {
                appearance.backgroundColor = UIColor(AppTheme.deepNavy)
            } else {
                appearance.backgroundColor = UIColor.systemBackground
            }

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Preview

#Preview("Child Mode Tabs") {
    ChildModeTabView()
        .environmentObject(SessionManager.shared)
        .environmentObject(AppUsageViewModel())
}
