//
//  SetupPathSelectionView.swift
//  ScreenTimeRewards
//
//  Asks parent how they want to monitor their child:
//  - Solo: On this device only (paywall on child device)
//  - Family: From parent's own device (paywall on parent device, 14-day trial for child)
//

import SwiftUI

/// The monitoring setup path chosen by the parent
enum SetupPath: String, Codable {
    case solo = "solo"       // Single device, no remote monitoring
    case family = "family"   // Multi-device with remote monitoring

    var displayName: String {
        switch self {
        case .solo: return String(localized: "Solo")
        case .family: return String(localized: "Family")
        }
    }
}

struct SetupPathSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var onboarding: OnboardingStateManager

    let onPathSelected: (SetupPath) -> Void

    @State private var selectedPath: SetupPath?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.top, 24)

                    // Path options
                    VStack(spacing: 16) {
                        PathOptionCard(
                            path: .solo,
                            isSelected: selectedPath == .solo,
                            onSelect: { selectedPath = .solo }
                        )

                        PathOptionCard(
                            path: .family,
                            isSelected: selectedPath == .family,
                            onSelect: { selectedPath = .family }
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)

                    Spacer(minLength: 24)

                    // Continue button
                    Button(action: {
                        guard let path = selectedPath else { return }
                        onPathSelected(path)
                    }) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedPath != nil ? AppTheme.vibrantTeal : Color.gray)
                            .cornerRadius(AppTheme.CornerRadius.medium)
                            .textCase(.uppercase)
                    }
                    .disabled(selectedPath == nil)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.and.arrow.right.inward")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.vibrantTeal)

            Text("Where will you manage the rules?")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                .padding(.horizontal, 24)

            Text("You can change this anytime later.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Path Option Card

private struct PathOptionCard: View {
    let path: SetupPath
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 16) {
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // Radio-style selection indicator (matches DeviceSelectionView)
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme),
                            lineWidth: 2
                        )
                        .background(Circle().fill(isSelected ? AppTheme.vibrantTeal : Color.clear))
                        .frame(width: 26, height: 26)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                            .stroke(isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme), lineWidth: isSelected ? 2.5 : 1)
                    )
                    .shadow(
                        color: isSelected ? AppTheme.vibrantTeal.opacity(0.25) : Color.black.opacity(0.06),
                        radius: isSelected ? 10 : 6, x: 0, y: 3
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch path {
        case .solo: return String(localized: "Right here on this device")
        case .family: return String(localized: "From my own phone")
        }
    }

    private var subtitle: String {
        switch path {
        case .solo: return String(localized: "Everything's set up on this phone. Best for a single or shared device.")
        case .family: return String(localized: "Use your phone as a remote control — start free for 14 days, pair later.")
        }
    }
}

// MARK: - Preview

#Preview {
    SetupPathSelectionView { path in
        print("Selected path: \(path)")
    }
    .environmentObject(OnboardingStateManager())
}
