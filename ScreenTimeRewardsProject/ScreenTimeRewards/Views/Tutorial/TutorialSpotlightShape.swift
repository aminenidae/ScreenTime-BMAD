import SwiftUI

/// Custom shape that fills the entire rect except for a spotlight cutout
/// Uses even-odd fill rule to create a hole (compatible with iOS 16+)
struct TutorialSpotlightShape: Shape {
    let targetFrame: CGRect
    let cornerRadius: CGFloat
    let padding: CGFloat

    init(targetFrame: CGRect, cornerRadius: CGFloat = 12, padding: CGFloat = 8) {
        self.targetFrame = targetFrame
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Add the full rectangle (outer boundary)
        path.addRect(rect)

        // If we have a valid target, add the spotlight hole
        if targetFrame != .zero && targetFrame.width > 0 && targetFrame.height > 0 {
            let spotlightRect = targetFrame.insetBy(dx: -padding, dy: -padding)
            // Add rounded rectangle for the spotlight hole
            path.addRoundedRect(in: spotlightRect, cornerSize: CGSize(width: cornerRadius + padding / 2, height: cornerRadius + padding / 2))
        }

        return path
    }
}

/// View-based spotlight overlay that works on iOS 16+
/// Uses overlay and mask to create the spotlight effect
struct TutorialSpotlightOverlay: View {
    let targetFrame: CGRect
    let cornerRadius: CGFloat
    let padding: CGFloat
    let dimColor: Color

    init(targetFrame: CGRect, cornerRadius: CGFloat = 12, padding: CGFloat = 12, dimColor: Color = Color.black.opacity(0.75)) {
        self.targetFrame = targetFrame
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.dimColor = dimColor
    }

    var body: some View {
        GeometryReader { geometry in
            dimColor
                .mask(
                    // Use even-odd fill rule by adding shapes
                    TutorialSpotlightShape(
                        targetFrame: targetFrame,
                        cornerRadius: cornerRadius,
                        padding: padding
                    )
                    .fill(style: FillStyle(eoFill: true))
                )
                .allowsHitTesting(true)
                .onTapGesture {
                    // Absorb taps on dimmed area
                }
        }
    }
}

/// Animatable version of the spotlight shape for smooth transitions
struct AnimatableTutorialSpotlight: Shape {
    var targetFrame: CGRect
    let cornerRadius: CGFloat
    let padding: CGFloat

    init(targetFrame: CGRect, cornerRadius: CGFloat = 12, padding: CGFloat = 8) {
        self.targetFrame = targetFrame
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(targetFrame.origin.x, targetFrame.origin.y),
                AnimatablePair(targetFrame.width, targetFrame.height)
            )
        }
        set {
            targetFrame = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Add the full rectangle (outer boundary)
        path.addRect(rect)

        // Add the spotlight hole
        if targetFrame != .zero && targetFrame.width > 0 && targetFrame.height > 0 {
            let spotlightRect = targetFrame.insetBy(dx: -padding, dy: -padding)
            path.addRoundedRect(in: spotlightRect, cornerSize: CGSize(width: cornerRadius + padding / 2, height: cornerRadius + padding / 2))
        }

        return path
    }
}

/// A pulsing ring effect around the spotlight target
struct TutorialSpotlightRing: View {
    let frame: CGRect
    let cornerRadius: CGFloat

    @State private var isAnimating = false

    init(frame: CGRect, cornerRadius: CGFloat = 12) {
        self.frame = frame
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        if frame != .zero && frame.width > 0 {
            ZStack {
                // Outer pulsing ring
                RoundedRectangle(cornerRadius: cornerRadius + 12)
                    .stroke(AppTheme.vibrantTeal.opacity(isAnimating ? 0 : 0.6), lineWidth: 3)
                    .frame(width: frame.width + 24, height: frame.height + 24)
                    .scaleEffect(isAnimating ? 1.15 : 1.0)

                // Inner static ring
                RoundedRectangle(cornerRadius: cornerRadius + 8)
                    .stroke(AppTheme.vibrantTeal, lineWidth: 2)
                    .frame(width: frame.width + 16, height: frame.height + 16)
            }
            .position(x: frame.midX, y: frame.midY)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
        }
    }
}
