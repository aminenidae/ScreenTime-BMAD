import SwiftUI
import CoreImage.CIFilterBuiltins
import CloudKit
import UIKit

struct ParentPairingView: View {
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var qrCodeImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var cloudKitAvailable = false

    var body: some View {
        VStack(spacing: 30) {
            Text("Add Child Device")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if isGenerating {
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
    }

    private func checkCloudKitAndGenerate() {
        // No CloudKit check needed for local-only pairing
        cloudKitAvailable = true
        generateQRCode()
    }

    private func generateQRCode() {
        isGenerating = true
        errorMessage = nil
        qrCodeImage = nil

        Task {
            do {
                // Create pairing session with CloudKit sharing (async)
                let (sessionID, verificationToken, share, zoneID) = try await pairingService.createPairingSession()

                #if DEBUG
                print("[ParentPairingView] Pairing session created with CloudKit sharing: \(sessionID)")
                #endif

                // Generate QR code with session info and share
                if let ciImage = pairingService.generatePairingQRCode(
                    sessionID: sessionID,
                    verificationToken: verificationToken,
                    share: share,
                    zoneID: zoneID
                ) {
                    await MainActor.run {
                        self.qrCodeImage = convertCIImageToUIImage(ciImage)
                        self.isGenerating = false
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to generate QR code"
                        self.isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to create pairing session: \(error.localizedDescription)"
                    self.isGenerating = false
                }
                
                #if DEBUG
                print("[ParentPairingView] ❌ Failed to create pairing session: \(error)")
                #endif
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
    }
}
