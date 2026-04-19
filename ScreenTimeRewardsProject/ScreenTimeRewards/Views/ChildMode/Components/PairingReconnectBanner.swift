//
//  PairingReconnectBanner.swift
//  ScreenTimeRewards
//
//  Non-blocking informational banner shown to children when the paired parent's
//  CloudKit zone is unreachable (e.g., parent switched iCloud accounts) while
//  the parent's subscription is still valid. Prompts a rescan without restricting
//  access to reward apps.
//

import SwiftUI

struct PairingReconnectBanner: View {
    @ObservedObject var syncService = ChildBackgroundSyncService.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showPairingSheet = false

    var body: some View {
        if syncService.needsReconnect && syncService.hasFullAccess {
            Button(action: { showPairingSheet = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync with parent interrupted")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text("Tap to reconnect — your access isn't affected")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.sunnyYellow)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPairingSheet) {
                ChildPairingPromptView()
            }
        }
    }
}

#Preview("Reconnect Banner") {
    VStack {
        PairingReconnectBanner()
        Spacer()
    }
}
