import SwiftUI

struct ParentModeContainer: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    
    var body: some View {
        // Removed NavigationView wrapper since MainTabView now has its own NavigationView
        MainTabView(isParentMode: true)
    }
}

struct ParentModeContainer_Previews: PreviewProvider {
    static var previews: some View {
        ParentModeContainer()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}