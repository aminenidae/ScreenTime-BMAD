# Phase 5 Implementation Plan: Device Pairing

## Overview
Phase 5 focuses on implementing device pairing functionality to enable seamless parent-child device connections using CloudKit sharing. This phase will establish the foundation for cross-account data synchronization.

## Goals
1. Create seamless parent-child device pairing experience
2. Implement QR code based pairing system
3. Enable CloudKit share creation and acceptance
4. Provide pairing verification and confirmation

## Implementation Tasks

### Task 5.1: Design Pairing QR Code System (2 hours)
**File:** `ScreenTimeRewards/Services/DevicePairingService.swift` (NEW)

**Implementation:**
```swift
import Foundation
import CoreImage
import CloudKit

class DevicePairingService {
    static let shared = DevicePairingService()
    
    struct PairingPayload: Codable {
        let shareURL: String
        let parentDeviceID: String
        let verificationToken: String
        let timestamp: Date
    }
    
    /// Generate QR code for pairing
    func generatePairingQRCode(share: CKShare) -> CIImage? {
        let payload = PairingPayload(
            shareURL: share.url?.absoluteString ?? "",
            parentDeviceID: DeviceModeManager.shared.deviceID,
            verificationToken: UUID().uuidString,
            timestamp: Date()
        )
        
        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(jsonString.data(using: .ascii), forKey: "inputMessage")
        qrFilter?.setValue("Q", forKey: "inputCorrectionLevel")
        
        return qrFilter?.outputImage
    }
    
    /// Parse scanned QR code
    func parsePairingQRCode(_ image: CIImage) -> PairingPayload? {
        // Implementation for parsing QR code
        // ... to be implemented
        return nil
    }
}
```

**Acceptance Criteria:**
- ✅ QR code generation with pairing payload
- ✅ JSON encoding of pairing data
- ✅ QR code scanning capability
- ✅ Payload parsing and validation

### Task 5.2: Implement Parent Invitation Flow (4 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift` (extend)
- `ScreenTimeRewards/Views/ParentMode/ParentPairingView.swift` (NEW)

**Implementation:**
```swift
// DevicePairingService extension
extension DevicePairingService {
    /// Create CloudKit share for child device
    func createChildDeviceShare() async throws -> CKShare {
        let container = CKContainer.default()
        let database = container.privateCloudDatabase
        
        // Create share
        let share = CKShare()
        share[CKShare.SystemFieldKey.title] = "ScreenTime Rewards Child Device"
        
        // Add share to database
        let shareOperation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        shareOperation.qualityOfService = .userInitiated
        
        return try await withCheckedThrowingContinuation { continuation in
            shareOperation.modifyRecordsCompletionBlock = { records, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let share = records?.first as? CKShare {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: NSError(domain: "PairingError", code: -1, 
                                                        userInfo: [NSLocalizedDescriptionKey: "Failed to create share"]))
                }
            }
            
            database.add(shareOperation)
        }
    }
}
```

**ParentPairingView Implementation:**
```swift
import SwiftUI
import CoreImage

struct ParentPairingView: View {
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var qrCodeImage: Image?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Child Device")
                .font(.title)
                .padding()
            
            if let qrCodeImage = qrCodeImage {
                qrCodeImage
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                
                Text("Show this QR code to your child's device")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if isGenerating {
                ProgressView("Generating pairing code...")
                    .padding()
            } else {
                Button("Generate Pairing Code") {
                    generatePairingCode()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            generatePairingCode()
        }
    }
    
    private func generatePairingCode() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let share = try await pairingService.createChildDeviceShare()
                if let qrImage = pairingService.generatePairingQRCode(share: share) {
                    // Convert CIImage to SwiftUI Image
                    let uiImage = UIImage(ciImage: qrImage)
                    DispatchQueue.main.async {
                        self.qrCodeImage = Image(uiImage: uiImage)
                        self.isGenerating = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to generate QR code"
                        self.isGenerating = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create pairing share: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }
}
```

**Acceptance Criteria:**
- ✅ CloudKit share creation
- ✅ QR code generation with share information
- ✅ Parent pairing view UI
- ✅ Error handling for share creation

### Task 5.3: Build Child Device Acceptance Flow (4 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift` (extend)
- `ScreenTimeRewards/Views/ChildMode/ChildPairingView.swift` (NEW)

**Implementation:**
```swift
// DevicePairingService extension
extension DevicePairingService {
    /// Accept CloudKit share from parent
    func acceptParentShare(from payload: PairingPayload) async throws {
        guard let url = URL(string: payload.shareURL) else {
            throw NSError(domain: "PairingError", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid share URL"])
        }
        
        let container = CKContainer.default()
        
        // Accept share
        return try await withCheckedThrowingContinuation { continuation in
            container.acceptShare(with: url) { acceptedShare, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let acceptedShare = acceptedShare {
                    // Successfully accepted share
                    // Save parent device ID for reference
                    UserDefaults.standard.set(payload.parentDeviceID, 
                                            forKey: "parentDeviceID")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "PairingError", code: -1, 
                                                        userInfo: [NSLocalizedDescriptionKey: "Failed to accept share"]))
                }
            }
        }
    }
}
```

