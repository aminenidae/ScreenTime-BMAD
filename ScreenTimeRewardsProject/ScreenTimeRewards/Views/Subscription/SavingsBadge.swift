import SwiftUI

/// The "Save 58%" promo sticker on the annual billing option.
///
/// Replaces plain `sunnyYellow` text, which sat on a near-white card in light mode and
/// was barely legible. Coral with navy text clears WCAG AA (~4.8:1) and — unlike the old
/// treatment — looks identical in light and dark mode, so there is no scheme-specific
/// contrast hole to re-open later.
///
/// Deliberately does not change with the selected/unselected state of the button it sits
/// in: a discount badge should look like the same sticker wherever it appears.
struct SavingsBadge: View {
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
        SavingsBadge(text: "Save 58%")
        SavingsBadge(text: "Save 58%", fontSize: 10)
        SavingsBadge(text: "Best Value")
    }
    .padding()
}
