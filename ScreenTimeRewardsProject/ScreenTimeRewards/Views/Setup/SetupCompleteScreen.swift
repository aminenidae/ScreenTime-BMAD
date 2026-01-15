//
//  SetupCompleteScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Shows setup completion and instructions
//
//

import SwiftUI

struct SetupCompleteScreen: View {
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Content area - main content
            VStack(spacing: 0) {
                // Success icon section
                ZStack {
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(width: 160, height: 160)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 128))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
                .padding(.bottom, 32)

                // Headline
                Text("Setup Complete!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .padding(.top, 8)

                // Subtitle
                Text("You're all set to empower your child's learning journey.")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 448) // max-w-md
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .padding(.top, 4)

                // Quick Tips section
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Text("Quick Tips to Get Started")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                            .multilineTextAlignment(.center)

                        // Tip 1
                        TipCard(
                            icon: "lightbulb.fill",
                            title: "Explore Together:",
                            description: "Show your child how to earn rewards by using their Learning Apps.",
                            colorScheme: colorScheme
                        )

                        // Tip 2
                        TipCard(
                            icon: "gearshape.fill",
                            title: "Adjust Goals:",
                            description: "You can easily change daily time targets from the Parent Dashboard.",
                            colorScheme: colorScheme
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .frame(maxWidth: 448) // max-w-md
            }
            .padding(.top, 64)

            Spacer()

            // Footer section - sticky bottom button
            VStack(spacing: 0) {
                Button(action: onComplete) {
                    Text("Start Using App")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.lightCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(12)
                        .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                .frame(maxWidth: 448) // max-w-md
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(AppTheme.background(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme))
    }
}

// MARK: - Tip Card Component
struct TipCard: View {
    let icon: String
    let title: String
    let description: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.playfulCoral)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            // Text content
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                +
                Text(" ")
                +
                Text(description)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct SetupCompleteScreen_Previews: PreviewProvider {
    static var previews: some View {
        SetupCompleteScreen(onComplete: {})
    }
}
