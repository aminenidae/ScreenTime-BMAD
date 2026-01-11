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
        case .solo: return "Solo"
        case .family: return "Family"
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

            Text("How would you like to monitor your child?")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                .padding(.horizontal, 24)

            Text("Choose how you want to manage screen time")
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
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 56, height: 56)

                    Image(systemName: iconName)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppTheme.vibrantTeal : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? AppTheme.vibrantTeal : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch path {
        case .solo: return "iphone"
        case .family: return "iphone.gen3.radiowaves.left.and.right"
        }
    }

    private var iconColor: Color {
        switch path {
        case .solo: return AppTheme.sunnyYellow
        case .family: return AppTheme.vibrantTeal
        }
    }

    private var iconBackgroundColor: Color {
        switch path {
        case .solo: return AppTheme.sunnyYellow.opacity(0.2)
        case .family: return AppTheme.vibrantTeal.opacity(0.2)
        }
    }

    private var title: String {
        switch path {
        case .solo: return "On This Device Only"
        case .family: return "From My Own Device"
        }
    }

    private var subtitle: String {
        switch path {
        case .solo: return "Monitor your child's usage directly on their device"
        case .family: return "Monitor remotely from your phone or tablet"
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
