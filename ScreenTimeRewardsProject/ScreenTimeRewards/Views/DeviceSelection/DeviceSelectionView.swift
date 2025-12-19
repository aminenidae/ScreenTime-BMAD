import SwiftUI

struct DeviceSelectionView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @State private var selectedMode: DeviceMode?
    @State private var deviceName = ""
    @Environment(\.colorScheme) private var colorScheme
    var showBackButton: Bool = false
    var onDeviceSelected: ((DeviceMode, String) -> Void)?
    var onBack: (() -> Void)?
    var initialMode: DeviceMode? = nil
    var initialDeviceName: String? = nil

    private let tealColor = Color(red: 31/255, green: 134/255, blue: 111/255) // #1F866F

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
                VStack(spacing: 24) {
                    // Headline Text Component
                    Text("Who will be using this device?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Image Card Grid - Device Selection
                    VStack(spacing: 16) {
                        // Parent Device Card
                        DeviceImageCard(
                            imageName: "onboarding_0_2",
                            title: "Parent's Device",
                            subtitle: "Set Rules & Monitor Progress",
                            isSelected: selectedMode == .parentDevice
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMode = .parentDevice
                            }
                        }

                        // Child Device Card
                        DeviceImageCard(
                            imageName: "onboarding_0_3",
                            title: "Child's Device",
                            subtitle: "Earn Screen Time By Learning",
                            isSelected: selectedMode == .childDevice
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMode = .childDevice
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 512)

                    // Text Field Component - Dynamic based on selected mode
                    if let mode = selectedMode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode == .parentDevice ? "Parent's Name" : "Child's Name")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppColors.textPrimary)

                            TextField(
                                mode == .parentDevice ? "e.g., Mom, Dad, Sarah" : "e.g., Sam, Emma, Alex",
                                text: $deviceName
                            )
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
                        .frame(maxWidth: 512)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, 16)
            }

            // Footer Area
            VStack(spacing: 16) {
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
                        .background((selectedMode != nil && !trimmedDeviceName.isEmpty) ? tealColor : tealColor.opacity(0.5))
                        .cornerRadius(12)
                }
                .disabled(selectedMode == nil || trimmedDeviceName.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 512)
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

// MARK: - Device Image Card Component

private struct DeviceImageCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    private let tealColor = Color(red: 31/255, green: 134/255, blue: 111/255)

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background image
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(16)

                // Selected checkmark overlay
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(tealColor)
                                    .frame(width: 28, height: 28)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 180)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? tealColor : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? tealColor.opacity(0.2) : Color.black.opacity(0.08),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: isSelected ? 4 : 2
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
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
