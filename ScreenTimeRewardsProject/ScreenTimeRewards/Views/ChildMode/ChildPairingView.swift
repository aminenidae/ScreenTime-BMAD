import SwiftUI

struct ChildPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var isPairing = false
    @State private var showSuccessAlert = false
    @State private var pairedParents: [RegisteredDevice] = []
    @State private var showingUnpairConfirmation: RegisteredDevice?
    @State private var showHelp = false

    var body: some View {
        ZStack {
            // Background
            Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top App Bar
                HStack {
                    // Placeholder for back button (empty 48x48 space)
                    Color.clear
                        .frame(width: 48, height: 48)

                    Spacer()

                    Text("Connect to a Grown-up")
                        .font(.custom("Lexend", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(Colors.text)

                    Spacer()

                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(Colors.text)
                            .frame(width: 48, height: 48)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Colors.background)

                ScrollView {
                    VStack(spacing: 0) {
                        // Main Call-to-Action Block
                        VStack(spacing: 0) {
                            // Illustrative Graphic
                            VStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 120))
                                    .foregroundColor(Colors.primary)
                                    .frame(width: 192, height: 192)
                            }
                            .padding(.vertical, 12)

                            // Scan QR Code Button
                            Button {
                                if pairedParents.count < 2 {
                                    showScanner = true
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 24))

                                    Text("Scan QR Code")
                                        .font(.custom("Lexend", size: 18))
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(pairedParents.count >= 2 ? Colors.neutralGray : Colors.primary)
                                .cornerRadius(12)
                                .shadow(color: pairedParents.count < 2 ? Color.black.opacity(0.15) : Color.clear, radius: 4, y: 2)
                            }
                            .disabled(pairedParents.count >= 2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            // Body Text
                            Text("Ask your parent for their code to scan it with the camera.")
                                .font(.custom("Lexend", size: 16))
                                .foregroundColor(Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .padding(.top, 4)
                        }
                        .padding(.top, 32)

                        // Paired Parents List
                        VStack(alignment: .leading, spacing: 0) {
                            // Section Header
                            Text("Your Connected Grown-ups")
                                .font(.custom("Lexend", size: 18))
                                .fontWeight(.bold)
                                .foregroundColor(Colors.text)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                            // List Items or Empty State
                            if pairedParents.isEmpty {
                                // Empty State
                                VStack(spacing: 16) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 50))
                                        .foregroundColor(Colors.neutralGray)

                                    Text("No Grown-ups Yet")
                                        .font(.custom("Lexend", size: 16))
                                        .fontWeight(.bold)
                                        .foregroundColor(Colors.text)

                                    Text("Scan a code to connect with your first grown-up!")
                                        .font(.custom("Lexend", size: 14))
                                        .foregroundColor(Colors.secondaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 16)
                                .background(Colors.emptyStateBackground)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(pairedParents, id: \.deviceID) { parent in
                                        ParentListItem(
                                            parent: parent,
                                            onUnpair: {
                                                showingUnpairConfirmation = parent
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        Spacer()
                            .frame(height: 20)
                    }
                }
            }

            // Loading Overlay
            if isPairing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Pairing with parent device...")
                        .font(.custom("Lexend", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRCodeScannerView { result in
                showScanner = false
                handleScanResult(result)
            }
        }
        .alert("Pairing Successful", isPresented: $showSuccessAlert) {
            Button("Continue") {
                dismiss()
            }
        } message: {
            Text("Successfully paired with parent device!")
        }
        .alert("Unpair Parent Device", isPresented: Binding(
            get: { showingUnpairConfirmation != nil },
            set: { if !$0 { showingUnpairConfirmation = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                showingUnpairConfirmation = nil
            }
            Button("Unpair", role: .destructive) {
                if let parent = showingUnpairConfirmation {
                    Task {
                        await unpairFromParent(parent)
                    }
                }
                showingUnpairConfirmation = nil
            }
        } message: {
            Text("Are you sure you want to unpair from this parent device? You will no longer be able to sync usage data with them.")
        }
        .alert("Help", isPresented: $showHelp) {
            Button("OK") {
                showHelp = false
            }
        } message: {
            Text("Ask your parent to display their pairing QR code. Scan it with your camera to connect your devices. You can connect with up to 2 parents.")
        }
        .alert("Connection Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Try Again") {
                errorMessage = nil
                showScanner = true
            }
            Button("Cancel", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred while pairing.")
        }
        .onAppear {
            Task {
                await loadPairedParents()
            }
        }
    }

    private func handleScanResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let jsonString):
            pairWithParent(jsonString: jsonString)
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
        }
    }

    private func pairWithParent(jsonString: String) {
        isPairing = true
        errorMessage = nil

        Task {
            do {
                // Parse the QR code payload
                guard let payload = pairingService.parsePairingQRCode(jsonString) else {
                    throw NSError(domain: "PairingError", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid QR code format"])
                }

                #if DEBUG
                print("[ChildPairingView] QR code parsed successfully")
                print("[ChildPairingView] Parent Device ID: \(payload.parentDeviceID)")
                print("[ChildPairingView] Share URL: \(payload.shareURL)")
                print("[ChildPairingView] Shared Zone ID: \(payload.sharedZoneID ?? "nil")")
                #endif

                // Accept the parent's share and register in parent's shared zone
                try await pairingService.acceptParentShareAndRegister(from: payload)

                // 🔴 TASK 11: Trigger immediate usage upload after successful pairing
                #if DEBUG
                print("[ChildPairingView] ✅ Pairing completed successfully with CloudKit sharing")
                print("[ChildPairingView] Triggering immediate upload of existing usage records...")
                #endif

                // Upload any existing unsynced usage records immediately after pairing
                Task {
                    do {
                        await ChildBackgroundSyncService.shared.triggerImmediateUsageUpload()
                        #if DEBUG
                        print("[ChildPairingView] ✅ Post-pairing upload completed")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[ChildPairingView] ⚠️ Post-pairing upload failed: \(error)")
                        #endif
                    }
                }

                await MainActor.run {
                    self.isPairing = false
                    self.showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isPairing = false
                    self.errorMessage = "Failed to pair: \(error.localizedDescription)"
                }

                #if DEBUG
                print("[ChildPairingView] ❌ Pairing failed: \(error)")
                #endif
            }
        }
    }
    
    private func loadPairedParents() async {
        // Query all parent devices this child is paired with
        // This would involve querying CloudKit for registered devices
        // For now, we'll just leave this as a placeholder
        // In a real implementation, this would query the shared zones
    }
    
    private func unpairFromParent(_ parent: RegisteredDevice) async {
        // Remove child's device record from that parent's shared zone
        // This effectively unpairs
        #if DEBUG
        print("[ChildPairingView] 🔓 Child unpairing from parent: \(parent.deviceID ?? "unknown")")
        #endif
        
        // In a real implementation, this would delete the device record
        // from the parent's shared zone in CloudKit
    }
}

// MARK: - Parent List Item Component
struct ParentListItem: View {
    let parent: RegisteredDevice
    let onUnpair: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Avatar Circle
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
            }

            // Parent Info
            VStack(alignment: .leading, spacing: 4) {
                Text(parent.deviceName ?? "Unknown Parent")
                    .font(.custom("Lexend", size: 16))
                    .fontWeight(.bold)
                    .foregroundColor(ChildPairingView.Colors.text)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.custom("Lexend", size: 14))
                        .foregroundColor(ChildPairingView.Colors.secondaryText)
                }
            }

            Spacer()

            // Unpair Button
            Button {
                onUnpair()
            } label: {
                Image(systemName: "link.badge.minus")
                    .font(.system(size: 20))
                    .foregroundColor(ChildPairingView.Colors.secondaryText)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.96))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        // For now, all connected parents show as connected (green)
        // In a real implementation, this would check the parent's connection status
        return ChildPairingView.Colors.successGreen
    }

    private var statusText: String {
        // For now, all show as connected
        // In a real implementation, this would show actual status
        return "Connected"
    }
}

// MARK: - Design Tokens
extension ChildPairingView {
    struct Colors {
        // Primary Colors
        static let primary = Color(hex: "4A90E2")
        static let accentTeal = Color(hex: "50E3C2")

        // Background Colors
        static var background: Color {
            Color(UIColor.systemBackground)
        }

        static var emptyStateBackground: Color {
            Color(UIColor.secondarySystemBackground).opacity(0.5)
        }

        // Text Colors
        static var text: Color {
            Color(UIColor.label)
        }

        static var secondaryText: Color {
            Color(hex: "8E8E93")
        }

        // Status Colors
        static let successGreen = Color(hex: "7ED321")
        static let warningOrange = Color(hex: "F5A623")
        static let errorRed = Color(hex: "D0021B")
        static let neutralGray = Color(hex: "8E8E93")
    }
}

struct ChildPairingView_Previews: PreviewProvider {
    static var previews: some View {
        ChildPairingView()
    }
}