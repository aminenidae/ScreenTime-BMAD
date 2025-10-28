import SwiftUI

struct DeviceSelectionView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @State private var showingConfirmation = false
    @State private var selectedMode: DeviceMode?
    @State private var deviceName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Text("Welcome to ScreenTime Rewards")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Is this device for a Parent or a Child?")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                // Device Type Cards
                VStack(spacing: 20) {
                    DeviceTypeCardView(
                        mode: .parentDevice,
                        isSelected: selectedMode == .parentDevice
                    ) {
                        selectedMode = .parentDevice
                    }
                    
                    DeviceTypeCardView(
                        mode: .childDevice,
                        isSelected: selectedMode == .childDevice
                    ) {
                        selectedMode = .childDevice
                    }
                }
                .padding(.horizontal)
                
                // Device Name Input (Optional)
                if selectedMode != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Name (Optional)")
                            .font(.headline)
                        
                        TextField("e.g., Johnny's iPad", text: $deviceName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.words)
                    }
                    .padding(.horizontal)
                }
                
                // Continue Button
                if selectedMode != nil {
                    Button(action: {
                        showingConfirmation = true
                    }) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .confirmationDialog(
                        "Confirm Device Selection",
                        isPresented: $showingConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Confirm") {
                            if let mode = selectedMode {
                                modeManager.setDeviceMode(mode, deviceName: deviceName.isEmpty ? nil : deviceName)
                            }
                        }
                        
                        Button("Cancel", role: .cancel) {
                            // Do nothing
                        }
                    } message: {
                        if let mode = selectedMode {
                            Text("Set this device as a \(mode.displayName)?\n\n\(mode.description)")
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}

struct DeviceTypeCardView: View {
    let mode: DeviceMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: mode == .parentDevice ? "iphone.badge.play" : "iphone.and.arrow.forward")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        Text(mode.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}

struct DeviceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSelectionView()
    }
}