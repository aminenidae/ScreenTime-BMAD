import SwiftUI
import CoreData

/// Full usage dashboard view with horizontal swipe navigation
/// Shown after tapping a device card from the carousel
struct ChildUsageDashboardView: View {
    let devices: [RegisteredDevice]
    let selectedDeviceID: String?

    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var currentIndex: Int = 0
    @Environment(\.colorScheme) var colorScheme
    
    init(devices: [RegisteredDevice], selectedDeviceID: String?) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        
        // Find initial index based on selected device
        if let id = selectedDeviceID,
           let index = devices.firstIndex(where: { $0.deviceID == id }) {
            _currentIndex = State(initialValue: index)
        }
    }
    
    var currentDevice: RegisteredDevice? {
        guard currentIndex < devices.count else { return nil }
        return devices[currentIndex]
    }
    
    var body: some View {
        ZStack {
            // App-themed gradient background
            AppTheme.Gradients.parentBackground(for: colorScheme)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(devices.enumerated()), id: \.element.deviceID) { index, device in
                    ChildUsagePageView(device: device, viewModel: viewModel)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // Hide page dots, use custom navigation
        }
        .navigationTitle(currentDevice?.deviceName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Custom navigation header showing current device
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation {
                            currentIndex = max(0, currentIndex - 1)
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(currentIndex > 0 ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
                    }
                    .disabled(currentIndex == 0)

                    VStack(spacing: 2) {
                        Text(currentDevice?.deviceName ?? "Device")
                            .font(.headline)

                        Text("\(currentIndex + 1) of \(devices.count)")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }

                    Button(action: {
                        withAnimation {
                            currentIndex = min(devices.count - 1, currentIndex + 1)
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(currentIndex < devices.count - 1 ? AppTheme.vibrantTeal : AppTheme.textSecondary(for: colorScheme))
                    }
                    .disabled(currentIndex >= devices.count - 1)
                }
            }
        }
        .onAppear {
            Task {
                await loadAllDeviceData()
            }
        }
    }
    
    private func loadAllDeviceData() async {
        await viewModel.loadLinkedChildDevices()
    }
}

/// Single page showing complete usage data for one child
struct ChildUsagePageView: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Reuse existing components from your current implementation
                RemoteUsageSummaryView(viewModel: viewModel)
                    .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal)
                
                HistoricalReportsView(viewModel: viewModel)
                    .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .onAppear {
            Task {
                // Load data for this specific device
                await viewModel.loadChildData(for: device)
            }
        }
    }
}

struct ChildUsageDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: Preview requires Core Data context which is not available here
        // For now, we'll just show a placeholder
        
        return Text("Child Usage Dashboard")
    }
}
