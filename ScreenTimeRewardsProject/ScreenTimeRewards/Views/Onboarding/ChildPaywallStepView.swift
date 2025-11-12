import SwiftUI

struct ChildPaywallStepView: View {
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SubscriptionPaywallView(isOnboarding: true, onComplete: onComplete)

            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .padding(12)
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(12)
            }
            .padding()
        }
    }
}
