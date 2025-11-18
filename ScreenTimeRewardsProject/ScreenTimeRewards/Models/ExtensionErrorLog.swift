import Foundation

/// Represents a single log entry emitted by the DeviceActivity extension.
struct ExtensionErrorEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let eventName: String
    let success: Bool
    let errorDescription: String?
    let memoryUsageMB: Double
    let action: String

    init(
        eventName: String,
        success: Bool,
        errorDescription: String? = nil,
        memoryUsageMB: Double,
        action: String
    ) {
        self.id = UUID()
        self.timestamp = Date().timeIntervalSince1970
        self.eventName = eventName
        self.success = success
        self.errorDescription = errorDescription
        self.memoryUsageMB = memoryUsageMB
        self.action = action
    }
}

/// Lightweight log store backed by the shared app-group defaults.
enum ExtensionErrorLog {
    private static let logKey = "extension_error_log"
    private static let appGroupIdentifier = "group.com.screentimerewards.shared"
    private static let maxEntries = 100

    static func append(_ entry: ExtensionErrorEntry) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        var entries = readAll()
        entries.append(entry)

        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        if let encoded = try? JSONEncoder().encode(entries) {
            defaults.set(encoded, forKey: logKey)
        }
    }

    static func readAll() -> [ExtensionErrorEntry] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([ExtensionErrorEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear() {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: logKey)
    }

    static func todayErrors() -> [ExtensionErrorEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return readAll().filter { !$0.success && $0.timestamp >= startOfDay }
    }
}
