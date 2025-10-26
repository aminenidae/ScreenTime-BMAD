import SwiftUI

struct ModeSelectionView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var authService = AuthenticationService()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // App title and logo
                VStack(spacing: 16) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("ScreenTime Rewards")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Choose your mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Mode selection buttons
                VStack(spacing: 20) {
                    // Parent Mode button
                    Button(action: handleParentModeSelection) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.2.fill")
                                .font(.title)

                            VStack(alignment: .leading) {
                                Text("Parent Mode")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Protected - Full Access")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "faceid")
                                .font(.title)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                    }
                    .disabled(isAuthenticating)

                    // Child Mode button
                    Button(action: handleChildModeSelection) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.fill")
                                .font(.title)

                            VStack(alignment: .leading) {
                                Text("Child Mode")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Open Access - View Only")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                    }
                    .disabled(isAuthenticating)
                }
                .padding(.horizontal, 30)
            }

            // Loading overlay
            if isAuthenticating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleParentModeSelection() {
        isAuthenticating = true

        authService.authenticate(reason: "Access Parent Mode to manage app settings") { result in
            isAuthenticating = false

            switch result {
            case .success:
                sessionManager.enterParentMode(authenticated: true)

            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleChildModeSelection() {
        sessionManager.enterChildMode()
    }
}

struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView()
    }
}