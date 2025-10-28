//
//  WelcomeScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Welcome screen shown on first app launch
//

import SwiftUI

struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App icon and title
                VStack(spacing: 20) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)

                    Text("ScreenTime Rewards")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Transform screen time into learning time")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Features list
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "book.fill",
                        title: "Earn Points",
                        description: "Use learning apps to earn points"
                    )

                    FeatureRow(
                        icon: "gamecontroller.fill",
                        title: "Unlock Rewards",
                        description: "Spend points on fun reward apps"
                    )

                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Parent Controls",
                        description: "Secure parent mode to manage settings"
                    )
                }
                .padding(.horizontal, 40)

                Spacer()

                // Get Started button
                Button(action: onContinue) {
                    HStack {
                        Text("Get Started")
                            .font(.headline)
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(radius: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(onContinue: {})
    }
}
