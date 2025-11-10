import SwiftUI

struct ChallengeBuilderNavigationFooter: View {
    var backTitle: String = "Back"
    var nextTitle: String = "Next"
    var showBackButton: Bool = true
    var isBackEnabled: Bool = true
    var isNextEnabled: Bool = true
    var isLoading: Bool = false
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Divider()
                .background(ChallengeBuilderTheme.border)
                .padding(.horizontal, -16)

            HStack(spacing: 16) {
                if showBackButton {
                    Button(action: onBack) {
                        Text(backTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 100)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isBackEnabled ? ChallengeBuilderTheme.border : ChallengeBuilderTheme.border.opacity(0.4), lineWidth: 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(ChallengeBuilderTheme.inputBackground.opacity(0.6))
                                    )
                            )
                            .foregroundColor(isBackEnabled ? ChallengeBuilderTheme.text : ChallengeBuilderTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isBackEnabled)
                }

                Spacer()

                Button(action: onNext) {
                    ZStack {
                        Text(isLoading ? "" : nextTitle)
                            .font(.system(size: 17, weight: .bold))
                            .frame(minWidth: 120)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 32)
                            .foregroundColor(isNextEnabled ? Color.white : ChallengeBuilderTheme.mutedText)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isNextEnabled ? ChallengeBuilderTheme.primary : ChallengeBuilderTheme.primary.opacity(0.4))
                            )

                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isNextEnabled || isLoading)
            }
        }
        .padding(.vertical, 16)
    }
}
