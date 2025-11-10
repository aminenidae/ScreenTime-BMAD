import SwiftUI

enum ChallengeBuilderTheme {
    static let primary = Color(hex: "#007AFF")
    static let secondary = Color(hex: "#34C759")
    static let background = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#000000") : UIColor(hex: "#F2F2F7")
    })
    static let cardBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#1C1C1E") : UIColor.white
    })
    static let surface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#1C1C1E") : UIColor.white
    })
    static let inputBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#2C2C2E") : UIColor(hex: "#F2F2F7")
    })
    static let text = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#F2F2F7") : UIColor(hex: "#1C1C1E")
    })
    static let mutedText = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#8E8E93") : UIColor(hex: "#6E6E73")
    })
    static let border = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#3A3A3C") : UIColor(hex: "#E5E5EA")
    })
}
