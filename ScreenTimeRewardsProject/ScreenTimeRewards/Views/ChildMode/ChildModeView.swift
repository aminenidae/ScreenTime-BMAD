import SwiftUI

struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ChildChallengesTabView()
                .environmentObject(viewModel)
                .environmentObject(sessionManager)
        }
        .navigationViewStyle(.stack)
    }
}

struct ChildModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChildModeView()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
