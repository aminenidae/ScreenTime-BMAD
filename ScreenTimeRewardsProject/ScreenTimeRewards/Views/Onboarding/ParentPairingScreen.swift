import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Combine
import CoreData

struct ParentPairingScreen: View {
    enum PairingStatus {
        case idle
        case waiting
        case success
    }

    @StateObject private var pairingService = DevicePairingService.shared
    @State private var qrCodeImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var status: PairingStatus = .idle
    @State private var hasAutoCompleted = false
    @State private var baselineDeviceIDs: Set<String>?
    @StateObject private var deviceObserver = PairedDeviceObserver()

    let deviceName: String
    let onBack: () -> Void
    let onSkip: () -> Void
    let onPaired: () -> Void

    private let context = CIContext()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            ParentOnboardingStepHeader(
                title: "Connect Devices",
                subtitle: "Generate a QR code and scan it from the child device.",
                step: 2,
                totalSteps: 2,
                onBack: onBack
            )

            pairingCard

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            } else {
                statusBanner
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    guard qrCodeImage != nil else { return }
                    status = .success
                    onPaired()
                }) {
                    Text("I've Connected the Child Device")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.lightCream)
                        .frame(maxWidth: 400)
                        .frame(height: 56)
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(14)
                }
                .disabled(qrCodeImage == nil)
                .opacity(qrCodeImage == nil ? 0.6 : 1)

                Button(action: onSkip) {
                    Text("Skip for Now")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }
            }
            .padding(.bottom, 16)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background(for: colorScheme))
        .task {
            if qrCodeImage == nil && !isGenerating {
                await generateQRCode()
            }
        }
        .onReceive(deviceObserver.$deviceIDs) { ids in
            if baselineDeviceIDs == nil {
                baselineDeviceIDs = ids
                return
            }

            guard let baseline = baselineDeviceIDs else { return }

            if ids.count > baseline.count && !hasAutoCompleted {
                status = .success
                hasAutoCompleted = true
                onPaired()
            }
        }
    }

    private var pairingCard: some View {
        VStack(spacing: 16) {
            Text("On the child device:")
                .font(.headline)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            Text("Open ScreenTime Rewards → Settings → Pair with Parent → Scan this code.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if isGenerating {
                ProgressView("Preparing secure QR code…")
                    .padding(.top, 24)
                    .padding(.bottom, 32)
            } else if let image = qrCodeImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                    )

                Button(action: { Task { await generateQRCode() } }) {
                    Label("Generate New Code", systemImage: "arrow.clockwise")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: { Task { await generateQRCode() } }) {
                    Label("Generate QR Code", systemImage: "qrcode")
                        .font(.headline)
                        .foregroundColor(AppTheme.lightCream)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.vibrantTeal)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 10)
        )
    }

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .success ? "checkmark.circle.fill" : "clock.badge.questionmark")
                .foregroundColor(status == .success ? .green : AppTheme.brandedText(for: colorScheme).opacity(0.7))
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 4) {
                Text(status == .success ? "Connected" : "Waiting for scan")
                    .font(.headline)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                if status == .success {
                    Text("You're all set—\(deviceName.isEmpty ? "this device" : deviceName) will show paired devices in the dashboard.")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                } else {
                    Text("We'll stay on this screen while you finish pairing. You can also skip and pair later from Settings.")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    @MainActor
    private func generateQRCode() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        status = .waiting

        do {
            let (sessionID, verificationToken, share, zoneID) = try await pairingService.createPairingSession()
            guard let ciImage = pairingService.generatePairingQRCode(
                sessionID: sessionID,
                verificationToken: verificationToken,
                share: share,
                zoneID: zoneID
            ) else {
                throw PairingError.invalidQRCode
            }

            let sharpImage = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            guard let cgImage = context.createCGImage(sharpImage, from: sharpImage.extent) else {
                throw PairingError.invalidQRCode
            }

            qrCodeImage = UIImage(cgImage: cgImage)
        } catch {
            errorMessage = error.localizedDescription
            status = .idle
        }

        isGenerating = false
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.sunnyYellow)

            Text(message)
                .font(.system(size: 15))
                .foregroundColor(Color.primary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.sunnyYellow.opacity(0.16))
        )
    }
}

private final class PairedDeviceObserver: ObservableObject {
    @Published private(set) var deviceIDs: Set<String> = []

    private let cloudKitService = CloudKitSyncService.shared
    private var cancellable: AnyCancellable?

    init() {
        startObserving()
        Task { await refreshDevices() }
    }

    deinit {
        cancellable?.cancel()
    }

    private func startObserving() {
        cancellable = NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                guard
                    let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event,
                    event.type == .import,
                    event.succeeded
                else { return }

                Task { await self?.refreshDevices() }
            }
    }

    private func refreshDevices() async {
        do {
            let devices = try await cloudKitService.fetchLinkedChildDevices()
            let ids = Set(devices.compactMap { $0.deviceID })
            await MainActor.run {
                self.deviceIDs = ids
            }
        } catch {
            #if DEBUG
            print("[PairedDeviceObserver] Failed to refresh devices: \(error)")
            #endif
        }
    }
}