**ChildPairingView Implementation:**
```swift
import SwiftUI
import AVFoundation

struct ChildPairingView: View {
    @StateObject private var pairingService = DevicePairingService.shared
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var isPairing = false
    @State private var showVerification = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Pair with Parent Device")
                .font(.title)
                .padding()
            
            Text("Scan the QR code shown on your parent's device")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Scan QR Code") {
                requestCameraAccess()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            if isPairing {
                ProgressView("Pairing with parent device...")
                    .padding()
            }
        }
        .sheet(isPresented: $isScanning) {
            QRCodeScannerView { result in
                handleScanResult(result)
            }
        }
        .alert("Pairing Successful", isPresented: $showVerification) {
            Button("Continue") {
                // Navigate to child dashboard
            }
        } message: {
            Text("Successfully paired with parent device!")
        }
    }
    
    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScanning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isScanning = true
                    } else {
                        errorMessage = "Camera access is required to scan QR codes"
                    }
                }
            }
        default:
            errorMessage = "Please enable camera access in Settings to scan QR codes"
        }
    }
    
    private func handleScanResult(_ result: Result<DevicePairingService.PairingPayload, Error>) {
        isScanning = false
        
        switch result {
        case .success(let payload):
            pairWithParent(payload: payload)
        case .failure(let error):
            errorMessage = "Failed to scan QR code: \(error.localizedDescription)"
        }
    }
    
    private func pairWithParent(payload: DevicePairingService.PairingPayload) {
        isPairing = true
        errorMessage = nil
        
        Task {
            do {
                try await pairingService.acceptParentShare(from: payload)
                DispatchQueue.main.async {
                    self.isPairing = false
                    self.showVerification = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isPairing = false
                    self.errorMessage = "Failed to pair with parent: \(error.localizedDescription)"
                }
            }
        }
    }
}
```

**Acceptance Criteria:**
- ✅ QR code scanning capability
- ✅ CloudKit share acceptance
- ✅ Child pairing view UI
- ✅ Camera permission handling

### Task 5.4: Add CloudKit Share Creation/Acceptance (3 hours)
**File:** `ScreenTimeRewards/Services/DevicePairingService.swift` (extend)

**Implementation:**
```swift
// Additional methods for share management
extension DevicePairingService {
    /// Get parent device ID for child device
    func getParentDeviceID() -> String? {
        return UserDefaults.standard.string(forKey: "parentDeviceID")
    }
    
    /// Check if device is already paired
    func isPaired() -> Bool {
        return getParentDeviceID() != nil
    }
    
    /// Unpair device
    func unpairDevice() {
        UserDefaults.standard.removeObject(forKey: "parentDeviceID")
        // Additional cleanup as needed
    }
}
```

**Acceptance Criteria:**
- ✅ Parent device ID storage and retrieval
- ✅ Pairing status checking
- ✅ Device unpairing capability

### Task 5.5: Create Pairing Verification UI (3 hours)
**Files:**
- `ScreenTimeRewards/Views/ChildMode/PairingVerificationView.swift` (NEW)
- `ScreenTimeRewards/Views/ParentMode/PairingConfirmationView.swift` (NEW)

**Implementation:**
```swift
import SwiftUI

struct PairingVerificationView: View {
    let parentDeviceName: String
    let verificationCode: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Pairing Verification")
                .font(.title)
                .padding()
            
            Text("Verify this code matches the one on your parent's device:")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding()
            
            Text(verificationCode)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            
            Text("If the codes match, tap Confirm to complete pairing")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Confirm Pairing") {
                // Complete pairing process
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            Button("Cancel") {
                // Cancel pairing
            }
            .padding()
        }
        .padding()
    }
}
```

**Acceptance Criteria:**
- ✅ Verification code display
- ✅ Visual matching confirmation
- ✅ Pairing confirmation flow
- ✅ Cancel option

## Phase 5 Deliverables

- ✅ QR code pairing system
- ✅ Parent invitation flow
- ✅ Child device acceptance flow
- ✅ CloudKit share creation/acceptance
- ✅ Pairing verification UI
- [ ] Unit tests (>80% coverage)
- [ ] Integration tests

## Technical Considerations

### Cross-Account Sharing Notes:
- Child must accept the share - iOS will prompt with parent's Apple ID
- For children under 13: Parent must approve on their device first
- Internet required: Both devices need connectivity during pairing
- One-time setup: After acceptance, sync happens automatically
- Revocable: Either party can stop sharing at any time

### Security Considerations:
- Verification tokens for pairing validation
- Secure storage of parent device IDs
- Proper error handling for failed pairings
- User consent for CloudKit sharing

### Performance Considerations:
- Efficient QR code generation and scanning
- Minimal impact on app performance during pairing
- Proper handling of network failures
- Timeout handling for pairing operations

## Dependencies
- CloudKitSyncService (already implemented in Phase 2)
- DeviceModeManager (already implemented)
- CloudKit capabilities (already configured)

## Estimated Timeline
- Implementation: 3-4 days
- Testing: 1-2 days
- Total: 4-6 days