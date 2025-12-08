# HTML to SwiftUI Conversion Rules

## Prepare the Inputs
- Audit the HTML and CSS to understand layout structure, component hierarchy, typography scale, color palette, and interactive behaviors before writing SwiftUI.
- Extract design tokens (colors, spacing, typography, corner radii, shadows) into a shared constants file or asset catalog for reuse across views.
- Export raster and vector assets at @1x/@2x/@3x or convert to SF Symbols where possible; keep original SVGs for future tweaks.
- Identify reusable components in the markup (cards, headers, list items) and plan 1:1 SwiftUI view structs rather than copy-pasting markup.

## translate Layout & Semantics
- Favor SwiftUI stacks (`VStack`, `HStack`, `ZStack`, `LazyVGrid`) to mirror flexbox/grid layout; keep hierarchy shallow and compose small views.
- Replace global HTML containers with `ScrollView`, `NavigationStack`, or `List` depending on intent; choose `Lazy` variants for large content.
- Map CSS spacing to `padding`, `spacing`, and `frame` modifiers; centralize magic numbers into constants for consistency.
- Use `GeometryReader` sparingly; lean on SwiftUI’s adaptive layout and `LayoutPriority` rather than absolute positioning from CSS.
- Translate responsive breakpoints into adaptive SwiftUI patterns (`@Environment(\.horizontalSizeClass)`, `ViewThatFits`, `Grid`).

## typography & color
- Define custom fonts via `Font.custom` or use dynamic type-friendly system fonts; respect `UIFontMetrics` and accessibility scaling.
- Convert CSS color values into `Color` extensions or asset catalog entries; prefer semantic names (`.primaryBackground`) over hex literals inline.
- Use `foregroundStyle`, `background`, and `tint` modifiers to replicate color application instead of layering rectangles.
- Support Dark Mode by providing both light/dark variants for palette entries, avoiding hard-coded light colors.

## componentization & state
- Break the UI into modular SwiftUI views with clear `init` parameters instead of large monolithic screens.
- Model UI state with `@State`, `@Binding`, `@ObservedObject`, `@EnvironmentObject`, or `@StateObject` following data ownership rules.
- Use `enum`-based view models or design system components to mirror HTML class variants (e.g., card styles, badge statuses).
- Replace CSS transitions/animations with SwiftUI `withAnimation`, `matchedGeometryEffect`, or `TimelineView`; keep motion tokens configurable.

## forms & interactions
- Match HTML form behaviors using `TextField`, `SecureField`, `Toggle`, `Picker`, and `Button`; ensure accessibility labels and hints mirror the original design intent.
- Respect focus flow with `@FocusState` and `submitLabel`; map HTML validation messages to SwiftUI alerts or inline error views.
- Convert hover/focus states into platform-appropriate cues (`hoverEffect` on iOS/iPadOS/macOS Catalyst, `buttonStyle` variants).

## accessibility & localization
- Translate semantic HTML elements (`<header>`, `<nav>`, `<section>`) into SwiftUI using `accessibilitySortPriority`, `accessibilityLabel`, `accessibilityAddTraits`.
- Support Dynamic Type, VoiceOver, and reduce motion; verify color contrast meets WCAG using system colors or accessible palettes.
- Prepare text for localization with `LocalizedStringKey`; avoid hard-coded strings inside view builders.

## testing & iteration
- Validate output with Xcode previews, testing multiple device sizes, locales, and accessibility settings; use preview modifiers to simulate states.
- Measure performance of complex layouts using Instruments, replacing heavy stacks with `Lazy` containers when needed.
- Establish snapshot or UI tests mirroring the original HTML reference to catch regressions after visual tweaks.

## avoid anti-patterns
- Do not embed raw HTML in `WKWebView` to mimic designs; reimplement using native SwiftUI for performance and platform fidelity.
- Avoid absolute positioning, pixel-perfect constraints, or fixed heights from the web design unless they adapt gracefully.
- Do not inline large style logic inside modifiers; encapsulate repeated style patterns in reusable view modifiers or custom views.
