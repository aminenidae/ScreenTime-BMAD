import SwiftUI

struct ParentRemoteDashboardView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var showingRefreshIndicator = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Parent Remote Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Welcome, Parent!")
                            .font(.title2)
                        
                        Text("Device: \(modeManager.deviceName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Child Device Selector
                    ChildDeviceSelectorView(viewModel: viewModel)
                        .padding(.horizontal)
                    
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
                    
                    // Main content (only show when a device is selected)
                    if viewModel.selectedChildDevice != nil {
                        // Usage Summary
                        RemoteUsageSummaryView(viewModel: viewModel)
                            .padding(.horizontal)
                        
                        // App Configuration
                        RemoteAppConfigurationView(viewModel: viewModel)
                            .padding(.horizontal)
                        
                        // Historical Reports
                        HistoricalReportsView(viewModel: viewModel)
                            .padding(.horizontal)
                    } else if !viewModel.linkedChildDevices.isEmpty {
                        // No device selected but devices exist
                        VStack(spacing: 16) {
                            Image(systemName: "hand.tap")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                            
                            Text("Select a child device to view data")
                                .font(.title3)
                                .multilineTextAlignment(.center)
                            
                            Text("Choose a device from the selector above to see usage data, configure apps, and view reports.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else if !viewModel.isLoading {
                        // No devices linked
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
                            
                            Button("Learn How to Pair Devices") {
                                // TODO: Navigate to pairing instructions
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
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
            .navigationTitle("Remote Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
        }
    }
    
    private func refreshData() async {
        showingRefreshIndicator = true
        defer { showingRefreshIndicator = false }
        
        await viewModel.loadLinkedChildDevices()
        
        if let selectedDevice = viewModel.selectedChildDevice {
            await viewModel.loadChildData(for: selectedDevice)
        }
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