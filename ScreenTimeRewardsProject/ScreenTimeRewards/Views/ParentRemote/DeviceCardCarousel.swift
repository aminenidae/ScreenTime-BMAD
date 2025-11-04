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

    // Soft gradient colors based on device type
    var cardGradient: LinearGradient {
        let colors: [Color]

        if let deviceName = device.deviceName?.lowercased() {
            if deviceName.contains("ipad") {
                // Soft purple gradient for iPad
                colors = [
                    Color(red: 0.95, green: 0.93, blue: 1.0),
                    Color(red: 0.98, green: 0.96, blue: 1.0)
                ]
            } else if deviceName.contains("iphone") {
                // Soft blue gradient for iPhone
                colors = [
                    Color(red: 0.93, green: 0.97, blue: 1.0),
                    Color(red: 0.96, green: 0.98, blue: 1.0)
                ]
            } else {
                // Soft green gradient for other devices
                colors = [
                    Color(red: 0.93, green: 1.0, blue: 0.97),
                    Color(red: 0.96, green: 1.0, blue: 0.98)
                ]
            }
        } else {
            // Default soft gradient
            colors = [
                Color(red: 0.97, green: 0.97, blue: 1.0),
                Color(red: 0.99, green: 0.99, blue: 1.0)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            // Device icon
            Image(systemName: deviceIcon)
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // Device name
            Text(device.deviceName ?? "Unknown Device")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Tap to view indicator
            HStack(spacing: 6) {
                Text("Tap to view")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardGradient)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
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
