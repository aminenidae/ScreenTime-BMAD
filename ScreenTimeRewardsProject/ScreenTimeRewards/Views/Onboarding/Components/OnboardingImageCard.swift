import SwiftUI

/// A reusable image card component for the onboarding flow.
/// Displays a full-width image with gradient overlay and text content.
struct OnboardingImageCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    var stepNumber: String? = nil
    var isSelected: Bool = false
    var aspectRatio: CGFloat = 400.0 / 1170.0 // Default horizontal card ratio
    var showCheckmark: Bool = false
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    // Design constants
    private let tealColor = Color(red: 31/255, green: 134/255, blue: 111/255) // #1F866F

    var body: some View {
        Button(action: { action?() }) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Background image
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    // Gradient overlay
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.45)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Text content
                    VStack(alignment: .leading, spacing: 6) {
                        if let num = stepNumber {
                            Text(num)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    .padding(16)

                    // Selected checkmark overlay
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
            }
            .aspectRatio(1.0 / aspectRatio, contentMode: .fit)
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

/// A variant for hero images (larger, typically full-screen width)
struct OnboardingHeroCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    var aspectRatio: CGFloat = 660.0 / 1170.0 // Hero card ratio

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background image
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.45)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(16)
            }
        }
        .aspectRatio(1.0 / aspectRatio, contentMode: .fit)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

/// Placeholder card for missing images
struct OnboardingPlaceholderCard: View {
    let title: String
    let subtitle: String
    var stepNumber: String? = nil
    var aspectRatio: CGFloat = 400.0 / 1170.0
    var isSelected: Bool = false
    var showCheckmark: Bool = false
    var action: (() -> Void)? = nil

    private let tealColor = Color(red: 31/255, green: 134/255, blue: 111/255)

    var body: some View {
        Button(action: { action?() }) {
            ZStack(alignment: .bottomLeading) {
                // Placeholder gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        tealColor.opacity(0.3),
                        tealColor.opacity(0.6)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Pattern overlay
                GeometryReader { geometry in
                    Path { path in
                        let spacing: CGFloat = 30
                        for i in stride(from: 0, to: geometry.size.width + geometry.size.height, by: spacing) {
                            path.move(to: CGPoint(x: i, y: 0))
                            path.addLine(to: CGPoint(x: 0, y: i))
                        }
                    }
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    if let num = stepNumber {
                        Text(num)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(16)

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
            .aspectRatio(1.0 / aspectRatio, contentMode: .fit)
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

// MARK: - Previews

#Preview("Image Card") {
    VStack(spacing: 20) {
        OnboardingImageCard(
            imageName: "onboarding_C2_1",
            title: "Agree on a Goal",
            subtitle: "Parent & child discuss learning targets",
            stepNumber: "1"
        )
        .padding(.horizontal)

        OnboardingImageCard(
            imageName: "onboarding_0_2",
            title: "Parent's Device",
            subtitle: "Set rules & monitor progress",
            isSelected: true,
            aspectRatio: 660.0 / 1170.0,
            showCheckmark: true
        )
        .padding(.horizontal)
    }
}

#Preview("Placeholder Card") {
    OnboardingPlaceholderCard(
        title: "Missing Image",
        subtitle: "This is a placeholder for a missing image",
        stepNumber: "1"
    )
    .padding()
}
