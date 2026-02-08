import SwiftUI

/// Position of the callout relative to the target
enum CalloutPosition {
    case above
    case below
}

/// Arrow/pointer shape for the callout
struct CalloutArrow: Shape {
    let direction: CalloutPosition

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch direction {
        case .above:
            // Arrow pointing down
            path.move(to: CGPoint(x: rect.midX - 10, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.minY))
            path.closeSubpath()
        case .below:
            // Arrow pointing up
            path.move(to: CGPoint(x: rect.midX - 10, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}

/// Instruction tooltip/callout that appears near the tutorial target
struct TutorialCalloutView: View {
    let step: TutorialModeManager.TutorialStep
    let targetFrame: CGRect
    let screenSize: CGSize

    @Environment(\.colorScheme) var colorScheme

    // Calculate callout position based on target location
    private var position: CalloutPosition {
        // If target is in top half, show callout below; otherwise above
        let targetMidY = targetFrame.midY
        return targetMidY < screenSize.height * 0.5 ? .below : .above
    }

    // Calculate the callout's center X position
    private var calloutCenterX: CGFloat {
        // Keep callout horizontally centered on target, but clamp to screen bounds
        let margin: CGFloat = 20
        let calloutWidth: CGFloat = min(320, screenSize.width - margin * 2)

        var centerX = targetFrame.midX

        // Clamp to screen bounds
        let minX = margin + calloutWidth / 2
        let maxX = screenSize.width - margin - calloutWidth / 2

        centerX = max(minX, min(maxX, centerX))

        return centerX
    }

    // Calculate the callout's Y position
    private var calloutY: CGFloat {
        let verticalOffset: CGFloat = 20  // Space between target and callout

        switch position {
        case .above:
            return targetFrame.minY - verticalOffset - 80  // Approximate callout height
        case .below:
            return targetFrame.maxY + verticalOffset + 60
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if position == .below {
                arrowView
            }

            calloutContent
                .frame(maxWidth: min(320, screenSize.width - 40))

            if position == .above {
                arrowView
            }
        }
        .position(x: calloutCenterX, y: calloutY)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: targetFrame)
    }

    private var arrowView: some View {
        CalloutArrow(direction: position)
            .fill(AppTheme.card(for: colorScheme))
            .frame(width: 24, height: 12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: position == .below ? -1 : 1)
    }

    private var calloutContent: some View {
        // Instruction text only (no step numbers to avoid overwhelming users)
        Text(step.instructionText)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
            )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        TutorialCalloutView(
            step: .tapLearningTab,
            targetFrame: CGRect(x: 100, y: 600, width: 80, height: 60),
            screenSize: CGSize(width: 390, height: 844)
        )
    }
}
