import SwiftUI
import CoreImage.CIFilterBuiltins
import CloudKit
import UIKit

struct ParentPairingView: View {
    @StateObject private var pairingService = DevicePairingService.shared
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var qrCodeImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var cloudKitStatus: CloudKitStatus = .checking
    @State private var showSubscriptionPaywall = false

    // QR type selection
    @State private var selectedQRType: QRType = .child

    enum QRType: String, CaseIterable {
        case child = "Child Device"
        case coParent = "Co-Parent"
    }

    // Polling for new child device
    @State private var isPollingForChild = false
    @State private var initialChildCount = 0
    @Environment(\.dismiss) private var dismiss

    enum CloudKitStatus: Equatable {
        case checking
        case available
        case notAuthenticated
        case unavailable(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text(selectedQRType == .child ? "Add Child Device" : "Invite Co-Parent")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            // QR Type Picker
            Picker("QR Type", selection: $selectedQRType) {
                ForEach(QRType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedQRType) { _ in
                // Reset QR when switching types
                qrCodeImage = nil
                isPollingForChild = false
                errorMessage = nil
            }

            if cloudKitStatus == .checking {
                ProgressView("Checking iCloud status...")
                    .padding()
            } else if case .notAuthenticated = cloudKitStatus {
                cloudKitSetupInstructions
            } else if case .unavailable(let reason) = cloudKitStatus {
                cloudKitErrorView(reason: reason)
            } else if isGenerating {
                ProgressView(selectedQRType == .child ? "Generating QR code..." : "Creating invitation...")
                    .padding()
            } else if let qrImage = qrCodeImage {
                qrCodeDisplayView(qrImage: qrImage)
            } else {
                qrGeneratePrompt
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.1))
                    )
                    .padding(.horizontal)
            }

            infoSection

