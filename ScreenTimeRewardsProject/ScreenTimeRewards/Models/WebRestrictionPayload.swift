import Foundation

/// Payload for web restriction commands sent from parent to child device
struct WebRestrictionPayload: Codable {
    let commandID: String
    let parentDeviceID: String
    let targetDeviceID: String
    let blockedWebDomainTokens: [Data]
    let blockedBrowserBundleIDs: [String]
    let timestamp: Date

    /// Number of blocked websites
    var blockedWebsiteCount: Int {
        blockedWebDomainTokens.count
    }

    /// Number of blocked browsers
    var blockedBrowserCount: Int {
        blockedBrowserBundleIDs.count
    }

    init(
        commandID: String = UUID().uuidString,
        parentDeviceID: String,
        targetDeviceID: String,
        blockedWebDomainTokens: [Data],
        blockedBrowserBundleIDs: [String],
        timestamp: Date = Date()
    ) {
        self.commandID = commandID
        self.parentDeviceID = parentDeviceID
        self.targetDeviceID = targetDeviceID
        self.blockedWebDomainTokens = blockedWebDomainTokens
        self.blockedBrowserBundleIDs = blockedBrowserBundleIDs
        self.timestamp = timestamp
    }

    /// Create payload from current state
    static func fromCurrentState(
        parentDeviceID: String,
        targetDeviceID: String,
        blockedWebDomainTokens: [Data],
        blockedBrowserBundleIDs: [String]
    ) -> WebRestrictionPayload {
        return WebRestrictionPayload(
            parentDeviceID: parentDeviceID,
            targetDeviceID: targetDeviceID,
            blockedWebDomainTokens: blockedWebDomainTokens,
            blockedBrowserBundleIDs: blockedBrowserBundleIDs
        )
    }

    /// Encode to base64 string for CloudKit transport
    func toBase64String() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    /// Decode from base64 string
    static func fromBase64String(_ base64String: String) throws -> WebRestrictionPayload {
        guard let data = Data(base64Encoded: base64String) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Invalid base64 string")
            )
        }
        return try JSONDecoder().decode(WebRestrictionPayload.self, from: data)
    }
}
