import SwiftUI

/// Centralized design system for the entire app
struct AppTheme {

    // MARK: - Brand Colors

    /// Vibrant Teal - Primary accent color (#00A6A6)
    static let vibrantTeal = Color(red: 0, green: 0.651, blue: 0.651)

    /// Sunny Yellow - Secondary accent, warnings, highlights (#FFD166)
    static let sunnyYellow = Color(red: 1, green: 0.820, blue: 0.400)

    /// Playful Coral - Rewards, achievements, excitement (#EF476F)
    static let playfulCoral = Color(red: 0.937, green: 0.278, blue: 0.435)

    /// Deep Navy - Dark background (#073B4C)
    static let deepNavy = Color(red: 0.027, green: 0.231, blue: 0.298)

    /// Light Cream - Light background (#F7F7F2)
    static let lightCream = Color(red: 0.969, green: 0.969, blue: 0.949)

    // MARK: - Learning Theme Colors (from hourglass icon)

    /// Learning Peach - Soft peachy-coral accent (#FFB4A3)
    static let learningPeach = Color(red: 1.0, green: 0.706, blue: 0.639)

    /// Learning Peach Light - Lighter peach for backgrounds (#FFC9B9)
    static let learningPeachLight = Color(red: 1.0, green: 0.788, blue: 0.725)

    /// Learning Peach Soft - Very light peach for cards (#FFE5DC)
    static let learningPeachSoft = Color(red: 1.0, green: 0.898, blue: 0.863)

    /// Learning Cream - Warm cream tone (#FFF4ED)
    static let learningCream = Color(red: 1.0, green: 0.957, blue: 0.929)

    // MARK: - Contextual Colors

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? deepNavy : lightCream
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.082, green: 0.294, blue: 0.361) : .white
    }

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? lightCream : deepNavy
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? lightCream.opacity(0.7) : deepNavy.opacity(0.7)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }

    static func progressTrack(for scheme: ColorScheme) -> Color {
        scheme == .dark ? deepNavy.opacity(0.5) : lightCream
    }

    static func inputBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.082, green: 0.294, blue: 0.361).opacity(0.5) : Color.white.opacity(0.8)
    }

    // MARK: - Semantic Colors

    /// Primary action color (buttons, links, interactive elements)
    static let primary = vibrantTeal

    /// Success states (completed challenges, unlocked rewards)
    static let success = vibrantTeal

    /// Warning states (low progress, expiring challenges)
    static let warning = sunnyYellow

    /// Error/destructive states (delete, cancel)
    static let error = playfulCoral

    /// Rewards and achievements
    static let reward = playfulCoral

    /// Learning and educational content
    static let learning = vibrantTeal

    // MARK: - Gamification Colors

    /// Evolution stage colors
    struct Evolution {
        static let stage1 = sunnyYellow      // Starter
        static let stage2 = vibrantTeal      // Growing
        static let stage3 = playfulCoral     // Advanced
        static let stage4 = Color.orange     // Max level

        static func color(for level: Int) -> Color {
            switch level {
            case 1: return stage1
            case 2: return stage2
            case 3: return stage3
            case 4: return stage4
            default: return stage1
            }
        }
    }

    /// Rarity tier colors
    struct Rarity {
        static let common = Color.gray
        static let uncommon = Color.green
        static let rare = Color.blue
        static let epic = Color.purple
        static let legendary = Color.orange

        /// Badge rarity colors (slightly different palette)
        static let bronze = Color(hex: "CD7F32")
        static let silver = Color(hex: "C0C0C0")
        static let gold = Color(hex: "FFD700")
        static let platinum = Color(hex: "E5E4E2")
        static let diamond = Color(hex: "B9F2FF")
    }

    /// Avatar mood colors
    struct Mood {
        static let happy = sunnyYellow
        static let excited = playfulCoral
        static let sleepy = Color.purple.opacity(0.7)
        static let neutral = Color.gray
        static let sad = Color.blue
        static let celebrating = Color.orange
    }

    // MARK: - Typography

    struct Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold)
        static let title1 = Font.system(size: 26, weight: .bold)
        static let title2 = Font.system(size: 22, weight: .bold)
        static let title3 = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 18, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let callout = Font.system(size: 15, weight: .regular)
        static let subheadline = Font.system(size: 14, weight: .regular)
        static let footnote = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let caption2 = Font.system(size: 11, weight: .regular)
    }

    // MARK: - Spacing

    struct Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let regular: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let huge: CGFloat = 48
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        static let xxLarge: CGFloat = 24
        static let round: CGFloat = 999
    }

    // MARK: - Shadows

    static func cardShadow(for scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.3 : 0.05)
    }

    struct Shadow {
        static let small = (color: Color.black.opacity(0.05), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
        static let medium = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let large = (color: Color.black.opacity(0.15), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
    }
}

// MARK: - View Extensions for Easy Access

extension View {
    func appBackground(_ scheme: ColorScheme) -> some View {
        self.background(AppTheme.background(for: scheme).ignoresSafeArea())
    }

    func appCard(_ scheme: ColorScheme) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: scheme))
                .shadow(
                    color: AppTheme.Shadow.small.color,
                    radius: AppTheme.Shadow.small.radius,
                    x: AppTheme.Shadow.small.x,
                    y: AppTheme.Shadow.small.y
                )
        )
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - ChallengeBuilderTheme Compatibility
/// Backward compatibility for components that referenced ChallengeBuilderTheme
enum ChallengeBuilderTheme {
    static let primary = AppTheme.vibrantTeal
    static let secondary = AppTheme.sunnyYellow

    static var background: Color {
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
