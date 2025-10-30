import SwiftUI
import AVFoundation
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    typealias CompletionHandler = (Result<String, Error>) -> Void
    
    let completion: CompletionHandler
    
    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
    
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