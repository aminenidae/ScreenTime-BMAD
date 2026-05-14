import SwiftUI
import Combine

struct ParentRemoteDashboardView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @EnvironmentObject var viewModel: ParentRemoteViewModel
    @State private var showingRefreshIndicator = false
    @State private var showingPairingView = false
    @State private var showingSettings = false
    @State private var showingChangePIN = false
    @State private var deviceCountBeforePairing = 0  // Track count to detect new pairing
    @State private var hasLoadedInitialData = false  // Prevent re-sync on navigation back
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    // Added @AppStorage for parent name as per UX/UI improvements Phase 1
    // Using device name as fallback since we couldn't find a specific parent name field
    @AppStorage("parentName") private var parentName: String = ""
    @AppStorage("parent_remote_last_refresh") private var lastRefreshEpoch: Double = 0
    @State private var nowTick: Date = Date()  // drives "Last synced Xm ago" relative text

    /// Auto-refresh only if data is older than this many seconds.
    private let autoRefreshStaleSeconds: TimeInterval = 3600  // 1 hour

    private var lastRefreshDate: Date? {
        lastRefreshEpoch > 0 ? Date(timeIntervalSince1970: lastRefreshEpoch) : nil
    }

    private var isDataStale: Bool {
        guard let last = lastRefreshDate else { return true }
        return Date().timeIntervalSince(last) > autoRefreshStaleSeconds
    }

    private var lastSyncedCaption: String? {
        guard let last = lastRefreshDate else { return nil }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours)h ago" }
        let days = hours / 24
        return "Updated \(days)d ago"
    }

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

                // Single device mode - embed ChildUsagePageView directly for proper viewModel observation
                if let device = singleDevice {
                    ChildUsagePageView(device: device, viewModel: viewModel)
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

                                if let caption = lastSyncedCaption {
                                    Text(caption)
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                }
                            }
                            .padding(.top)

                            // Error message
                            if let errorMessage = viewModel.errorMessage {
                                ErrorBanner(message: errorMessage)
                                    .padding(.horizontal)
                            }

                            // Devices present (from cache or fresh fetch) → show carousel.
                            // First load hasn't completed AND we have no cached devices → loading skeleton.
                            // First load completed AND list is empty → truthful "No Child Devices Linked".
                            if !viewModel.linkedChildDevices.isEmpty {
                                VStack(spacing: 16) {
                                    Text("Family Devices")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal)

                                    // 3D Card Carousel
                                    DeviceCardCarousel(devices: viewModel.linkedChildDevices)
                                }
                            } else if !viewModel.hasCompletedFirstLoad {
                                // First CK fetch still in flight; don't lie about "No devices".
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .padding(.top, 24)

                                    Text("Loading your family…")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                                .padding(.horizontal)
                            } else {
                                // Truthful empty state — CK fetch completed with zero paired children.
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

                                    // Recovery path for previously-paired children whose
                                    // CloudKit zones didn't surface (iCloud swap, deviceID
                                    // drift, transient sync delay).
                                    Button(action: {
                                        Task { await refreshData() }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: showingRefreshIndicator
                                                  ? "arrow.triangle.2.circlepath"
                                                  : "arrow.clockwise")
                                            Text("Refresh")
                                        }
                                        .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(showingRefreshIndicator)

                                    Text("Already paired a child? Make sure the child's device has opened Brain Coinz at least once and that you're signed into the same iCloud account used during pairing.")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 4)
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
                    await refreshData(isAuto: true)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active, hasLoadedInitialData, isDataStale else { return }
                Task { await refreshData(isAuto: true) }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                nowTick = date
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Add Child Device button at top-left as per UX/UI improvements Phase 1
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button(action: {
                            showingPairingView = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(.blue)
                        }
                        .accessibilityLabel("Add Child Device")

                        // Settings menu
                        Menu {
                            Button(action: {
                                showingChangePIN = true
                            }) {
                                Label("Change PIN", systemImage: "lock.rotation")
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .imageScale(.large)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                        .accessibilityLabel("Settings")
                    }
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
                            if let caption = lastSyncedCaption {
                                Text(caption)
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
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
            .sheet(isPresented: $showingChangePIN) {
                ChangePINView(onSuccess: {
                    #if DEBUG
                    print("[ParentRemoteDashboardView] PIN changed successfully")
                    #endif
                })
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewChildPaired"))) { _ in
                // When new child is detected, refresh all data (not just device list)
                Task {
                    #if DEBUG
                    print("[ParentRemoteDashboardView] 📣 NewChildPaired notification received - refreshing all data")
                    #endif
                    await viewModel.loadLinkedChildDevices()
                    // Load the newly paired child's data
                    if let firstChild = viewModel.linkedChildDevices.first {
                        await viewModel.loadChildData(for: firstChild)
                    }
                    lastRefreshEpoch = Date().timeIntervalSince1970
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func refreshData(isAuto: Bool = false) async {
        if !isAuto {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingRefreshIndicator = true
            }
        }
        defer {
            if !isAuto {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingRefreshIndicator = false
                }
            }
        }

        await viewModel.loadLinkedChildDevices()
        // Only force a per-child load on EXPLICIT refresh (pull-to-refresh,
        // refresh button). On `isAuto: true` (app launch / scenePhase active)
        // the user is on the Family Dashboard — cards render their tiles
        // from the on-disk cache. Triggering a full per-child load here
        // would clear+restore @Published vars for the auto-selected child,
        // cascading objectWillChange events that linger if the user then
        // taps into a child page. Let ChildUsageDashboardView.onAppear own
        // its own loadChildData when the user actually navigates.
        if !isAuto, let device = viewModel.selectedChildDevice ?? singleDevice {
            await viewModel.loadChildData(for: device, forceRefresh: true)
        }
        lastRefreshEpoch = Date().timeIntervalSince1970
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
            .environmentObject(ParentRemoteViewModel())
    }
}
