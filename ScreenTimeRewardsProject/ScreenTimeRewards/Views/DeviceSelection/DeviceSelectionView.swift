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
                                .font(.system(size: 14, weight: .semibold)) // Reduced by 2 pts
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold)) // Reduced by 2 pts
                        }
                        .foregroundColor(AppTheme.vibrantTeal)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xLarge) {
                        // Headline Text Component
                        Text("Where does your child spend screen time?")
                            .font(.system(size: 25, weight: .bold)) // Reduced from 28 by 3 pts
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppTheme.Spacing.regular)
                            .padding(.top, AppTheme.Spacing.regular)

                        // Explanation text
                        Text("Setup takes about 3 minutes. Pick what fits today — you can add the other device later.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.regular)
                            .padding(.top, AppTheme.Spacing.small)

                        // Tap instruction
                        Text("Tap one to begin")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                            .tracking(1)
                            .padding(.top, AppTheme.Spacing.medium)

                        // Image Card Grid - Device Selection
                        // Cards describe the parent's SITUATION, not device ownership —
                        // answerable even when the parent installs alone on their own phone.
                        VStack(spacing: AppTheme.Spacing.regular) {
                            // Child uses THIS device → child flow
                            DeviceImageCard(
                                imageName: "onboarding_0_3",
                                title: String(localized: "On this device"),
                                subtitle: String(localized: "Set up learning goals and app locks right here."),
                                isSelected: selectedMode == .childDevice,
                                colorScheme: colorScheme
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedMode = .childDevice
                                }
                            }

                            // Child has their own device → this phone becomes the remote
                            DeviceImageCard(
                                imageName: "onboarding_0_2",
                                title: String(localized: "On their own device"),
                                subtitle: String(localized: "Turn this phone into your remote dashboard."),
                                isSelected: selectedMode == .parentDevice,
                                colorScheme: colorScheme
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedMode = .parentDevice
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.regular)
                        .frame(maxWidth: 512)

                        // Text Field Component - Dynamic based on selected mode.
                        // Optional by design: never block Continue on a name, never style
                        // an empty field as an error (funnel data showed this gate cost installs).
                        if let mode = selectedMode {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                Text(mode == .parentDevice ? String(localized: "Your name (optional)") : String(localized: "Child's name (optional)"))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                                TextField(
                                    mode == .parentDevice ? String(localized: "e.g. Mom, Dad, Sarah") : String(localized: "e.g. Sam, Emma, Alex"),
                                    text: $deviceName
                                )
                                .font(.system(size: 16))
                                .padding(AppTheme.Spacing.regular)
                                .frame(height: 56)
                                .background(AppTheme.card(for: colorScheme))
                                .cornerRadius(AppTheme.CornerRadius.medium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                                        .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
                                )
                                .autocapitalization(.words)
                            }
                            .id("nameTextField")
                            .padding(.horizontal, AppTheme.Spacing.regular)
                            .padding(.vertical, AppTheme.Spacing.medium)
                            .frame(maxWidth: 512)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                    // Get Started Button - inside ScrollView
                    Button(action: {
                        if let mode = selectedMode {
                            // Name is optional — fall back to a friendly default so
                            // downstream display sites (Settings, pairing) never show "".
                            let name = trimmedDeviceName.isEmpty
                                ? (mode == .parentDevice ? String(localized: "Parent") : String(localized: "Child"))
                                : trimmedDeviceName
                            if let callback = onDeviceSelected {
                                callback(mode, name)
                            } else {
                                modeManager.setDeviceMode(mode, deviceName: name)
                            }
                        }
                    }) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedMode != nil ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.5))
                            .cornerRadius(AppTheme.CornerRadius.medium)
                            .textCase(.uppercase)
                    }
                    .disabled(selectedMode == nil)
                    .padding(.horizontal, AppTheme.Spacing.regular)
                    .padding(.top, AppTheme.Spacing.xLarge)
                    .padding(.bottom, AppTheme.Spacing.xxLarge)
                    .frame(maxWidth: 512)
                }
                .onChange(of: selectedMode) { newMode in
                    if newMode != nil {
                        // Auto-scroll to name text field when device is selected
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("nameTextField", anchor: .center)
                        }
                    }
                }
            }
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

    @State private var isPulsing = false

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
                }
                .padding(AppTheme.Spacing.regular)

                // Tap indicator when not selected
                if !isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                // Soft glow behind the tap icon (gentle pulse)
                                Circle()
                                    .fill(AppTheme.vibrantTeal)
                                    .frame(width: isPulsing ? 42 : 38, height: isPulsing ? 42 : 38)
                                    .blur(radius: 4)
                                    .opacity(isPulsing ? 0.35 : 0.2)

                                // Main tap icon circle
                                Circle()
                                    .fill(AppTheme.vibrantTeal)
                                    .frame(width: 36, height: 36)

                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(AppTheme.Spacing.medium)
                            .scaleEffect(isPulsing ? 1.06 : 1.0)
                        }
                        Spacer()
                    }
                }

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
                        isSelected ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(isPulsing ? 0.5 : 0.3),
                        lineWidth: isSelected ? 3 : 2
                    )
            )
            .shadow(
                color: isSelected ? AppTheme.vibrantTeal.opacity(0.4) : AppTheme.vibrantTeal.opacity(isPulsing ? 0.25 : 0.12),
                radius: isSelected ? 12 : (isPulsing ? 12 : 8),
                x: 0,
                y: isSelected ? 6 : (isPulsing ? 5 : 3)
            )
            .scaleEffect(isSelected ? 1.02 : (isPulsing ? 1.03 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .onAppear {
            // Start pulsing animation for unselected cards
            if !isSelected {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                // Stop pulsing animation immediately when selected
                withAnimation(.linear(duration: 0)) {
                    isPulsing = false
                }
            } else {
                // Resume pulsing when deselected
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Remove old Design Tokens and DeviceTypeCardView (not used)


struct DeviceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSelectionView()
    }
}
