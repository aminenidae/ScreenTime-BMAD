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
                    OnboardingBackButton(action: { onBack?() })
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
                            .foregroundColor(AppTheme.accentText(for: colorScheme))
                            .tracking(1)
                            .padding(.top, AppTheme.Spacing.medium)

                        // Choice cards - Device Selection
                        // Text-only by design: at the decision moment, imagery competes
                        // with the words. Cards describe the parent's SITUATION, not device
                        // ownership — answerable even when installing alone on their own phone.
                        VStack(spacing: AppTheme.Spacing.regular) {
                            // Child uses THIS device → child flow
                            DeviceChoiceCard(
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
                            DeviceChoiceCard(
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

// MARK: - Device Choice Card Component

/// Text-only selection card with a radio-style indicator. Deliberately minimal:
/// the decision moment should be about reading two lines, not decoding imagery.
private struct DeviceChoiceCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.regular) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.Spacing.small)

                // Radio-style selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme),
                            lineWidth: 2
                        )
                        .background(Circle().fill(isSelected ? AppTheme.vibrantTeal : Color.clear))
                        .frame(width: 26, height: 26)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(AppTheme.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? AppTheme.vibrantTeal.opacity(0.25) : Color.black.opacity(0.06),
                radius: isSelected ? 10 : 6,
                x: 0,
                y: 3
            )
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
