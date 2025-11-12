import SwiftUI

/// ChallengeBuilderTheme now uses the centralized AppTheme for consistency
/// This maintains backward compatibility while ensuring uniform styling
enum ChallengeBuilderTheme {
    static let primary = AppTheme.vibrantTeal
    static let secondary = AppTheme.sunnyYellow

    static var background: Color {
        // Use dynamic color based on current color scheme
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.background(for: scheme))
        })
    }

    static var cardBackground: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.card(for: scheme))
        })
    }

    static var surface: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.card(for: scheme))
        })
    }

    static var inputBackground: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.card(for: scheme))
        })
    }

    static var text: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.textPrimary(for: scheme))
        })
    }

    static var mutedText: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.textSecondary(for: scheme))
        })
    }

    static var border: Color {
        Color(UIColor { traitCollection in
            let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.border(for: scheme))
        })
    }
}
