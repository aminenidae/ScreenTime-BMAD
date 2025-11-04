import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showingPairingView = false
    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared

    var body: some View {
        ZStack {
            // Soft gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 1.0),  // Soft purple
                    Color(red: 0.95, green: 0.97, blue: 1.0),  // Soft blue
                    Color(red: 1.0, green: 0.97, blue: 0.95)   // Soft peach
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Parent Mode Controls")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Exit Parent Mode Button
                    exitParentModeSection

                    Divider()
                        .padding(.horizontal)

                    // Parent Monitoring (Pairing)
                    parentMonitoringSection

                    Divider()
                        .padding(.horizontal)

                    // Device Settings (Reset)
                    deviceSettingsSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }
    }
}

// MARK: - Sections

private extension SettingsTabView {
    var exitParentModeSection: some View {
        VStack(spacing: 12) {
            Text("Mode")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                sessionManager.exitToSelection()
            }) {
                HStack {
                    Image(systemName: "arrow.backward.circle.fill")
                    Text("Exit Parent Mode")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }

    var parentMonitoringSection: some View {
        VStack(spacing: 12) {
            Text("Parent Monitoring")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !pairingService.isPaired() {
                // Not Paired - Show pairing option
                VStack(spacing: 16) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Connect to Parent Device")
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Text("Scan your parent's QR code to enable monitoring")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Scan Parent's QR Code") {
                        showingPairingView = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            } else {
                // Paired - Show status and disconnect
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        Text("Connected to Parent")
                            .font(.headline)
                    }

                    if let parentID = pairingService.getParentDeviceID() {
                        Text("Parent Device ID: \(parentID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Disconnect from Parent") {
                        pairingService.unpairDevice()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    var deviceSettingsSection: some View {
        VStack(spacing: 12) {
            Text("Device Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                showResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Device Mode")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red, lineWidth: 1)
                )
            }
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
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
    }
}