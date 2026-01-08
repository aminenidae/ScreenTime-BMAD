import SwiftUI

struct ParentRemoteDashboardView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var viewModel = ParentRemoteViewModel()
    @State private var showingRefreshIndicator = false
    @State private var showingPairingView = false
    @State private var deviceCountBeforePairing = 0  // Track count to detect new pairing
    @State private var hasLoadedInitialData = false  // Prevent re-sync on navigation back
    @Environment(\.colorScheme) var colorScheme
    // Added @AppStorage for parent name as per UX/UI improvements Phase 1
    // Using device name as fallback since we couldn't find a specific parent name field
    @AppStorage("parentName") private var parentName: String = ""

    /// Returns true when exactly one child device is linked (skip carousel)
    private var isSingleDeviceMode: Bool {
        viewModel.linkedChildDevices.count == 1
    }

    /// The single linked device when in single-device mode
    private var singleDevice: RegisteredDevice? {
        isSingleDeviceMode ? viewModel.linkedChildDevices.first : nil
    }

    /// Show full-screen loading overlay during initial load
    private var showInitialLoadingOverlay: Bool {
        viewModel.isLoading && viewModel.linkedChildDevices.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                // App-themed gradient background
                AppTheme.Gradients.parentBackground(for: colorScheme)
                    .ignoresSafeArea()

                // Single device mode - show dashboard directly (outside ScrollView)
                if let device = singleDevice {
                    ChildUsageDashboardView(
                        devices: viewModel.linkedChildDevices,
                        selectedDeviceID: device.deviceID,
                        isEmbedded: true
                    )
                    .id(device.deviceID) // Force recreation when device changes
                    .overlay {
                        // Syncing overlay for single-device mode
                        if showingRefreshIndicator {
                            SyncingOverlayView(
                                deviceName: device.deviceName,
                                message: "Syncing with \(device.deviceName ?? "Device")..."
                            )
                            .transition(.opacity)
                        }
                    }
                } else if showInitialLoadingOverlay {
                    // Initial loading state - full screen overlay
                    SyncingOverlayView(
                        deviceName: nil,
                        message: "Loading Family Dashboard..."
                    )
                } else {
                    // Multi-device or empty state - use ScrollView
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header
                            VStack(spacing: 8) {
                                Text("Family Dashboard")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                // Personalized welcome message
                                Text("Welcome, \(parentName.isEmpty ? modeManager.deviceName : parentName)!")
                                    .font(.title2)

                                Text("Device: \(modeManager.deviceName)")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                            .padding(.top)

                            // Error message
                            if let errorMessage = viewModel.errorMessage {
                                ErrorBanner(message: errorMessage)
                                    .padding(.horizontal)
                            }

                            // Multiple devices - show carousel
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
                                // No devices linked - empty state
                                VStack(spacing: 16) {
                                    Image(systemName: "iphone.and.arrow.forward")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)

                                    Text("No Child Devices Linked")
                                        .font(.title3)
                                        .multilineTextAlignment(.center)

                                    Text("To get started, set up a child device and link it to this parent device using the pairing process.")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                        .multilineTextAlignment(.center)

                                    Button("Pair Devices") {
                                        showingPairingView = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.vibrantTeal)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                        .fill(AppTheme.Gradients.cardSubtle(for: colorScheme))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal)
                            }

                            Spacer()
                        }
                        .padding(.bottom)
                    }
                    .refreshable {
                        await refreshData()
                    }
                }
            }
            .onAppear {
                // Only load data on first appearance, not when navigating back from child views
                guard !hasLoadedInitialData else { return }
                hasLoadedInitialData = true
                Task {
                    await refreshData()
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

                // Show device name in center for single-device mode
                if let device = singleDevice {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(device.deviceName ?? "Device")
                                .font(.headline)
                            Text("Family Dashboard")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await refreshData()
                        }
                    }) {
                        if let device = singleDevice {
                            // Single device mode: show sync label with device name
                            Label(
                                "Sync with \(device.deviceName ?? "Device")",
                                systemImage: showingRefreshIndicator ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.down"
                            )
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                        } else {
                            // Multi-device mode: just show icon
                            Image(systemName: showingRefreshIndicator ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .imageScale(.large)
                        }
                    }
                    .disabled(showingRefreshIndicator)
                }
            }
            // Move the sheet outside of conditional views to ensure it's always available
            .sheet(isPresented: $showingPairingView) {
                ParentPairingView()
            }
            .onChange(of: showingPairingView) { isShowing in
                if isShowing {
                    // Capture device count before pairing view opens
                    deviceCountBeforePairing = viewModel.linkedChildDevices.count
                } else {
                    // When pairing view is dismissed, poll with retry to find new child device
                    Task {
                        // Use retry logic to wait for CloudKit sync (polls with exponential backoff)
                        await viewModel.loadLinkedChildDevicesWithRetry(
                            maxAttempts: 5,
                            initialDelay: 2.0,
                            previousCount: deviceCountBeforePairing
                        )
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func refreshData() async {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingRefreshIndicator = true
        }
        defer {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingRefreshIndicator = false
            }
        }

        await viewModel.loadLinkedChildDevices()

        // In single-device mode, also load the child's usage data
        if let device = viewModel.linkedChildDevices.first, viewModel.linkedChildDevices.count == 1 {
            await viewModel.loadChildData(for: device)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(AppTheme.errorRed)

            Text(message)
                .font(.caption)
                .foregroundColor(AppTheme.errorRed)

            Spacer()
        }
        .padding()
        .background(AppTheme.errorRed.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.small)
    }
}

// MARK: - Syncing Overlay View

private struct SyncingOverlayView: View {
    let deviceName: String?
    let message: String
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    @State private var iconScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Syncing card
            VStack(spacing: 20) {
                // Animated cloud sync icon
                ZStack {
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(iconScale)

                    Image(systemName: "icloud.and.arrow.down.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .scaleEffect(iconScale)
                }
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        iconScale = 1.1
                    }
                }

                VStack(spacing: 8) {
                    Text(message)
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Please wait while we fetch the latest data")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }

                // Animated progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isAnimating ? 1.0 : 0.5)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.card(for: colorScheme))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct ParentRemoteDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ParentRemoteDashboardView()
    }
}
