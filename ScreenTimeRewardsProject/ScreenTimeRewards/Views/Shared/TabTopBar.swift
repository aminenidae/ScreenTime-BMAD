import SwiftUI
import UIKit

struct TabTopBar: View {
    let title: String
    var style: TabTopBarStyle = .default
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(style.iconColor)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(style.iconBackground)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                    }
                    Spacer()
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(style.titleColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, resolvedTopPadding)
            .padding(.bottom, 12)

            Divider()
                .background(style.dividerColor)
        }
        .frame(maxWidth: .infinity)
        .background(
            style.background
                .ignoresSafeArea(edges: .top)
        )
    }

    private var topSafeAreaInset: CGFloat {
        guard let window = UIApplication.shared.firstKeyWindow else { return 0 }
        return window.safeAreaInsets.top
    }

    private var resolvedTopPadding: CGFloat {
        let inset = topSafeAreaInset
        // Minimize top padding to eliminate unused space
        if inset > 20 {
            // On notched devices, use minimal padding above safe area
            return 4
        } else {
            // On non-notched devices, add slight padding
            return 8
        }
    }
}

struct TabTopBarStyle {
    let background: Color
    let titleColor: Color
    let iconColor: Color
    let iconBackground: Color
    let dividerColor: Color

    static let `default` = TabTopBarStyle(
        background: Color(red: 0.98, green: 0.98, blue: 0.98),
        titleColor: Color(red: 0.13, green: 0.13, blue: 0.13),
        iconColor: Color(red: 0.00, green: 0.35, blue: 0.61),
        iconBackground: Color.white,
        dividerColor: Color.black.opacity(0.06)
    )
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
