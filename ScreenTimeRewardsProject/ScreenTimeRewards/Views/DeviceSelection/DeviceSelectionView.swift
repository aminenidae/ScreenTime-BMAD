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

    private var trimmedDeviceName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showBackButton {
                HStack {
                    Button(action: { onBack?() }) {
                        HStack(spacing: 4) { // To match Label structure
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold)) // Reduced from 18
                            Text("Back")
                                .font(.system(size: 16, weight: .semibold)) // Reduced from 18
                        }
                        .foregroundColor(AppTheme.vibrantTeal)
                        .padding(.vertical, 14) // Consistent with other buttons
                        .background(AppTheme.vibrantTeal.opacity(0.1))
                        .cornerRadius(AppTheme.CornerRadius.medium)
                        .textCase(.uppercase)
                    }
                    .buttonStyle(.plain) // Use .plain to allow background/padding
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.top, AppTheme.Spacing.small)
            }

            // Content Area - Main content wrapped in ScrollView
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xLarge) {
                    // Headline Text Component
                    Text("WHO WILL BE USING THIS DEVICE?")
                        .font(.system(size: 25, weight: .bold)) // Reduced from 28 by 3 pts
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppTheme.Spacing.regular)
                        .padding(.top, AppTheme.Spacing.regular)
                        .textCase(.uppercase)
                        .tracking(3)

                    // Image Card Grid - Device Selection
                    VStack(spacing: AppTheme.Spacing.regular) {
                        // Parent Device Card
                        DeviceImageCard(
                            imageName: "onboarding_0_2",
                            title: "Parent's Device",
                            subtitle: "Set Rules & Monitor Progress",
                            isSelected: selectedMode == .parentDevice,
                            colorScheme: colorScheme
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
                            isSelected: selectedMode == .childDevice,
                            colorScheme: colorScheme
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMode = .childDevice
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .frame(maxWidth: 512)

                    // Text Field Component - Dynamic based on selected mode
                    if let mode = selectedMode {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            Text(mode == .parentDevice ? "Parent's Name" : "Child's Name")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .textCase(.uppercase)

                            TextField(
                                mode == .parentDevice ? "e.g., MOM, DAD, SARAH" : "e.g., SAM, EMMA, ALEX",
                                text: $deviceName
                            )
                            .font(.system(size: 16))
                            .padding(AppTheme.Spacing.regular)
                            .frame(height: 56)
                            .background(AppTheme.card(for: colorScheme))
                            .cornerRadius(AppTheme.CornerRadius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                                    .stroke(deviceName.isEmpty ? AppTheme.error.opacity(0.5) : AppTheme.border(for: colorScheme), lineWidth: 1)
                            )
                            .autocapitalization(.words)
                        }
                        .padding(.horizontal, AppTheme.Spacing.regular)
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .frame(maxWidth: 512)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, AppTheme.Spacing.regular)
            }

            // Footer Area
            VStack(spacing: AppTheme.Spacing.regular) {
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background((selectedMode != nil && !trimmedDeviceName.isEmpty) ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.5))
                        .cornerRadius(AppTheme.CornerRadius.medium)
                        .textCase(.uppercase)
                }
                .disabled(selectedMode == nil || trimmedDeviceName.isEmpty)
                .padding(.horizontal, AppTheme.Spacing.regular)
                .padding(.vertical, AppTheme.Spacing.medium)
                .frame(maxWidth: 512)
            }
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AppTheme.background(for: colorScheme)
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
    let colorScheme: ColorScheme
    let action: () -> Void

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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold)) // Reduced from 20 by 3 pts
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                        .tracking(2)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .textCase(.uppercase)
                }
                .padding(AppTheme.Spacing.regular)

                // Selected checkmark overlay
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(AppTheme.vibrantTeal)
                                    .frame(width: 28, height: 28)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(AppTheme.Spacing.medium)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 180)
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? AppTheme.vibrantTeal.opacity(0.2) : Color.black.opacity(0.08),
                radius: isSelected ? AppTheme.Shadow.large.radius : AppTheme.Shadow.small.radius,
                x: 0,
                y: isSelected ? 4 : 2
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Remove old Design Tokens and DeviceTypeCardView (not used)


struct DeviceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSelectionView()
    }
}
