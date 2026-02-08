import SwiftUI

/// Reusable component for displaying App Store subscription disclosure text
/// Complies with Schedule 2 requirements for subscription apps
struct SubscriptionDisclosureText: View {
    let price: String
    let billingPeriod: String = "month"
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple Account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged \(price) for renewal within 24 hours prior to the end of the current period. Any unused portion of a free trial will be forfeited when you purchase a subscription.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 8) {
                Text("Subscriptions may be managed and auto-renewal turned off in")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Link("Account Settings", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }
            .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    SubscriptionDisclosureText(price: "$59.99")
        .padding()
}
