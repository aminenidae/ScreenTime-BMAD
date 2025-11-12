import SwiftUI

struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            TabView {
                ChildDashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "house.fill")
                    }
                    .navigationTitle("Dashboard")

                ChildChallengesTabView()
                    .tabItem {
                        Label("Challenges", systemImage: "star.fill")
                    }
                    .navigationTitle("Challenges")
            }
            .environmentObject(viewModel)
            .environmentObject(sessionManager)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Exit") {
                        sessionManager.exitToSelection()
                    }
                    .foregroundColor(AppTheme.error)
                    .font(.headline)
                }
            }
        }
        .navigationViewStyle(.stack)  // Add this to fix iPad layout issue
    }
}

struct ChildModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChildModeView()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
