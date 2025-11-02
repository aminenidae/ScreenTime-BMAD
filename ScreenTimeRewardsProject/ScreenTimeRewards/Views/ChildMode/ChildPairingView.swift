import SwiftUI

struct ChildPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var isPairing = false
    @State private var showSuccessAlert = false
    @State private var pairedParents: [RegisteredDevice] = []
    @State private var showingUnpairConfirmation: RegisteredDevice?

    var body: some View {
        VStack(spacing: 30) {
            Text("Pair with Parent Device")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            // Show current pairing status
            if !pairedParents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paired Parent Devices (\(pairedParents.count)/2)")
                        .font(.headline)

                    ForEach(pairedParents, id: \.deviceID) { parent in
                        HStack {
                            Image(systemName: "iphone.and.arrow.forward")
                                .foregroundColor(.blue)

                            VStack(alignment: .leading) {
                                Text(parent.deviceName ?? "Unknown Parent")
                                    .font(.subheadline)
                                Text("Paired on \(parent.registrationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Unpair") {
                                showingUnpairConfirmation = parent
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }

                    if pairedParents.count >= 2 {
                        Text("Maximum parent devices reached. Unpair from one parent to add another.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }

            if !showScanner {
                VStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                        .padding()

                    Text("Scan the QR code displayed on your parent's device")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "camera")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .disabled(pairedParents.count >= 2) // Disable if max parents reached
                }
            } else if isPairing {
                ProgressView("Pairing with parent device...")
                    .padding()
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.1))
                    )
                    .padding(.horizontal)

                Button {
                    errorMessage = nil
                    showScanner = true
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding()
            }

            VStack(spacing: 10) {
                Label {
                    Text("Get the QR code from your parent's device")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Label {
                    Text("Child device can use a different iCloud account")
                } icon: {
                    Image(systemName: "icloud")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal)

            Spacer()
        }
        .padding()
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

struct ChildPairingView_Previews: PreviewProvider {
    static var previews: some View {
        ChildPairingView()
    }
}