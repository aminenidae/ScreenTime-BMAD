import SwiftUI

struct DeviceSelectionView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @State private var selectedMode: DeviceMode?
    @State private var deviceName = ""
    var showBackButton: Bool = false
    var onDeviceSelected: ((DeviceMode, String) -> Void)?
    var onBack: (() -> Void)?
    var initialMode: DeviceMode? = nil
    var initialDeviceName: String? = nil

    private var trimmedDeviceName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showBackButton {
                HStack {
                    Button(action: { onBack?() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Content Area - Main content wrapped in ScrollView
            ScrollView {
                VStack(spacing: 32) {
                // Headline Text Component
                Text("Welcome! Who will be using this device?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Text Grid Component - Device Cards
                    VStack(spacing: 16) {
                        // Parent Card
                        DeviceTypeCardView(
                            mode: .parentDevice,
                            isSelected: selectedMode == .parentDevice
                        ) {
                            selectedMode = .parentDevice
                        }

                        // Child Card
                        DeviceTypeCardView(
                            mode: .childDevice,
                            isSelected: selectedMode == .childDevice
                        ) {
                            selectedMode = .childDevice
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 512) // max-w-lg

                    // Text Field Component
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Name")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.textPrimary)

                        TextField("e.g., Mom's iPhone, Sam's iPad", text: $deviceName)
                            .font(.system(size: 16))
                            .padding(15)
                            .frame(height: 56)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(deviceName.isEmpty ? Color.red.opacity(0.5) : AppColors.border, lineWidth: 1)
                            )
                            .autocapitalization(.words)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 512) // max-w-lg
                    }
                    .padding(.bottom, 16) // Add bottom padding to ScrollView content
                }

                // Footer Area
                VStack(spacing: 16) {
                    // Single Button Component
                    Button(action: {
                        if let mode = selectedMode, !trimmedDeviceName.isEmpty {
                            if let callback = onDeviceSelected {
                                callback(mode, trimmedDeviceName)
                            } else {
                                modeManager.setDeviceMode(mode, deviceName: trimmedDeviceName)
                            }
                        }
                    }) {
                        Text("Get Started")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background((selectedMode != nil && !trimmedDeviceName.isEmpty) ? AppColors.primary : AppColors.primary.opacity(0.5))
                            .cornerRadius(12)
                    }
                    .disabled(selectedMode == nil || trimmedDeviceName.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 512) // max-w-lg
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AppColors.background
                .ignoresSafeArea()
        )
        .onAppear {
            if selectedMode == nil, let initialMode {
                selectedMode = initialMode
            }
            if deviceName.isEmpty, let initialDeviceName {
                deviceName = initialDeviceName
            }
        }
    }
}

// MARK: - Design Tokens
extension DeviceSelectionView {
    struct AppColors {
        static let primary = Color(hex: "#4A90E2")
        static let background = Color(hex: "#F9F9F9")
        static let surface = Color(hex: "#FFFFFF")
        static let textPrimary = Color(hex: "#4A4A4A")
        static let textSecondary = Color(hex: "#9B9B9B")
        static let border = Color(hex: "#e5e7eb")
        static let accentTeal = Color(hex: "#50E3C2")
        static let accentYellow = Color(hex: "#F8E71C")
    }
}

struct DeviceTypeCardView: View {
    let mode: DeviceMode
    let isSelected: Bool
    let action: () -> Void

    var iconName: String {
        mode == .parentDevice ? "person.badge.shield.checkmark" : "figure.2.and.child.holdinghands"
    }

    var iconColor: Color {
        if mode == .parentDevice {
            return DeviceSelectionView.AppColors.primary
        } else {
            return DeviceSelectionView.AppColors.accentTeal
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundColor(iconColor)

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DeviceSelectionView.AppColors.textPrimary)
                        .lineLimit(1)

                    Text(mode.description)
                        .font(.system(size: 14))
                        .foregroundColor(DeviceSelectionView.AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? DeviceSelectionView.AppColors.primary.opacity(0.1) : DeviceSelectionView.AppColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? DeviceSelectionView.AppColors.primary : DeviceSelectionView.AppColors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DeviceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSelectionView()
    }
}
