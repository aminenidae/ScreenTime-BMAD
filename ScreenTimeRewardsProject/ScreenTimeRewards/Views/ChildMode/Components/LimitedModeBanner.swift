//
//  LimitedModeBanner.swift
//  ScreenTimeRewards
//
//  Banner shown to children when parent subscription has expired
//  or trial period has ended without pairing with a subscribed parent.
//

import SwiftUI

/// Banner displayed when child doesn't have full access
struct LimitedModeBanner: View {
    @ObservedObject var syncService = ChildBackgroundSyncService.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showPairingSheet = false

    var body: some View {
        if !syncService.hasFullAccess {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: bannerIcon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)

                    // Message
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        Text(bannerSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    // Action button
                    Button(action: { showPairingSheet = true }) {
                        Text("Connect")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(bannerColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bannerColor)
            }
            .sheet(isPresented: $showPairingSheet) {
                ChildPairingPromptView()
            }
        }
    }

    private var bannerIcon: String {
        switch syncService.parentSubscriptionStatus {
        case .trial:
            return "clock.fill"
        case .expired:
            return "exclamationmark.triangle.fill"
        case .unpaired:
            return "link.badge.plus"
        default:
            return "exclamationmark.circle.fill"
        }
    }

    private var bannerTitle: String {
        switch syncService.parentSubscriptionStatus {
        case .trial:
            if let days = syncService.trialDaysRemaining, days > 0 {
                return "Trial: \(days) day\(days == 1 ? "" : "s") left"
            }
            return "Trial Expired"
        case .expired:
            return "Subscription Expired"
        case .unpaired:
            return "Not Connected"
        default:
            return "Limited Access"
        }
    }

    private var bannerSubtitle: String {
        switch syncService.parentSubscriptionStatus {
        case .trial:
            return "Ask your parent to set up their device"
        case .expired:
            return "Ask your parent to renew"
        case .unpaired:
            return "Connect with your parent to unlock"
        default:
            return "Some features are limited"
        }
    }

    private var bannerColor: Color {
        switch syncService.parentSubscriptionStatus {
        case .trial:
            return AppTheme.sunnyYellow
        case .expired, .unpaired:
            return Color.orange
        default:
            return AppTheme.vibrantTeal
        }
    }
}

/// Prompt shown when child taps "Connect" button
struct ChildPairingPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var syncService = ChildBackgroundSyncService.shared

    @State private var showScanner = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Illustration
                        illustrationSection

                        // Instructions
                        instructionsSection

                        // Scan button
                        scanButton

                        // Help text
                        helpText
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Connect with Parent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRCodeScannerView { result in
                showScanner = false
                handleScanResult(result)
            }
        }
    }

    private var illustrationSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.vibrantTeal)
            }

            if syncService.parentSubscriptionStatus == .trial,
               let days = syncService.trialDaysRemaining, days > 0 {
                Text("Your trial has \(days) day\(days == 1 ? "" : "s") remaining")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.sunnyYellow)
            } else {
                Text("Scan your parent's QR code to continue")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionStepRow(number: 1, text: "Ask your parent to open ScreenTimeRewards")
            InstructionStepRow(number: 2, text: "They tap 'Add Child Device' in Settings")
            InstructionStepRow(number: 3, text: "Scan the QR code they show you")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private var scanButton: some View {
        Button(action: { showScanner = true }) {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 20))

                Text("Scan Parent's Code")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AppTheme.vibrantTeal)
            .cornerRadius(16)
        }
    }

    private var helpText: some View {
        Text("Once connected, you'll have full access to all features and your parent can see your progress.")
            .font(.system(size: 13))
            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            .multilineTextAlignment(.center)
    }

    private func handleScanResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let jsonString):
            Task {
                do {
                    try await DevicePairingService.shared.handleScannedQRCode(jsonString)

                    // Verify subscription immediately after pairing
                    await syncService.verifyParentSubscription()

                    await MainActor.run {
                        dismiss()
                    }
                } catch {
                    // Handle error - could show alert
                    #if DEBUG
                    print("[ChildPairingPromptView] Pairing failed: \(error)")
                    #endif
                }
            }
        case .failure(let error):
            #if DEBUG
            print("[ChildPairingPromptView] Scan failed: \(error)")
            #endif
        }
    }
}

/// Instruction step row
private struct InstructionStepRow: View {
    let number: Int
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.vibrantTeal)
                    .frame(width: 28, height: 28)

                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Banner - Trial") {
    VStack {
        LimitedModeBanner()
        Spacer()
    }
}

#Preview("Pairing Prompt") {
    ChildPairingPromptView()
}
