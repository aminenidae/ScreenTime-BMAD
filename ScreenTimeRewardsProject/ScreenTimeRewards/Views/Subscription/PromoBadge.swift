import SwiftUI

/// The one sticker style for "pick this one" on the paywalls — "Save 58%" on the annual
/// billing option, "Best Value" on the Family tier.
///
/// Both treatments this replaced put text on or near `sunnyYellow`, which is far too light
/// to carry anything: white on it is ~1.5:1, and as a text colour it sat on a near-white
/// card in light mode. Coral with `deepNavy` text is ~4.8:1 and looks identical in light
/// and dark mode, so there is no scheme-specific contrast hole to re-open later.
///
/// Deliberately does not vary with the selected state of whatever it sits in, and is
/// deliberately the same sticker for both uses: one shape the eye learns to read as "this
/// is the better deal" beats two competing accents on one screen.
struct PromoBadge: View {
    let text: String
    var fontSize: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundColor(AppTheme.deepNavy)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppTheme.playfulCoral))
    }
}

#Preview {
    VStack(spacing: 16) {
        PromoBadge(text: "Save 58%")
        PromoBadge(text: "Save 58%", fontSize: 10)
        PromoBadge(text: "Best Value")
    }
    .padding()
}
