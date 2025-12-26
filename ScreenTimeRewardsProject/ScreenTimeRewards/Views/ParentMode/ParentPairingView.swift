import SwiftUI
import CoreImage.CIFilterBuiltins
import CloudKit
import UIKit

struct ParentPairingView: View {
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var qrCodeImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var cloudKitStatus: CloudKitStatus = .checking
    @State private var showSubscriptionPaywall = false

    enum CloudKitStatus: Equatable {
        case checking
        case available
        case notAuthenticated
        case unavailable(String)
    }

    var body: some View {
        VStack(spacing: 30) {
            Text("Add Child Device")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if cloudKitStatus == .checking {
                ProgressView("Checking iCloud status...")
                    .padding()
            } else if case .notAuthenticated = cloudKitStatus {
                cloudKitSetupInstructions
            } else if case .unavailable(let reason) = cloudKitStatus {
                cloudKitErrorView(reason: reason)
            } else if isGenerating {
                ProgressView("Generating QR code...")
                    .padding()
            } else if let qrImage = qrCodeImage {
                VStack(spacing: 20) {
                    Text("Scan this QR code")
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

                    Text("Scan this code on your child's device")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // Important notice about different Apple ID requirement
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

                    Button {
                        generateQRCode()
                    } label: {
                        Label("Generate New QR Code", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            } else {
                Button {
                    generateQRCode()
                } label: {
                    Label("Generate QR Code", systemImage: "qrcode")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
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

            VStack(spacing: 10) {
                Label {
                    Text("Child device can use a different iCloud account")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Label {
                    Text("Pairing works entirely on-device (no cloud required)")
                } icon: {
                    Image(systemName: "checkmark.shield")
                }
                .font(.caption)
                .foregroundColor(.green)
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
        .onAppear {
            checkCloudKitAndGenerate()
        }
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView()
        }
    }

    private func checkCloudKitAndGenerate() {
        cloudKitStatus = .checking

        Task {
            let status = await pairingService.checkCloudKitAvailability()

            await MainActor.run {
                if status {
                    self.cloudKitStatus = .available
                    // Automatically generate QR code when CloudKit is available
                    generateQRCode()
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

        #if DEBUG
        print("[ParentPairingView] 🔵 Starting QR code generation...")
        #endif

        Task {
            do {
                #if DEBUG
                print("[ParentPairingView] 🔵 Calling createPairingSession()...")
                #endif

                // Create pairing session with CloudKit sharing (async)
                let (sessionID, verificationToken, share, zoneID) = try await pairingService.createPairingSession()

                #if DEBUG
                print("[ParentPairingView] ✅ Pairing session created with CloudKit sharing: \(sessionID)")
                #endif

                // Generate QR code with session info and share
                if let ciImage = pairingService.generatePairingQRCode(
                    sessionID: sessionID,
                    verificationToken: verificationToken,
                    share: share,
                    zoneID: zoneID
                ) {
                    #if DEBUG
                    print("[ParentPairingView] ✅ QR code image generated successfully")
                    #endif

                    await MainActor.run {
                        self.qrCodeImage = convertCIImageToUIImage(ciImage)
                        self.isGenerating = false
                    }
                } else {
                    #if DEBUG
                    print("[ParentPairingView] ❌ Failed to generate QR code image")
                    #endif

                    await MainActor.run {
                        self.errorMessage = "Failed to generate QR code"
                        self.isGenerating = false
                    }
                }
            } catch {
                #if DEBUG
                print("[ParentPairingView] ❌ CRITICAL ERROR in QR code generation:")
                print("[ParentPairingView] Error type: \(type(of: error))")
                print("[ParentPairingView] Error description: \(error.localizedDescription)")
                print("[ParentPairingView] Full error: \(error)")
                #endif

                await MainActor.run {
                    self.isGenerating = false

                    // Handle specific error types with helpful messages
                    if case PairingError.deviceLimitReached = error {
                        self.showSubscriptionPaywall = true
                        self.errorMessage = nil
                    } else if case PairingError.networkError(let ckError) = error {
                        if let cloudKitError = ckError as? CKError, cloudKitError.code == .notAuthenticated {
                            self.cloudKitStatus = .notAuthenticated
                            self.errorMessage = nil
                        } else {
                            self.errorMessage = "iCloud connection error. Please check your internet connection and try again."
                        }
                    } else if let ckError = error as? CKError {
                        switch ckError.code {
                        case .notAuthenticated:
                            self.cloudKitStatus = .notAuthenticated
                            self.errorMessage = nil
                        case .networkUnavailable, .networkFailure:
                            self.errorMessage = "No internet connection. Please connect to the internet and try again."
                        case .quotaExceeded:
                            self.errorMessage = "iCloud storage is full. Please free up iCloud space in Settings."
                        default:
                            self.errorMessage = "iCloud error: \(ckError.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Unable to create pairing QR code. Please try again."
                    }
                }
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

struct ParentPairingView_Previews: PreviewProvider {
    static var previews: some View {
        ParentPairingView()
            .environmentObject(SubscriptionManager.shared)
    }
}
