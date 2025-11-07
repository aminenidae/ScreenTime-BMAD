import SwiftUI

struct ChildChallengeCard: View {
    let challenge: Challenge
    let progress: ChallengeProgress?

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header Section
            HStack(alignment: .top, spacing: 16) {
                // Left side: Icon and text
                HStack(spacing: 16) {
                    // Challenge icon with circular background
                    ZStack {
                        Circle()
                            .fill(goalTypeColor.opacity(colorScheme == .dark ? 0.2 : 0.1))
                            .frame(width: 56, height: 56)

                        Image(systemName: goalTypeIcon)
                            .font(.system(size: 28))
                            .foregroundColor(goalTypeColor)
                    }

                    // Title and description
                    VStack(alignment: .leading, spacing: 0) {
                        Text(challenge.title ?? "Untitled Challenge")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))

                        Text(unlockText)
                            .font(.system(size: 14))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                }

                Spacer()

                // Points badge
                ZStack {
                    Circle()
                        .fill(Colors.customOrange.opacity(colorScheme == .dark ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "rosette")
                        .font(.system(size: 24))
                        .foregroundColor(Colors.customOrange)
                }
            }

            // Progress Bar Section
            if let progress = progress {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress text and percentage
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(progress.currentValue)/\(progress.targetValue) \(valueUnit)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))

                        Spacer()

                        Text("\(Int(progress.progressPercentage))%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Colors.customBlue)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 999)
                                .fill(Colors.progressTrack(for: colorScheme))
                                .frame(height: 16)

                            // Progress fill
                            RoundedRectangle(cornerRadius: 999)
                                .fill(Colors.customBlue)
                                .frame(width: geometry.size.width * min(progress.progressPercentage / 100, 1.0), height: 16)
                                .animation(.spring(), value: progress.currentValue)
                        }
                    }
                    .frame(height: 16)

                    // Bonus notification
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Colors.customGreen)

                        Text("Finish today for a 2x bonus!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Colors.customGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Colors.customGreen.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    )
                }
            }

            // Stats Section
            HStack(spacing: 16) {
                // Modules Done stat
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modules Done")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))

                    Text(modulesText)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.border(for: colorScheme), lineWidth: 1)
                )

                // Points Earned stat
                VStack(alignment: .leading, spacing: 6) {
                    Text("Points Earned")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))

                    Text("\(pointsEarned)")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.border(for: colorScheme), lineWidth: 1)
                )
            }

            // CTA Button
            Button(action: {
                // Action for going to learning app
            }) {
                HStack(spacing: 8) {
                    Text("Go to Learning App")
                        .font(.system(size: 16, weight: .bold))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(Colors.backgroundDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Colors.primary)
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Colors.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Colors.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Helpers

    private var goalTypeIcon: String {
        guard let goalType = challenge.goalType else { return "flag.fill" }
        switch goalType {
        case "daily_minutes": return "sun.max.fill"
        case "weekly_minutes": return "calendar"
        case "specific_apps": return "app.fill"
        case "streak": return "flame.fill"
        default: return "flag.fill"
        }
    }

    private var goalTypeColor: Color {
        guard let goalType = challenge.goalType else { return .gray }
        switch goalType {
        case "daily_minutes": return Colors.customOrange
        case "weekly_minutes": return Colors.customBlue
        case "specific_apps": return Colors.customGreen
        case "streak": return .red
        default: return .gray
        }
    }

    private var valueUnit: String {
        guard let goalType = challenge.goalType else { return "min" }
        switch goalType {
        case "daily_minutes", "weekly_minutes", "specific_apps": return "minutes"
        case "streak": return "days"
        default: return "min"
        }
    }

    private var unlockText: String {
        // Parse the first app from targetAppsJSON
        if let jsonString = challenge.targetAppsJSON,
           let data = jsonString.data(using: .utf8),
           let apps = try? JSONDecoder().decode([String].self, from: data),
           let firstApp = apps.first {
            return "Unlocks: \(firstApp)"
        }
        return "No app unlock"
    }

    private var modulesText: String {
        // This would need to be connected to actual module data
        // For now using a placeholder based on progress
        guard let progress = progress else { return "0/5" }
        let modulesCompleted = Int(progress.progressPercentage / 20)  // Rough estimate
        return "\(modulesCompleted)/5"
    }

    private var pointsEarned: Int {
        // Calculate points based on progress and bonus
        guard let progress = progress else { return 0 }
        let basePoints = Int(Double(progress.currentValue) * 5.0)  // 5 points per minute
        return basePoints
    }
}

// MARK: - Design Tokens
extension ChildChallengeCard {
    struct Colors {
        static let primary = Color(red: 0x13/255, green: 0xEC/255, blue: 0x13/255)
        static let customBlue = Color(red: 0x00/255, green: 0x7A/255, blue: 0xFF/255)
        static let customGreen = Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255)
        static let customOrange = Color(red: 0xFF/255, green: 0x95/255, blue: 0x00/255)

        static let backgroundLight = Color(red: 0xF6/255, green: 0xF8/255, blue: 0xF6/255)
        static let backgroundDark = Color(red: 0x10/255, green: 0x22/255, blue: 0x10/255)

        static let textLightPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
        static let textLightSecondary = Color(red: 0x63/255, green: 0x63/255, blue: 0x66/255)
        static let textDarkPrimary = Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF7/255)
        static let textDarkSecondary = Color(red: 0x8E/255, green: 0x8E/255, blue: 0x93/255)

        static let cardLight = Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255)
        static let cardDark = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)

        static let borderLight = Color(red: 0xE5/255, green: 0xE5/255, blue: 0xEA/255)
        static let borderDark = Color(red: 0x38/255, green: 0x38/255, blue: 0x3A/255)

        static let progressTrackLight = Color(red: 0xEF/255, green: 0xEF/255, blue: 0xF4/255)
        static let progressTrackDark = Color(red: 0x2C/255, green: 0x2C/255, blue: 0x2E/255)

        static func textPrimary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? textDarkPrimary : textLightPrimary
        }

        static func textSecondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? textDarkSecondary : textLightSecondary
        }

        static func card(for scheme: ColorScheme) -> Color {
            scheme == .dark ? cardDark : cardLight
        }

        static func border(for scheme: ColorScheme) -> Color {
            scheme == .dark ? borderDark : borderLight
        }

        static func progressTrack(for scheme: ColorScheme) -> Color {
            scheme == .dark ? progressTrackDark : progressTrackLight
        }
    }
}
