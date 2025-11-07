import Foundation
import SwiftUI

struct ChallengeTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol
    let goalType: Challenge.GoalType
    let suggestedTarget: Int
    let suggestedBonus: Int
    let colorHex: String

    static let allTemplates: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "daily_dynamo",
            name: "Daily Dynamo",
            description: "Complete 60 minutes of learning every day",
            icon: "bolt.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 60,
            suggestedBonus: 10,
            colorHex: "#FFB800"
        ),
        ChallengeTemplate(
            id: "weekend_warrior",
            name: "Weekend Warrior",
            description: "Learn 180 minutes over the weekend",
            icon: "trophy.fill",
            goalType: .weeklyMinutes,
            suggestedTarget: 180,
            suggestedBonus: 15,
            colorHex: "#FF6B35"
        ),
        ChallengeTemplate(
            id: "app_master",
            name: "App Master",
            description: "Spend 5 hours in your favorite learning app this week",
            icon: "target",
            goalType: .specificApps,
            suggestedTarget: 300,
            suggestedBonus: 20,
            colorHex: "#4ECDC4"
        ),
        ChallengeTemplate(
            id: "streak_champion",
            name: "Streak Champion",
            description: "Maintain a 7-day learning streak",
            icon: "flame.fill",
            goalType: .streak,
            suggestedTarget: 7,
            suggestedBonus: 25,
            colorHex: "#FF3366"
        ),
        ChallengeTemplate(
            id: "quick_start",
            name: "Quick Start",
            description: "Just 15 minutes of learning per day",
            icon: "star.fill",
            goalType: .dailyMinutes,
            suggestedTarget: 15,
            suggestedBonus: 5,
            colorHex: "#95E1D3"
        )
    ]
}

// Helper extension for Color from hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}