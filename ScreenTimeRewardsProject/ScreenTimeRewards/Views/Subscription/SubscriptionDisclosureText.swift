import SwiftUI

/// The subscription fine print shown at the point of purchase: trial terms, Apple's
/// required renewal disclosure, and the Terms / Privacy links.
///
/// This is the single source of that text. It was previously hand-rolled in four paywalls
/// (SubscriptionPaywallView, ChildSubscriptionView, ParentPaywallView and the onboarding
/// Screen6_TrialPaywallView) and they drifted: three stated no trial length or post-trial
/// price at all while their CTA promised a 14-day trial, and an earlier version of this
/// very file — referenced by nothing but its own preview — carried a *fifth* wording.
/// Apple guideline 3.1.2 wants duration, price-after-trial and renewal terms together at
/// the point of purchase, so there needs to be exactly one copy.
///
/// Styling is parameterised because the paywalls legitimately differ (branded teal links
/// on the parent and onboarding screens, system secondary elsewhere). The *text* is not
/// parameterised — that is the entire point of this type.
struct SubscriptionDisclosureText: View {
    /// Trial length and what is charged when it ends, e.g. "Free for 14 days, then
    /// $49.99/year." Pass nil while pricing is still loading, so the line is omitted
    /// rather than rendering a blank amount.
    var trialTerms: String? = nil

    var textColor: Color = .secondary
    var linkColor: Color = .blue
    var fontSize: CGFloat = 11
    var linkSpacing: CGFloat = 16
    var separator: String = "•"

    static let termsURL = URL(string: "https://i6dev.ca/ticlock/terms.html")!
    static let privacyURL = URL(string: "https://i6dev.ca/ticlock/privacy.html")!

    /// Apple's required renewal disclosure. Exposed separately so a paywall that composes
    /// its own paragraph (the onboarding screen stitches it onto the trial line) still
    /// uses this exact wording instead of keeping a private copy.
    static var renewalDisclosure: String {
        String(localized: "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions by going to your account settings after purchase.")
    }

    var body: some View {
        VStack(spacing: 8) {
            if let trialTerms {
                Text(trialTerms)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(textColor)
            }

            Text(Self.renewalDisclosure)
                .font(.system(size: fontSize))
                .foregroundColor(textColor)

            HStack(spacing: linkSpacing) {
                Link("Terms of Service", destination: Self.termsURL)
                Text(separator)
                    .foregroundColor(textColor)
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            .font(.system(size: fontSize))
            .foregroundColor(linkColor)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    SubscriptionDisclosureText(trialTerms: "Free for 14 days, then $49.99/year.")
        .padding()
}
