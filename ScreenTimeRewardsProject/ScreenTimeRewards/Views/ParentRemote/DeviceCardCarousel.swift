import SwiftUI
import CoreData

/// 3D Card Carousel showing child devices
/// Cards scroll horizontally with deck-of-cards effect
struct DeviceCardCarousel: View {
    let devices: [RegisteredDevice]
    
    var body: some View {
        GeometryReader { geometry in
            let cardWidth: CGFloat = geometry.size.width * 0.75
            let cardHeight: CGFloat = 280
            let spacing: CGFloat = 20
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(devices, id: \.deviceID) { device in
                        NavigationLink(destination: ChildUsageDashboardView(
                            devices: devices,
                            selectedDeviceID: device.deviceID
                        )) {
                            DeviceCard(device: device)
                                .frame(width: cardWidth, height: cardHeight)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, (geometry.size.width - cardWidth) / 2)
            }
            .frame(height: cardHeight + 40)
        }
        .frame(height: 320)
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
            VStack(spacing: 24) {
                // Device icon
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: deviceIcon)
                        .font(.system(size: 80))
                        .foregroundColor(iconColor)

                    // Connection status indicator
                    if device.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                            .offset(x: 10, y: 10)
                    } else if device.connectionStatus.isHealthy {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .offset(x: 8, y: 8)
                    }
                }

                // Device name
                Text(device.deviceName ?? "Unknown Device")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(device.isStale ? .gray : AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Connection status or "Tap to view"
                if device.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                        Text("Disconnected")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 6) {
                        Text("Tap to view")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                            .fill(deviceTypeTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                            .stroke(device.isStale ? Color.orange : AppTheme.border(for: colorScheme), lineWidth: device.isStale ? 2 : 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 10, x: 0, y: 5)
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
