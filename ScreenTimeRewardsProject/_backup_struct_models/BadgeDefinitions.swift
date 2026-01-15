import Foundation

struct BadgeDefinition {
    let id: String
    let name: String
    let description: String
    let icon: String
    let criteria: Badge.BadgeCriteria

    static let starterBadges: [BadgeDefinition] = [
        BadgeDefinition(
            id: "first_steps",
            name: "First Steps",
            description: "Complete your first challenge",
            icon: "figure.walk",
            criteria: Badge.BadgeCriteria(type: .challengesCompleted, threshold: 1)
        ),
        BadgeDefinition(
            id: "week_warrior",
            name: "Week Warrior",
            description: "Maintain a 7-day streak",
            icon: "calendar",
            criteria: Badge.BadgeCriteria(type: .streakDays, threshold: 7)
        ),
        BadgeDefinition(
            id: "month_master",
            name: "Month Master",
            description: "Maintain a 30-day streak",
            icon: "calendar.badge.plus",
            criteria: Badge.BadgeCriteria(type: .streakDays, threshold: 30)
        ),
        BadgeDefinition(
            id: "learning_legend",
            name: "Learning Legend",
            description: "Complete 100 hours of learning",
            icon: "brain.head.profile",
            criteria: Badge.BadgeCriteria(type: .totalLearningMinutes, threshold: 6000)
        ),
        BadgeDefinition(
            id: "point_collector",
            name: "Point Collector",
            description: "Earn 10,000 learning points",
            icon: "star.circle.fill",
            criteria: Badge.BadgeCriteria(type: .totalPointsEarned, threshold: 10000)
        ),
        BadgeDefinition(
            id: "challenge_champion",
            name: "Challenge Champion",
            description: "Complete 10 challenges",
            icon: "rosette",
            criteria: Badge.BadgeCriteria(type: .challengesCompleted, threshold: 10)
        )
    ]
}