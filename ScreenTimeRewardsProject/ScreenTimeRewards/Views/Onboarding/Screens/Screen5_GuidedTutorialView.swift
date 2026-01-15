import SwiftUI

/// Screen 5: Guided Tutorial
/// Wrapper that embeds the 18-step GuidedTutorialContainerView
/// Parents interact with the real app UI while tutorial highlights guide them
struct Screen5_GuidedTutorialView: View {
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    /// Called when the tutorial completes successfully
    let onTutorialComplete: () -> Void

    var body: some View {
        GuidedTutorialContainerView(onTutorialComplete: onTutorialComplete)
            .environmentObject(appUsageViewModel)
            .environmentObject(SessionManager.shared)
            .environmentObject(subscriptionManager)
    }
}

// MARK: - Preview

#Preview {
    Screen5_GuidedTutorialView {
        print("Tutorial completed!")
    }
    .environmentObject(AppUsageViewModel())
    .environmentObject(SubscriptionManager.shared)
}
