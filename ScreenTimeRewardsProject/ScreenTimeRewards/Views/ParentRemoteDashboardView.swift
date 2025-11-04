import SwiftUI

struct ParentRemoteDashboardView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var showingRefreshIndicator = false
    @State private var showingPairingView = false
    // Added @AppStorage for parent name as per UX/UI improvements Phase 1
    // Using device name as fallback since we couldn't find a specific parent name field
    @AppStorage("parentName") private var parentName: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Soft gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),  // Very light blue
                        Color(red: 0.98, green: 0.95, blue: 1.0),  // Very light purple
                        Color(red: 1.0, green: 0.97, blue: 0.98)   // Very light pink
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Family Dashboard") // Changed from "Parent Remote Dashboard" as per UX/UI improvements Phase 1
                                .font(.largeTitle)
                                .fontWeight(.bold)

                            // Personalized welcome message as per UX/UI improvements Phase 1
                            Text("Welcome, \(parentName.isEmpty ? modeManager.deviceName : parentName)!")
                                .font(.title2)

                            Text("Device: \(modeManager.deviceName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top)
                    
                    // Loading indicator
                    if viewModel.isLoading {
                        ProgressView("Loading data...")
                            .padding()
                    }
                    
                    // Error message
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(message: errorMessage)
                            .padding(.horizontal)
                    }
                    
                    // 3D Card Carousel - Level 1 Navigation
                    if !viewModel.linkedChildDevices.isEmpty {
                        VStack(spacing: 16) {
                            Text("Family Devices")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            // 3D Card Carousel
                            DeviceCardCarousel(devices: viewModel.linkedChildDevices)
                        }
                    } else if !viewModel.isLoading {
                        // No devices linked - keep existing empty state
                        VStack(spacing: 16) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("No Child Devices Linked")
                                .font(.title3)
                                .multilineTextAlignment(.center)
                            
                            Text("To get started, set up a child device and link it to this parent device using the pairing process.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Pair Devices") {
                                showingPairingView = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.7),
                                            Color.gray.opacity(0.1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                        Spacer()
                    }
                    .padding(.bottom)
                }
                .refreshable {
                    await refreshData()
                }
                .onAppear {
                    Task {
                        await refreshData()
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Add Child Device button at top-left as per UX/UI improvements Phase 1
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingPairingView = true
                    }) {
                        Image(systemName: "plus.circle.fill") // Changed from "iphone.gen2.badge.plus" as per UX/UI improvements Phase 1 Update
                            .imageScale(.large)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Add Child Device")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await refreshData()
                        }
                    }) {
                        Image(systemName: showingRefreshIndicator ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .imageScale(.large)
                    }
                    .disabled(showingRefreshIndicator)
                }
            }
            // Move the sheet outside of conditional views to ensure it's always available
            .sheet(isPresented: $showingPairingView) {
                ParentPairingView()
            }
            .onChange(of: showingPairingView) { isShowing in
                // When pairing view is dismissed, refresh to check for newly paired devices
                if !isShowing {
                    Task {
                        // Add a small delay to allow CloudKit sync to complete
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        await refreshData()
                    }
                }
            }
        }
    }
    
    private func refreshData() async {
        showingRefreshIndicator = true
        defer { showingRefreshIndicator = false }
        
        await viewModel.loadLinkedChildDevices()
    }
}

private struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ParentRemoteDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ParentRemoteDashboardView()
    }
}
