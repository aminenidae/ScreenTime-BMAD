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

struct PairingVerificationView_Previews: PreviewProvider {
    static var previews: some View {
        PairingVerificationView(
            parentDeviceName: "Parent's iPhone",
            verificationCode: "A1B2C3"
        )
    }
}