import SwiftUI

struct PairingVerificationView: View {
    let parentDeviceName: String
    let verificationCode: String

    var body: some View {
        ZStack {
            // Background
            Colors.backgroundOffWhite
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top App Bar
                HStack(spacing: 0) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Colors.blue)
                        .frame(width: 48, height: 48)

                    Text("Verify Your Device")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Colors.charcoal)
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 48) // Balance the icon
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Main Content Area
                VStack(spacing: 0) {
                    Spacer()

                    // Confirmation Code Display
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // First 3 digits
                            ForEach(0..<3, id: \.self) { index in
                                CodeDigitView(digit: getDigit(at: index))
                            }

                            // Separator
                            Text("-")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(Colors.charcoal)
                                .frame(width: 24, height: 64)

                            // Last 3 digits
                            ForEach(3..<6, id: \.self) { index in
                                CodeDigitView(digit: getDigit(at: index))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)

                    // Body Text
                    Text("Does the code above match the one shown on your child's device?")
                        .font(.system(size: 16))
                        .foregroundColor(Colors.mediumGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 320)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

                // Button Group
                VStack(spacing: 12) {
                    Button(action: {
                        // Complete pairing process
                    }) {
                        Text("Yes, It Matches")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Colors.green)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        // Cancel pairing
                    }) {
                        Text("Cancel Pairing")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Colors.mediumGray)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.clear)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .frame(maxWidth: 500)
                .padding(.bottom, 16)
            }
        }
    }

    private func getDigit(at index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        let digitIndex = verificationCode.index(verificationCode.startIndex, offsetBy: index)
        return String(verificationCode[digitIndex])
    }
}

// MARK: - Code Digit View
private struct CodeDigitView: View {
    let digit: String

    var body: some View {
        Text(digit)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(PairingVerificationView.Colors.charcoal)
            .frame(width: 48, height: 64)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(Color(hex: "E0E0E0"))
                    .padding(.top, 8),
                alignment: .bottom
            )
    }
}

// MARK: - Design Tokens
extension PairingVerificationView {
    struct Colors {
        static let backgroundOffWhite = Color(hex: "F9F9FB")
        static let charcoal = Color(hex: "2A2A2A")
        static let mediumGray = Color(hex: "8E8E93")
        static let green = Color(hex: "28A745")
        static let blue = Color(hex: "007AFF")
    }
}

struct PairingVerificationView_Previews: PreviewProvider {
    static var previews: some View {
        PairingVerificationView(
            parentDeviceName: "Parent's iPhone",
            verificationCode: "123456"
        )
    }
}