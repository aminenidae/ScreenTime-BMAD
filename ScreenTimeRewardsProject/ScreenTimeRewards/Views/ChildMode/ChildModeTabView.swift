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

    var body: some View {
        NavigationView {
            ChildDashboardView()
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Preview

#Preview("Child Mode Tabs") {
    ChildModeTabView()
        .environmentObject(SessionManager.shared)
        .environmentObject(AppUsageViewModel())
}
