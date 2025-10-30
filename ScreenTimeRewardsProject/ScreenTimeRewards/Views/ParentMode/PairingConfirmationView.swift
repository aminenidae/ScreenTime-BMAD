import SwiftUI

struct PairingConfirmationView: View {
    let childDeviceName: String
    let verificationCode: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Pairing Request")
                .font(.title)
                .padding()
            
            Text("A child device is requesting to pair with your account:")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding()
            
            Text(childDeviceName)
                .font(.title2)
                .fontWeight(.bold)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            
            Text("Verification code:")
                .font(.subheadline)
                .padding(.top)
            
            Text(verificationCode)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            
            Text("Confirm that this matches the code shown on the child device")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Confirm Pairing") {
                // Confirm pairing
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            Button("Reject") {
                // Reject pairing
            }
            .padding()
        }
        .padding()
    }
}

struct PairingConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        PairingConfirmationView(
            childDeviceName: "Child's iPad",
            verificationCode: "A1B2C3"
        )
    }
}