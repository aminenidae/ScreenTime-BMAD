import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairingView = false
    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Account Section
                        settingsSection(title: "ACCOUNT") {
                            exitParentModeRow
                        }

                        // Devices Section
                        settingsSection(title: "DEVICES") {
                            pairingStatusRow
                        }

                        // Danger Zone Section
                        VStack(alignment: .leading, spacing: 8) {
                            settingsSection(title: "DANGER ZONE") {
                                resetDeviceRow
                            }

                            Text("This will erase all app settings and data on this device.")
                                .font(.system(size: 12))
                                .foregroundColor(Colors.textSecondary)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Colors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Colors.primary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 24))
                            .foregroundColor(Colors.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }
    }
}

// MARK: - Helper Functions

private extension SettingsTabView {
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Colors.textSecondary)
                .tracking(0.6)
                .padding(.horizontal, 20)

            content()
        }
    }
}

// MARK: - Row Views

private extension SettingsTabView {
    var exitParentModeRow: some View {
        Button(action: {
            sessionManager.exitToSelection()
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Colors.primary.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .foregroundColor(Colors.primary)
                }

                // Label
                Text("Exit Parent Mode")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.textPrimary)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.textSecondary)
            }
            .padding(16)
            .background(Colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var pairingStatusRow: some View {
        Button(action: {
            if !pairingService.isPaired() {
                showingPairingView = true
            }
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Colors.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 20))
                        .foregroundColor(Colors.secondary)
                }

                // Status content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Status")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.textPrimary)

                    if pairingService.isPaired() {
                        Text("Paired with Child's iPad")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.secondary)
                    } else {
                        Text("Not paired")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.textSecondary)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.textSecondary)
            }
            .padding(16)
            .background(Colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var resetDeviceRow: some View {
        Button(action: {
            showResetConfirmation = true
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Colors.destructive.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20))
                        .foregroundColor(Colors.destructive)
                }

                // Label
                Text("Reset This Device")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.destructive)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.textSecondary)
            }
            .padding(16)
            .background(Colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Reset Device Mode?",
                          isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                modeManager.resetDeviceMode()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset your device mode selection. App configurations will be preserved.")
        }
    }
}

// MARK: - Design Tokens

private extension SettingsTabView {
    struct Colors {
        static let primary = Color(red: 0.00, green: 0.35, blue: 0.61)  // #005A9C
        static let secondary = Color(red: 0.30, green: 0.69, blue: 0.63)  // #4DB1A1
        static let destructive = Color(red: 0.84, green: 0.15, blue: 0.24)  // #D7263D
        static let background = Color(red: 0.98, green: 0.98, blue: 0.98)  // #F9F9F9
        static let textPrimary = Color(red: 0.13, green: 0.13, blue: 0.13)  // #222222
        static let textSecondary = Color(red: 0.42, green: 0.45, blue: 0.50)  // #6B7280
        static let surface = Color.white  // #FFFFFF
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
    }
}