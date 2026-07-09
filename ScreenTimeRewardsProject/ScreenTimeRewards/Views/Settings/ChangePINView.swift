import SwiftUI

/// View for changing the parent PIN
struct ChangePINView: View {
    @Environment(\.dismiss) private var dismiss
    private let pinService = ParentPINService.shared

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isVerifyingCurrent = true

    var onSuccess: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isVerifyingCurrent {
                    currentPINSection
                } else {
                    newPINSection
                }

                Spacer()
            }
            .padding()
            .navigationTitle(isVerifyingCurrent ? "Verify PIN" : "New PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var currentPINSection: some View {
        VStack(spacing: 16) {
            Text("Enter your current PIN")
                .font(.headline)

            SecureField("Current PIN", text: $currentPIN)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Button("Verify") {
                verifyCurrent()
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentPIN.count < 4)
        }
    }

    private var newPINSection: some View {
        VStack(spacing: 16) {
            Text("Enter your new PIN")
                .font(.headline)

            SecureField("New PIN (4 digits)", text: $newPIN)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            SecureField("Confirm PIN", text: $confirmPIN)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Button("Save PIN") {
                savePIN()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newPIN.count < 4 || newPIN != confirmPIN)
        }
    }

    private func verifyCurrent() {
        if pinService.validatePIN(currentPIN) {
            isVerifyingCurrent = false
            currentPIN = ""
        } else {
            errorMessage = String(localized: "Incorrect PIN. Please try again.")
            showError = true
            currentPIN = ""
        }
    }

    private func savePIN() {
        guard newPIN.count == 4 else {
            errorMessage = String(localized: "PIN must be 4 digits")
            showError = true
            return
        }

        guard newPIN == confirmPIN else {
            errorMessage = String(localized: "PINs do not match")
            showError = true
            return
        }

        let result = pinService.setParentPIN(newPIN)
        switch result {
        case .success:
            onSuccess()
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
