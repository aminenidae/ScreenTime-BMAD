import SwiftUI

// MARK: - PreferenceKey for collecting target frames

/// PreferenceKey that collects frames of all tutorial target elements
struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - ViewModifier for marking tutorial targets

/// Marks a view as a tutorial target with a specific identifier
/// Captures the view's frame and reports it via PreferenceKey
/// Optionally controls hit testing based on tutorial state
struct TutorialTargetModifier: ViewModifier {
    let identifier: String
    @EnvironmentObject var tutorialManager: TutorialModeManager

    private var isCurrentTarget: Bool {
        tutorialManager.isCurrentTarget(identifier)
    }

    func body(content: Content) -> some View {
        content
            // Capture frame in global coordinate space
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [identifier: geometry.frame(in: .global)]
                        )
                }
            )
            // Visual feedback when this is the current target
            .overlay(
                Group {
                    if isCurrentTarget && tutorialManager.isActive {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.vibrantTeal, lineWidth: 3)
                            .shadow(color: AppTheme.vibrantTeal.opacity(0.5), radius: 8)
                    }
                }
            )
    }
}

// MARK: - View Extension

extension View {
    /// Marks this view as a tutorial target with the given identifier
    /// - Parameter identifier: Unique string to identify this target (e.g., "tab_learning", "add_learning_apps")
    /// - Note: Empty identifiers are ignored (no modifier applied)
    @ViewBuilder
    func tutorialTarget(_ identifier: String) -> some View {
        if identifier.isEmpty {
            self
        } else {
            self.modifier(TutorialTargetModifier(identifier: identifier))
        }
    }
}

// MARK: - Hit Testing Control Modifier

/// Separate modifier for controlling hit testing during tutorial
/// Applied at a higher level to prevent interaction with non-target elements
struct TutorialHitTestModifier: ViewModifier {
    let identifier: String
    @EnvironmentObject var tutorialManager: TutorialModeManager

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(tutorialManager.shouldAllowInteraction(for: identifier))
    }
}

extension View {
    /// Controls whether this view allows hit testing during tutorial mode
    /// - Parameter identifier: The tutorial target identifier for this view
    func tutorialHitTest(_ identifier: String) -> some View {
        self.modifier(TutorialHitTestModifier(identifier: identifier))
    }
}
