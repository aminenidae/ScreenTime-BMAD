import SwiftUI

/// Provides responsive layout calculations for onboarding cards across different device sizes and orientations.
struct ResponsiveCardLayout {
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?

    init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
        self.horizontalSizeClass = horizontal
        self.verticalSizeClass = vertical
    }

    // MARK: - Device Detection

    var isCompact: Bool { horizontalSizeClass == .compact }
    var isRegular: Bool { horizontalSizeClass == .regular }
    var isLandscape: Bool { verticalSizeClass == .compact }
    var isIpad: Bool { isRegular && verticalSizeClass == .regular }

    // MARK: - Hero Card Sizing

    /// Height for hero/banner cards (Screen 1, Welcome)
    var heroCardHeight: CGFloat {
        if isIpad {
            return 400
        } else if isLandscape {
            return 200
        } else {
            return 280
        }
    }

    /// Max width constraint for hero cards on iPad
    var heroCardMaxWidth: CGFloat {
        isRegular ? 600 : .infinity
    }

    // MARK: - Horizontal Scroll Card Sizing

    /// Width for cards in horizontal scroll views (Screen 2, 6, 7)
    var scrollCardWidth: CGFloat {
        if isIpad {
            return 340
        } else if isLandscape {
            return 240
        } else {
            return 280
        }
    }

    /// Height for cards in horizontal scroll views (maintains 280:180 aspect ratio)
    var scrollCardHeight: CGFloat {
        scrollCardWidth * (180.0 / 280.0)
    }

    // MARK: - Full-Width Card Sizing

    /// Height for full-width stacked cards (Screen 3, Device Selection)
    var fullWidthCardHeight: CGFloat {
        if isIpad {
            return 200
        } else if isLandscape {
            return 140
        } else {
            return 160
        }
    }

    /// Aspect ratio for full-width cards
    var fullWidthAspectRatio: CGFloat { 2.2 }

    // MARK: - Device Selection Card Sizing

    /// Height for device selection cards
    var deviceCardHeight: CGFloat {
        if isIpad {
            return 220
        } else if isLandscape {
            return 140
        } else {
            return 180
        }
    }

    // MARK: - Benefit Card Sizing (Screen 6)

    var benefitCardWidth: CGFloat {
        if isIpad {
            return 300
        } else if isLandscape {
            return 220
        } else {
            return 260
        }
    }

    var benefitCardHeight: CGFloat {
        benefitCardWidth * (150.0 / 260.0)
    }

    // MARK: - iPad Grid/Side-by-Side Card Sizing

    /// Explicit width for cards in iPad grid or side-by-side layouts
    /// This prevents images from expanding unbounded when using flexible layouts
    var ipadGridCardWidth: CGFloat {
        if isIpad && isLandscape {
            return 320
        } else if isIpad {
            return 300
        } else {
            return scrollCardWidth // fallback for iPhone
        }
    }

    /// Height for cards in iPad grid layouts (maintains aspect ratio)
    var ipadGridCardHeight: CGFloat {
        ipadGridCardWidth * (180.0 / 280.0)
    }

    // MARK: - Layout Mode

    /// Whether to use grid layout instead of horizontal scroll (iPad)
    var useGridLayout: Bool { isRegular }

    /// Whether to use side-by-side layout for paired cards (iPad)
    var useSideBySideLayout: Bool { isRegular }

    /// Number of columns for grid layout
    var gridColumns: Int {
        if isIpad && isLandscape {
            return 3
        } else if isRegular {
            return 2
        } else {
            return 1
        }
    }

    // MARK: - Spacing

    var cardSpacing: CGFloat {
        isRegular ? 20 : 12
    }

    var horizontalPadding: CGFloat {
        isRegular ? 32 : 16
    }
}

// MARK: - Aspect Ratio Constants

enum CardAspectRatio {
    /// Hero/banner cards (660/1170)
    static let hero: CGFloat = 1.77

    /// Horizontal scroll cards (280/180)
    static let horizontal: CGFloat = 1.56

    /// Full-width stacked cards (~160/350)
    static let fullWidth: CGFloat = 2.2

    /// Device selection cards
    static let deviceSelection: CGFloat = 1.95
}

// MARK: - Environment Key

private struct ResponsiveLayoutKey: EnvironmentKey {
    static let defaultValue = ResponsiveCardLayout(horizontal: .compact, vertical: .regular)
}

extension EnvironmentValues {
    var responsiveLayout: ResponsiveCardLayout {
        get { self[ResponsiveLayoutKey.self] }
        set { self[ResponsiveLayoutKey.self] = newValue }
    }
}

// MARK: - View Modifier for Responsive Layout

struct ResponsiveLayoutModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    func body(content: Content) -> some View {
        content
            .environment(\.responsiveLayout, ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass))
    }
}

extension View {
    func withResponsiveLayout() -> some View {
        modifier(ResponsiveLayoutModifier())
    }
}

// MARK: - Responsive Image Card View

/// A responsive image card that adapts to different screen sizes and orientations.
struct ResponsiveImageCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    var stepNumber: String? = nil
    var isSelected: Bool = false
    var showCheckmark: Bool = false
    var cardType: CardType = .horizontal
    var action: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    enum CardType {
        case hero
        case horizontal
        case fullWidth
        case deviceSelection
        case benefit
    }

    private let tealColor = Color(red: 31/255, green: 134/255, blue: 111/255)

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    private var cardSize: CGSize {
        switch cardType {
        case .hero:
            return CGSize(width: 0, height: layout.heroCardHeight) // Width fills container
        case .horizontal:
            return CGSize(width: layout.scrollCardWidth, height: layout.scrollCardHeight)
        case .fullWidth:
            return CGSize(width: 0, height: layout.fullWidthCardHeight) // Width fills container
        case .deviceSelection:
            return CGSize(width: 0, height: layout.deviceCardHeight) // Width fills container
        case .benefit:
            return CGSize(width: layout.benefitCardWidth, height: layout.benefitCardHeight)
        }
    }

    var body: some View {
        Button(action: { action?() }) {
            ZStack(alignment: .bottomLeading) {
                // Background image
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: cardSize.width > 0 ? cardSize.width : nil,
                        height: cardSize.height
                    )
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    if let num = stepNumber {
                        Text(num)
                            .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(title)
                        .font(.system(size: layout.isRegular ? 22 : 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: layout.isRegular ? 14 : 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(layout.isRegular ? 20 : 12)

                // Selected checkmark
                if showCheckmark && isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(tealColor)
                                    .frame(width: 28, height: 28)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(
                width: cardSize.width > 0 ? cardSize.width : nil,
                height: cardSize.height
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? tealColor : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? tealColor.opacity(0.2) : Color.black.opacity(0.08),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: isSelected ? 4 : 2
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Adaptive Card Container

/// A container that switches between horizontal scroll (iPhone) and grid (iPad) layouts.
struct AdaptiveCardContainer<Content: View, Item: Identifiable>: View {
    let items: [Item]
    let content: (Item) -> Content

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    var body: some View {
        if layout.useGridLayout {
            // iPad: Grid layout
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: layout.cardSpacing), count: layout.gridColumns),
                spacing: layout.cardSpacing
            ) {
                ForEach(items) { item in
                    content(item)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
        } else {
            // iPhone: Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.cardSpacing) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 8)
            }
        }
    }
}
