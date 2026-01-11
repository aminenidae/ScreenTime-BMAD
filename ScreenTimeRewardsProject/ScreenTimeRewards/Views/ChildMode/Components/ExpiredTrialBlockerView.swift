//
//  ExpiredTrialBlockerView.swift
//  ScreenTimeRewards
//
//  Full-screen blocker shown when child's trial expires
//  and they haven't paired with a subscribed parent.
//

import SwiftUI

/// Full-screen blocker that prevents app usage when trial expires
struct ExpiredTrialBlockerView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showPairingSheet = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Content
                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 100, height: 100)

                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                    }

                    // Title
                    Text("Trial Ended")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    // Message
                    Text("Your 14-day free trial has ended.\nConnect with your parent to continue using the app.")
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 24)

                    // Primary CTA: Connect with parent
                    Button(action: { showPairingSheet = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 20))

                            Text("Connect with Parent")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)

                        Text("or")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 12)

                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)

                    // Secondary CTA: Subscribe Solo
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 16))

                            Text("Subscribe on This Device")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Footer
                Text("Ask your parent to subscribe on their device,\nthen scan their QR code to connect.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showPairingSheet) {
            ChildPairingPromptView()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationView {
                SubscriptionPaywallView(
                    isOnboarding: false,
                    onComplete: {
                        // Dismiss paywall when subscription is successful
                        showPaywall = false
                    }
                )
                .environmentObject(subscriptionManager)
            }
        }
    }
}

// MARK: - Preview

#Preview("Expired Trial Blocker") {
    ExpiredTrialBlockerView()
        .environmentObject(SubscriptionManager.shared)
}
