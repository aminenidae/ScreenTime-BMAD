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
        ZStack(alignment: .top) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                ScrollView {
                    VStack(spacing: 24) {
                        scanCard
                        connectedParentsSection
                    }
                    .padding(20)
                }
            }
            
            // Loading Overlay
            if isPairing {
                loadingOverlay
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
            Button("OK") { showHelp = false }
        } message: {
            Text("Ask your parent to display their pairing QR code. Scan it with your camera to connect your devices.")
        }
        .alert("Connection Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Try Again") {
                errorMessage = nil
                showScanner = true
            }
            Button("Cancel", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An error occurred while pairing.")
        }
        .onAppear {
            Task { await loadPairedParents() }
        }
    }
}

// MARK: - Components

private extension ChildPairingView {
    var headerView: some View {
        ZStack {
            HStack {
                Spacer()
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
            }
            
            // Centered Title
            Text("PAIRING STATUS")
                .font(.system(size: 18, weight: .bold))
                .tracking(2)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
            
            // Left dismiss button
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.background(for: colorScheme))
    }

    var scanCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(AppTheme.vibrantTeal)
                .padding(.top, 8)
                
            VStack(spacing: 8) {
                Text("Connect New Device")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                
                Text("Ask your parent for their code to scan it with the camera.")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            Button {
                if pairedParents.count < 2 {
                    showScanner = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                    Text("SCAN QR CODE")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(AppTheme.lightCream)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(pairedParents.count >= 2 ? Color.gray : AppTheme.vibrantTeal)
                .cornerRadius(16)
                .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(pairedParents.count >= 2)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 10, x: 0, y: 4)
        )
    }

    var connectedParentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNECTED GROWN-UPS")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                .padding(.leading, 4)
            
            if pairedParents.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(pairedParents, id: \.deviceID) { parent in
                        ParentListItem(
                            parent: parent,
                            onUnpair: { showingUnpairConfirmation = parent }
                        )
                    }
                }
            }
        }
    }
    
    var emptyState: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.brandedText(for: colorScheme).opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "person.badge.plus")
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                    .font(.system(size: 24))
            }
            
            Text("No devices connected yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.brandedText(for: colorScheme).opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.lightCream)

                Text("Pairing...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.lightCream)
            }
            .padding(32)
            .background(AppTheme.vibrantTeal)
            .cornerRadius(20)
            .shadow(radius: 20)
        }
    }
}

// MARK: - Logic Helpers

private extension ChildPairingView {
    func handleScanResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let jsonString):
            pairWithParent(jsonString: jsonString)
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
        }
    }

    func pairWithParent(jsonString: String) {
        isPairing = true
        errorMessage = nil

        Task {
            do {
                guard let payload = pairingService.parsePairingQRCode(jsonString) else {
                    throw NSError(domain: "PairingError", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid QR code format"])
                }

                try await pairingService.acceptParentShareAndRegister(from: payload)
                
                // Trigger upload
                Task {
                    await ChildBackgroundSyncService.shared.triggerImmediateUsageUpload()
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
            }
        }
    }
    
    func loadPairedParents() async {
        // Placeholder for loading logic
    }
    
    func unpairFromParent(_ parent: RegisteredDevice) async {
        // Placeholder for unpairing logic
    }
}

// MARK: - List Item

struct ParentListItem: View {
    let parent: RegisteredDevice
    let onUnpair: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppTheme.sunnyYellow.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(parent.deviceName ?? "Unknown Parent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.sunnyYellow)
                        .frame(width: 8, height: 8)

                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }
            }

            Spacer()

            Button {
                onUnpair()
            } label: {
                Image(systemName: "link.badge.minus")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 2, x: 0, y: 1)
        )
    }
}