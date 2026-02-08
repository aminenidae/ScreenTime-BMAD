//
//  WelcomeScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Welcome screen shown on first app launch
//
//

import SwiftUI

struct WelcomeScreen: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            VStack(spacing: 0) {
                // Icon and headline section
                VStack(spacing: 0) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.vibrantTeal.opacity(0.2))
                            .frame(width: 80, height: 80)

                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                    .padding(.bottom, 24)

                    // Headline
                    Text("Transform Screen Time into Learning Time")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 384) // max-w-sm

                    // Subtitle
                    Text("Guide your child's digital journey. Encourage learning, reward progress, and build healthy habits together.")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 384) // max-w-sm
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)

                // Features section
                VStack(spacing: 24) {
                    // Feature 1
                    FeatureRow(
                        icon: "brain.head.profile",
                        title: "Set Learning Goals",
                        description: "Turn educational apps into exciting challenges.",
                        iconColor: AppTheme.vibrantTeal,
                        colorScheme: colorScheme
                    )

                    // Feature 2
                    FeatureRow(
                        icon: "trophy.fill",
                        title: "Reward Achievements",
                        description: "Unlock games and fun apps as they learn.",
                        iconColor: AppTheme.playfulCoral,
                        colorScheme: colorScheme
                    )

                    // Feature 3
                    FeatureRow(
                        icon: "figure.2.and.child.holdinghands",
                        title: "Foster Healthy Habits",
                        description: "Create a balanced and positive digital life.",
                        iconColor: AppTheme.vibrantTeal,
                        colorScheme: colorScheme
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }

            Spacer()

            // Footer section
            VStack(spacing: 16) {
                // Get Started button
                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.lightCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(12)
                        .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 12, x: 0, y: 4)
                }
                .frame(maxWidth: 480)

                // Login link
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

                    Button(action: {
                        // Login action
                    }) {
                        Text("Log In")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme))
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }
            .frame(width: 48, height: 48)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(onContinue: {})
    }
}
