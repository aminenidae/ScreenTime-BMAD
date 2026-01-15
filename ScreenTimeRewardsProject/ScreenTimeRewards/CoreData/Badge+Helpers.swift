import Foundation

extension Badge {
    /// Decoded criteria for the badge, if available.
    var criteria: BadgeCriteria? {
        guard let criteriaJSON,
              let data = criteriaJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(BadgeCriteria.self, from: data)
    }

    /// Indicates whether the badge has been unlocked.
    var isUnlocked: Bool {
        unlockedAt != nil
    }
}

