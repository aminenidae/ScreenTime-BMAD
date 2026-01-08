//
//  LaunchScreenView.swift
//  ScreenTimeRewards
//
//  Custom launch screen with app logo and animated rotation
//

import SwiftUI

struct LaunchScreenView: View {
    @State private var rotationDegrees: Double = 0
    @State private var opacity: Double = 1.0
    @State private var isLaunchComplete = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if isLaunchComplete {
            RootView()
                .transition(.opacity)
        } else {
            launchScreenContent
                .opacity(opacity)
                .onAppear { startLaunchAnimation() }
        }
    }

    private var launchScreenContent: some View {
        ZStack {
            // Background adapts to color scheme
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.large) {
                Image("LaunchIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(rotationDegrees))

                Text("Learn More... Earn More")
                    .font(AppTheme.Typography.title1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func startLaunchAnimation() {
        // Start rotation immediately (2 second duration for smoother effect)
        withAnimation(.easeInOut(duration: 2.0)) {
            rotationDegrees = 360
        }

        // Schedule fade out after 3.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
        }

        // Mark launch complete after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            isLaunchComplete = true
        }
    }
}
