import SwiftUI
import CoreData

/// 2-Column Grid showing child devices
/// Displays all devices at once in a grid layout
struct DeviceCardCarousel: View {
    let devices: [RegisteredDevice]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let cardHeight: CGFloat = 180

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(devices, id: \.deviceID) { device in
                NavigationLink(destination: ChildUsageDashboardView(
                    devices: devices,
                    selectedDeviceID: device.deviceID
                )) {
                    DeviceCard(device: device)
                        .frame(height: cardHeight)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Individual device card with device name and icon
struct DeviceCard: View {
    let device: RegisteredDevice
    @Environment(\.colorScheme) var colorScheme

    var deviceIcon: String {
        if let deviceName = device.deviceName?.lowercased() {
            if deviceName.contains("ipad") {
                return "ipad"
            } else if deviceName.contains("iphone") {
                return "iphone"
            }
        }
        return "laptopcomputer"
    }

    // Subtle device-type tint overlay
    var deviceTypeTint: Color {
        // Use gray tint for stale devices
        if device.isStale {
            return Color.gray.opacity(0.2)
        }
        if let deviceName = device.deviceName?.lowercased() {
            if deviceName.contains("ipad") {
                return AppTheme.vibrantTeal.opacity(0.1)
            } else if deviceName.contains("iphone") {
                return AppTheme.playfulCoral.opacity(0.1)
            }
        }
        return AppTheme.sunnyYellow.opacity(0.1)
    }

    /// Icon color based on connection status
    var iconColor: Color {
        if device.isStale {
            return .gray
        }
        return AppTheme.brandedText(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                // Device icon (compact size)
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: deviceIcon)
                        .font(.system(size: 50))
                        .foregroundColor(iconColor)

                    // Connection status indicator
                    if device.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .offset(x: 6, y: 6)
                    } else if device.connectionStatus.isHealthy {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                            .offset(x: 5, y: 5)
                    }
                }

                // Device name (compact)
                Text(device.deviceName ?? "Unknown Device")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(device.isStale ? .gray : AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Connection status or "Tap to view"
                if device.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                        Text("Disconnected")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Text("Tap to view")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .fill(deviceTypeTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .stroke(device.isStale ? Color.orange : AppTheme.border(for: colorScheme), lineWidth: device.isStale ? 2 : 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 6, x: 0, y: 3)
            )
        }
    }
}

struct DeviceCardCarousel_Previews: PreviewProvider {
    static var previews: some View {
        // Note: Preview requires Core Data context which is not available here
        // For now, we'll just show a placeholder
        
        return Text("Device Card Carousel")
            .padding()
    }
}
