import SwiftUI

struct ParentModeContainer: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    
    var body: some View {
        #if DEBUG
        let _ = print("[ParentModeContainer] Rendering with sessionManager: \(sessionManager)")
        let _ = print("[ParentModeContainer] Exit button should be visible")
        #endif
        
        ZStack(alignment: .topTrailing) {
            // Main content
            MainTabView(isParentMode: true)

            // Exit button with explicit z-index
            Button {
                sessionManager.exitToSelection()
            } label: {
                Label("Exit Parent Mode", systemImage: "arrow.backward.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(Color.red.opacity(0.85), in: Capsule())
            }
            .padding(.top, 60)  // Increased to avoid navigation bar
            .padding(.trailing, 20)
            .zIndex(999)  // Ensure button is always on top
        }
        .ignoresSafeArea(edges: .top)  // Allow ZStack to extend to top edge
    }
}

struct ParentModeContainer_Previews: PreviewProvider {
    static var previews: some View {
        ParentModeContainer()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
