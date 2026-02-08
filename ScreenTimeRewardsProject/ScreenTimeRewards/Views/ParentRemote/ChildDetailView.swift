import SwiftUI

struct ChildDetailView: View {
    let device: RegisteredDevice
    @ObservedObject var viewModel: ParentRemoteViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Device header
                DeviceHeaderView(device: device)

                // Usage summary for this device
                RemoteUsageSummaryView(viewModel: viewModel)
                    .padding(.horizontal)

                // Historical reports for this device
                HistoricalReportsView(viewModel: viewModel)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(device.deviceName ?? "Device Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load data for this specific device
            Task {
                await viewModel.loadChildData(for: device)
            }
        }
    }
}

private struct DeviceHeaderView: View {
    let device: RegisteredDevice

    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .font(.largeTitle)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName ?? "Unknown Device")
                    .font(.title2)
                    .fontWeight(.bold)

                if let deviceID = device.deviceID {
                    Text("ID: \(deviceID.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let regDate = device.registrationDate {
                    Text("Paired on \(regDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var deviceIcon: String {
        guard let type = device.deviceType else { return "iphone" }
        return type.lowercased().contains("ipad") ? "ipad" : "iphone"
    }
}