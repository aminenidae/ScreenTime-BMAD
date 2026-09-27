import SwiftUI

/// The three reassurance lines for the Screen Time permission ask.
///
/// Shared by the priming screen and the recovery screen so the wording can't drift
/// between them. On recovery they sit below the button as a reminder: a parent who
/// declined may simply not have read them the first time.
struct PermissionSafetyLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SafetyLine(
                icon: "checkmark.shield.fill",
                lead: String(localized: "Safe"),
                rest: String(localized: "it's Apple's own Screen Time switch, not ours.")
            )
            SafetyLine(
                icon: "eye.slash.fill",
                lead: String(localized: "Private"),
                rest: String(localized: "never your messages, photos, browsing or location.")
            )
            SafetyLine(
                icon: "arrow.uturn.backward",
                lead: String(localized: "Reversible"),
                rest: String(localized: "turn it off any time in Settings.")
            )
        }
    }
}

/// A bold lead word carries the reassurance on its own for a parent who only skims.
struct SafetyLine: View {
    let icon: String
    let lead: String
    let rest: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.accentText(for: colorScheme))
                .frame(width: 20)
            (
                Text(lead).font(.system(size: 15, weight: .bold))
                + Text(" — ").font(.system(size: 15))
                + Text(rest).font(.system(size: 15))
            )
            .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    PermissionSafetyLines()
        .padding(30)
}
