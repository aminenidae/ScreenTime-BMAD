import SwiftUI
import CoreData

struct ChildDeviceSelectorView: View {
    @ObservedObject var viewModel: ParentRemoteViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Linked Devices")
                .font(.headline)
            
            if viewModel.linkedChildDevices.isEmpty {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.gray)
                    Text("No linked devices found")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.linkedChildDevices, id: \.deviceID) { device in
                            ChildDeviceCardView(
                                device: device,
                                isSelected: device.deviceID == viewModel.selectedChildDevice?.deviceID
                            ) {
                                Task {
                                    await viewModel.loadChildData(for: device)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}

private struct ChildDeviceCardView: View {
    let device: RegisteredDevice
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(isSelected ? .white : .blue)
                    
                    Spacer()
                    
                    if let lastSync = device.lastSyncDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(timeAgo(since: lastSync))
                                .font(.caption)
                                .foregroundColor(isSelected ? .white : .secondary)
                        }
                    }
                }
                
                Text(device.deviceName ?? "Unknown Device")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let childName = device.childName {
                    Text(childName)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white : .secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Circle()
                        .fill(device.isActive == true ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(device.isActive == true ? "Active" : "Inactive")
                        .font(.caption)
                }
            }
            .frame(width: 140, height: 100)
            .padding()
            .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgo(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ChildDeviceSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock view model for preview
        let viewModel = ParentRemoteViewModel()
        
        // Note: In a real preview, we would need a proper Core Data context
        // For now, we'll just show the view without mock data
        
        return ChildDeviceSelectorView(viewModel: viewModel)
            .padding()
    }
}