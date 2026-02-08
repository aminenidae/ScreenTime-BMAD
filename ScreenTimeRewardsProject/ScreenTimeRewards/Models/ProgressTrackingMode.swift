//
//  ProgressTrackingMode.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-11.
//

import Foundation

enum ProgressTrackingMode: String, CaseIterable, Codable {
    case combined = "combined"
    case perApp = "per_app"

    var displayName: String {
        switch self {
        case .combined:
            return "Combined Total"
        case .perApp:
            return "Per-App Target"
        }
    }

    var description: String {
        switch self {
        case .combined:
            return "All selected apps contribute to one shared progress counter"
        case .perApp:
            return "Each selected app must individually meet the target"
        }
    }

    func exampleText(appCount: Int, targetMinutes: Int) -> String {
        switch self {
        case .combined:
            return "Example: \(targetMinutes) min total across \(appCount) apps = Complete"
        case .perApp:
            return "Example: \(targetMinutes) min in EACH of \(appCount) apps = Complete"
        }
    }
}
