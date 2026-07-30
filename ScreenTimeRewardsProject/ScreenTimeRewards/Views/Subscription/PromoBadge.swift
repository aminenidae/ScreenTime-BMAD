import SwiftUI

/// The one sticker style for "pick this one" on the paywalls — "Save 58%" on the annual
/// billing option, "Best Value" on the Family tier.
///
/// Teal on gold, and gold means `promoGold` (#FFD700) rather than `sunnyYellow` — the pale
/// brand yellow is what made both of the treatments this replaced illegible in the first
/// place (white on it is ~1.5:1; as a text colour it vanished against the light-mode card).
///
/// The teal is `darkTeal`, NOT `vibrantTeal`. Brand teal on this gold measures ~4.1:1,
/// which is under AA for 11pt text — close enough to look fine on a designer's monitor and
/// fail on a sunlit phone. `darkTeal` reads as the same colour and clears 6.7:1.
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
            .foregroundColor(AppTheme.darkTeal)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppTheme.promoGold))
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
