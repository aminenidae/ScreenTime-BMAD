import SwiftUI
import AVFoundation
import UIKit

// MARK: - Design Tokens
fileprivate struct Colors {
    static let primary = Color(hex: "#fac638")
    static let backgroundLight = Color(hex: "#f8f8f5")
    static let backgroundDark = Color(hex: "#231e0f")
}

struct QRCodeScannerView: View {
    typealias CompletionHandler = (Result<String, Error>) -> Void

    let completion: CompletionHandler
    @Environment(\.dismiss) private var dismiss
    @State private var torchOn = false
    @State private var showSuccessModal = false
    @State private var scannedCode: String?

    var body: some View {
        ZStack {
            // Camera Preview Background
            CameraPreviewView(completion: handleScanResult, torchOn: $torchOn)
                .ignoresSafeArea()

            // Semi-transparent Overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // UI Content
            VStack(spacing: 0) {
                // Top App Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Spacer()

                // Main Content
                VStack(spacing: 16) {
                    Text("Link Child's Device")
                        .font(.custom("Lexend", size: 24).weight(.semibold))
                        .foregroundColor(.white)

                    // Scanning Frame
                    ZStack {
                        // Base border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)

                        // Corner brackets
                        CornerBrackets()
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 16)

                    Text("Position the code inside the frame.")
                        .font(.custom("Lexend", size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)

                Spacer()

                // Bottom Camera Controls
                HStack(spacing: 24) {
                    Button(action: { torchOn.toggle() }) {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }

            // Success Modal
            if showSuccessModal {
                SuccessModal(onDismiss: {
                    showSuccessModal = false
                    if let code = scannedCode {
                        completion(.success(code))
                    }
                })
                .transition(.opacity)
                .zIndex(20)
            }
        }
    }

    private func handleScanResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let code):
            scannedCode = code
            withAnimation {
                showSuccessModal = true
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

// MARK: - Corner Brackets
private struct CornerBrackets: View {
    var body: some View {
        ZStack {
            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: 48, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 48))
            }
            .stroke(Colors.primary, lineWidth: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -4, y: -4)

            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: -48, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 48))
            }
            .stroke(Colors.primary, lineWidth: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 4, y: -4)

            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: 0, y: -48))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 48, y: 0))
            }
            .stroke(Colors.primary, lineWidth: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .offset(x: -4, y: 4)

            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: 0, y: -48))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: -48, y: 0))
            }
            .stroke(Colors.primary, lineWidth: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 4, y: 4)
        }
    }
}

// MARK: - Success Modal
private struct SuccessModal: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .blur(radius: 4)

            VStack(spacing: 0) {
                // Success Icon
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green.opacity(0.8))
                }
                .padding(.bottom, 16)

                Text("Device Linked!")
                    .font(.custom("Lexend", size: 20).weight(.bold))
                    .foregroundColor(.white)

                Text("You've successfully linked Leo's device.")
                    .font(.custom("Lexend", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.custom("Lexend", size: 16).weight(.bold))
                        .foregroundColor(Colors.backgroundDark)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Colors.primary)
                        .cornerRadius(8)
                }
                .padding(.top, 24)
            }
            .padding(24)
            .frame(maxWidth: 400)
            .background(Colors.backgroundDark)
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Camera Preview
private struct CameraPreviewView: UIViewControllerRepresentable {
    typealias CompletionHandler = (Result<String, Error>) -> Void

    let completion: CompletionHandler
    @Binding var torchOn: Bool

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.setTorch(torchOn)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    class Coordinator: NSObject, QRScannerControllerDelegate {
        let completion: CompletionHandler

        init(completion: @escaping CompletionHandler) {
            self.completion = completion
        }

        func didScanQRCode(_ code: String) {
            completion(.success(code))
        }

        func didFailWithError(_ error: Error) {
            completion(.failure(error))
        }
    }
}

protocol QRScannerControllerDelegate: AnyObject {
    func didScanQRCode(_ code: String)
    func didFailWithError(_ error: Error)
}

class QRScannerController: UIViewController {
    weak var delegate: QRScannerControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        checkCameraAuthorization()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSession?.startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
        setTorch(false)
    }

    func setTorch(_ on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error)")
        }
    }

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -2,
                                                               userInfo: [NSLocalizedDescriptionKey: "Camera access denied"]))
                    }
                }
            }
        default:
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -3,
                                             userInfo: [NSLocalizedDescriptionKey: "Please enable camera access in Settings"]))
        }
    }

    private func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "No camera available"]))
            return
        }

        self.captureDevice = captureDevice

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
            delegate?.didFailWithError(error)
            return
        }

        let output = AVCaptureMetadataOutput()
        captureSession = AVCaptureSession()

        guard let captureSession = captureSession else {
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "Failed to create capture session"]))
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "Failed to add input to capture session"]))
            return
        }

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        } else {
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -1,
                                             userInfo: [NSLocalizedDescriptionKey: "Failed to add output to capture session"]))
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer!)

        captureSession.startRunning()
    }
}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.stopRunning()
        
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            delegate?.didFailWithError(NSError(domain: "QRScannerError", code: -1, 
                                             userInfo: [NSLocalizedDescriptionKey: "Failed to read QR code"]))
            return
        }
        
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.didScanQRCode(stringValue)
    }
}