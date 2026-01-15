import SwiftUI
import FamilyControls
import ManagedSettings

/// View for selecting and managing blocked websites using FamilyActivityPicker
struct WebsiteBlockingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    private let screenTimeService = ScreenTimeService.shared

    @State private var familySelection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var blockedCount: Int = 0

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header info
                    VStack(spacing: 12) {
                        Image(systemName: "globe.badge.chevron.backward")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.playfulCoral)

                        Text("Block Websites")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        Text("Select websites from browsing history to block. When blocked, a shield will appear when trying to access them.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    // Current blocked websites count
                    if blockedCount > 0 {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)

                            Text("\(blockedCount) website\(blockedCount == 1 ? "" : "s") blocked")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))

                            Spacer()

                            Button(action: clearAllBlocked) {
                                Text("Clear All")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.playfulCoral)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.card(for: colorScheme))
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    Spacer()

                    // Add websites button
                    VStack(spacing: 16) {
                        Button(action: {
                            isPickerPresented = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))

                                Text("Select Websites to Block")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(AppTheme.playfulCoral)
                            )
                        }
                        .padding(.horizontal, 16)

                        // Note about picker limitation
                        Text("Only websites from browsing history will appear in the picker.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.vibrantTeal)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
                }
            }
            .familyActivityPicker(
                isPresented: $isPickerPresented,
                selection: $familySelection
            )
            .onChange(of: familySelection) { newSelection in
                applyWebDomainSelection(newSelection)
            }
            .onAppear {
                loadCurrentSelection()
            }
        }
    }

    // MARK: - Helper Methods

    private func loadCurrentSelection() {
        // Pre-populate the picker with currently blocked domains
        // Note: FamilyActivitySelection doesn't expose webDomainTokens directly for reading,
        // so we track blocked domains separately in ScreenTimeService
        blockedCount = screenTimeService.currentlyBlockedWebDomains.count
    }

    private func applyWebDomainSelection(_ selection: FamilyActivitySelection) {
        // Get the web domain tokens from the selection
        let newWebDomains = selection.webDomainTokens

        // Sync with ScreenTimeService
        screenTimeService.syncWebDomainShields(currentBlockedDomains: newWebDomains)

        // Update local count for UI
        blockedCount = newWebDomains.count

        // Sync to paired child devices via CloudKit
        Task {
            await screenTimeService.syncWebRestrictionsToChildren()
        }

        #if DEBUG
        print("[WebsiteBlockingView] Applied \(newWebDomains.count) web domain blocks")
        #endif
    }

    private func clearAllBlocked() {
        // Clear all blocked web domains
        screenTimeService.syncWebDomainShields(currentBlockedDomains: [])

        // Reset the picker selection
        familySelection = FamilyActivitySelection()

        // Update local count for UI
        blockedCount = 0

        // Sync to paired child devices via CloudKit
        Task {
            await screenTimeService.syncWebRestrictionsToChildren()
        }

        #if DEBUG
        print("[WebsiteBlockingView] Cleared all blocked websites")
        #endif
    }
}

// MARK: - Preview

struct WebsiteBlockingView_Previews: PreviewProvider {
    static var previews: some View {
        WebsiteBlockingView()
    }
}
