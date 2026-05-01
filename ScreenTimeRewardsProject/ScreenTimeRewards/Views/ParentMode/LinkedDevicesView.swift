//
//  LinkedDevicesView.swift
//  ScreenTimeRewards
//
//  View for managing linked child devices.
//

import SwiftUI

/// View for managing linked child devices.
///
/// IMPORTANT: This view shares `ParentRemoteViewModel` with the parent dashboard
/// via `@EnvironmentObject` instead of owning a private `@StateObject`. Without
/// the shared instance, an unpair from the dashboard's carousel mutated only the
/// dashboard VM's `linkedChildDevices` array, while LinkedDevicesView's separate
/// VM rendered stale rows from `populateFromLocalCache` (Core Data still held the
/// row because NSPersistentCloudKitContainer hadn't reconciled the deleted zone
/// yet). User-facing symptom (Apr 30): dashboard shows 4 children, Settings →
/// Linked Devices keeps showing 5. Callers (ParentSettingsView sheet,
/// SubscriptionManagementView NavigationLink) must forward the parent's
/// `ParentRemoteViewModel` via `.environmentObject(...)`.
struct LinkedDevicesView: View {
    @EnvironmentObject var viewModel: ParentRemoteViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var showingPairingView = false
    @State private var deviceToUnpair: RegisteredDevice?
    @State private var showingUnpairConfirmation = false
    @State private var isUnpairing = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.linkedChildDevices.isEmpty {
                    ProgressView("Loading devices...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if viewModel.linkedChildDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Linked Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingPairingView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPairingView) {
                ParentPairingView()
            }
            .alert("Unpair Device", isPresented: $showingUnpairConfirmation, presenting: deviceToUnpair) { device in
                Button("Cancel", role: .cancel) { }
                Button("Unpair", role: .destructive) {
                    Task {
                        await unpairDevice(device)
                    }
                }
            } message: { device in
                Text("Are you sure you want to unpair \(device.childName ?? device.deviceName ?? "this device")? You will no longer be able to monitor their screen time.")
            }
            .task {
                await viewModel.loadLinkedChildDevices()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.vibrantTeal)

            Text("No Linked Devices")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            Text("Pair a child's device to start monitoring their screen time.")
                .font(.body)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingPairingView = true
            } label: {
                Label("Add Device", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Device List

    private var deviceListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.linkedChildDevices, id: \.deviceID) { device in
                    deviceRow(device)
                }
            }
            .padding()
        }
    }

    private func deviceRow(_ device: RegisteredDevice) -> some View {
        HStack(spacing: 16) {
            // Device Icon
            Image(systemName: deviceIcon(for: device))
                .font(.system(size: 28))
                .foregroundColor(statusColor(for: device))
                .frame(width: 44, height: 44)
                .background(statusColor(for: device).opacity(0.15))
                .cornerRadius(10)

            // Device Info
            VStack(alignment: .leading, spacing: 4) {
                Text(device.childName ?? device.deviceName ?? "Unknown Device")
                    .font(.headline)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(device.connectionStatus.displayText)
                    .font(.caption)
                    .foregroundColor(statusColor(for: device))

                if let lastSync = device.lastSyncDate {
                    Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            // Unpair Button
            Button {
                deviceToUnpair = device
                showingUnpairConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red.opacity(0.7))
            }
            .disabled(isUnpairing)
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func deviceIcon(for device: RegisteredDevice) -> String {
        let deviceType = device.deviceType?.lowercased() ?? ""
        if deviceType.contains("ipad") {
            return "ipad"
        } else if deviceType.contains("mac") {
            return "desktopcomputer"
        }
        return "iphone"
    }

    private func statusColor(for device: RegisteredDevice) -> Color {
        switch device.connectionStatus {
        case .active:
            return .green
        case .inactive:
            return .orange
        case .stale:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func unpairDevice(_ device: RegisteredDevice) async {
        isUnpairing = true
        defer { isUnpairing = false }

        let success = await viewModel.unpairChildDevice(device)

        if !success {
            // Show error - viewModel.errorMessage will be set
            print("[LinkedDevicesView] Failed to unpair device")
        }
    }
}

// MARK: - Preview

#Preview("Linked Devices View") {
    LinkedDevicesView()
        .environmentObject(ParentRemoteViewModel())
}