            Spacer()
        }
        .padding()
        .onAppear {
            checkCloudKitAndGenerate()
        }
        .onDisappear {
            // Stop polling when view is dismissed
            isPollingForChild = false
        }
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView()
        }
    }

    // MARK: - QR Code Display

    private func qrCodeDisplayView(qrImage: UIImage) -> some View {
        VStack(spacing: 20) {
            Text(selectedQRType == .child ? "Scan this QR code" : "Co-Parent Invitation")
                .font(.headline)
                .foregroundColor(.secondary)

            // Display QR code
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.white)
                )
                .padding(.horizontal)

            Text(selectedQRType == .child
                 ? "Scan this code on your child's device"
                 : "Your partner should scan this code to join your family")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Polling indicator (only for child)
            if selectedQRType == .child && isPollingForChild {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for child device to connect...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            // Important notices
            if selectedQRType == .child {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Child device must use a different Apple ID")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundColor(AppTheme.vibrantTeal)
                    Text("This code expires in 10 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            Button {
                generateQRCode()
            } label: {
                Label("Generate New Code", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
    }

    // MARK: - Generate Prompt

    private var qrGeneratePrompt: some View {
        VStack(spacing: 16) {
            if selectedQRType == .child {
                Image(systemName: "qrcode")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Generate a QR code for your child to scan")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Invite your partner to monitor together")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("They'll get full access without paying separately")
                    .font(.caption)
                    .foregroundColor(AppTheme.vibrantTeal)
            }

            Button {
                generateQRCode()
            } label: {
                Label(selectedQRType == .child ? "Generate QR Code" : "Create Invitation",
                      systemImage: selectedQRType == .child ? "qrcode" : "person.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 10) {
            if selectedQRType == .child {
                Label {
                    Text("Child device can use a different iCloud account")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Label {
                    Text("Secure single-use code prevents sharing abuse")
                } icon: {
                    Image(systemName: "checkmark.shield")
                }
                .font(.caption)
                .foregroundColor(.green)
            } else {
                Label {
                    Text("Co-parents share your family subscription")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Label {
                    Text("Both parents can monitor all children")
                } icon: {
                    Image(systemName: "person.2.fill")
                }
                .font(.caption)
                .foregroundColor(AppTheme.vibrantTeal)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }

    private func checkCloudKitAndGenerate() {
        cloudKitStatus = .checking

        Task {
            let status = await pairingService.checkCloudKitAvailability()

            await MainActor.run {
                if status {
                    self.cloudKitStatus = .available
                    // Don't auto-generate - user must click button to avoid destroying existing pairings
                } else {
                    self.cloudKitStatus = .notAuthenticated
                }
            }
        }
    }

    var cloudKitSetupInstructions: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 64))
                .foregroundColor(.orange)
                .padding(.top, 20)

            Text("iCloud Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("Pairing requires iCloud to sync usage data between devices.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                Text("To enable pairing:")
                    .font(.headline)
                    .padding(.bottom, 4)

                HStack(alignment: .top, spacing: 12) {
                    Text("1.")
                        .fontWeight(.bold)
                    Text("Open **Settings** app on this device")
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("2.")
                        .fontWeight(.bold)
                    Text("Tap your name at the top")
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("3.")
                        .fontWeight(.bold)
                    Text("Tap **iCloud**")
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("4.")
                        .fontWeight(.bold)
                    Text("Sign in with your Apple ID")
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("5.")
                        .fontWeight(.bold)
                    Text("Return to this app and try again")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
            )
            .padding(.horizontal)

            Button {
                checkCloudKitAndGenerate()
            } label: {
                Label("Check iCloud Status", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()

            Spacer()
        }
        .padding()
    }

    func cloudKitErrorView(reason: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 64))
                .foregroundColor(.red)
                .padding(.top, 20)

            Text("iCloud Error")
                .font(.title2)
                .fontWeight(.bold)

            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                checkCloudKitAndGenerate()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()

            Spacer()
        }
        .padding()
    }

    private func generateQRCode() {
        isGenerating = true
        errorMessage = nil
        qrCodeImage = nil

        Task {
            do {
                if selectedQRType == .child {
                    try await generateChildQRCode()
                } else {
                    try await generateCoParentQRCode()
                }
            } catch {
                await handleQRGenerationError(error)
            }
        }
    }

    private func generateChildQRCode() async throws {
        #if DEBUG
        print("[ParentPairingView] 🔵 Starting child QR code generation...")
        #endif

        // Try secure pairing first if Firebase is configured
        if pairingService.isSecurePairingEnabled {
            #if DEBUG
            print("[ParentPairingView] 🔵 Using secure (Firebase-validated) pairing...")
            #endif

            let (_, qrData, _, _) = try await pairingService.createSecurePairingSession()

            if let ciImage = pairingService.generateQRCodeImage(from: qrData) {
                await MainActor.run {
                    self.qrCodeImage = convertCIImageToUIImage(ciImage)
                    self.isGenerating = false
                    self.startPollingForNewChild()
                }
                #if DEBUG
                print("[ParentPairingView] ✅ Secure QR code generated successfully")
                #endif
            } else {
                throw PairingError.invalidQRCode
            }
        } else {
            // Fall back to legacy CloudKit-only pairing
            #if DEBUG
            print("[ParentPairingView] 🔵 Using legacy CloudKit pairing (no Firebase)...")
            #endif

            let (sessionID, verificationToken, share, zoneID) = try await pairingService.createPairingSession()

            if let ciImage = pairingService.generatePairingQRCode(
                sessionID: sessionID,
                verificationToken: verificationToken,
                share: share,
                zoneID: zoneID
            ) {
                await MainActor.run {
                    self.qrCodeImage = convertCIImageToUIImage(ciImage)
                    self.isGenerating = false
                    self.startPollingForNewChild()
                }
                #if DEBUG
                print("[ParentPairingView] ✅ Legacy QR code generated: \(sessionID)")
                #endif
            } else {
                throw PairingError.invalidQRCode
            }
        }
    }

    private func generateCoParentQRCode() async throws {
        #if DEBUG
        print("[ParentPairingView] 🔵 Generating co-parent invitation QR code...")
        #endif

        // Co-parent QR always requires Firebase
        guard pairingService.isSecurePairingEnabled else {
            throw PairingError.networkError(NSError(domain: "PairingError", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Please complete subscription setup before inviting a co-parent."]))
        }

        // Get a family name for the invitation
        let familyName = DeviceModeManager.shared.deviceName + "'s Family"

        if let ciImage = try await pairingService.generateCoParentQRCode(familyName: familyName) {
            await MainActor.run {
                self.qrCodeImage = convertCIImageToUIImage(ciImage)
                self.isGenerating = false
            }
            #if DEBUG
            print("[ParentPairingView] ✅ Co-parent QR code generated successfully")
            #endif
        } else {
            throw PairingError.invalidQRCode
        }
    }

    private func handleQRGenerationError(_ error: Error) async {
        #if DEBUG
        print("[ParentPairingView] ❌ QR code generation error:")
        print("[ParentPairingView] Error type: \(type(of: error))")
        print("[ParentPairingView] Error: \(error.localizedDescription)")
        #endif

        await MainActor.run {
            self.isGenerating = false

            // Handle specific error types with helpful messages
            if case PairingError.deviceLimitReached = error {
                self.showSubscriptionPaywall = true
                self.errorMessage = nil
            } else if case PairingError.soloCannotPair = error {
                self.errorMessage = "Solo subscription doesn't support device pairing. Please upgrade to Individual or Family plan."
            } else if case PairingError.firebaseValidationFailed(let fbError) = error {
                self.errorMessage = fbError.errorDescription ?? "Validation failed. Please try again."
            } else if case PairingError.networkError(let ckError) = error {
                if let cloudKitError = ckError as? CKError, cloudKitError.code == .notAuthenticated {
                    self.cloudKitStatus = .notAuthenticated
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Connection error. Please check your internet and try again."
                }
            } else if let ckError = error as? CKError {
                switch ckError.code {
                case .notAuthenticated:
                    self.cloudKitStatus = .notAuthenticated
                    self.errorMessage = nil
                case .networkUnavailable, .networkFailure:
                    self.errorMessage = "No internet connection. Please connect and try again."
                case .quotaExceeded:
                    self.errorMessage = "iCloud storage is full. Please free up space in Settings."
                default:
                    self.errorMessage = "iCloud error: \(ckError.localizedDescription)"
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func startPollingForNewChild() {
        isPollingForChild = true

        Task {
            // Capture initial child count
            let cloudKitSync = CloudKitSyncService.shared
            let startCount = (try? await cloudKitSync.fetchLinkedChildDevices().count) ?? 0
            initialChildCount = startCount

            #if DEBUG
            print("[ParentPairingView] 🔄 Starting polling for new child device. Initial count: \(startCount)")
            #endif

            // Poll every 2 seconds for up to 5 minutes (150 attempts)
            for attempt in 1...150 {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                // Check if polling was cancelled
                guard isPollingForChild else {
                    #if DEBUG
                    print("[ParentPairingView] 🛑 Polling cancelled")
                    #endif
                    return
                }

                // Fetch current child count
                let currentCount = (try? await cloudKitSync.fetchLinkedChildDevices().count) ?? 0

                #if DEBUG
                if attempt % 10 == 0 {
                    print("[ParentPairingView] 🔄 Poll attempt \(attempt): \(currentCount) children (started with \(startCount))")
                }
                #endif

                if currentCount > startCount {
                    // SUCCESS - new child detected!
                    #if DEBUG
                    print("[ParentPairingView] ✅ New child device detected! Closing view...")
                    #endif

                    await MainActor.run {
                        isPollingForChild = false
                        // Notify parent dashboard to refresh all data (not just device list)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NewChildPaired"),
                            object: nil
                        )
                        dismiss()
                    }
                    return
                }
            }

            // Timeout after 5 minutes
            #if DEBUG
            print("[ParentPairingView] ⏰ Polling timeout after 5 minutes")
            #endif

            await MainActor.run {
                isPollingForChild = false
            }
        }
    }

    private func convertCIImageToUIImage(_ ciImage: CIImage) -> UIImage {
        let context = CIContext()
        let scale = UIScreen.main.scale
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale * 10, y: scale * 10))

        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage()
    }
}

#Preview {
    ParentPairingView()
        .environmentObject(SubscriptionManager.shared)
}
