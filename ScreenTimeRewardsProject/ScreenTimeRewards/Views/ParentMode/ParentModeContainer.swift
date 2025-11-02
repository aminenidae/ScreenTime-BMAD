import SwiftUI

struct ParentModeContainer: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    
    var body: some View {
        MainTabView(isParentMode: true)
            .overlay(alignment: .topTrailing) {
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
                .padding(.top, 20)
                .padding(.trailing, 20)
            }
    }
}

struct ParentModeContainer_Previews: PreviewProvider {
    static var previews: some View {
        ParentModeContainer()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
