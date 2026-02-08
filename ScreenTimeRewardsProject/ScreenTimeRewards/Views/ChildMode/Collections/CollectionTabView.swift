//
//  CollectionTabView.swift
//  ScreenTimeRewards
//
//  Main collection view with badges and cards tabs
//

import SwiftUI

struct CollectionTabView: View {
    @ObservedObject var avatarService: AvatarService
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedSegment: CollectionSegment = .badges

    enum CollectionSegment: String, CaseIterable {
        case badges = "badges"
        case cards = "cards"

        var title: String {
            switch self {
            case .badges: return "Badges"
            case .cards: return "Cards"
            }
        }

        var icon: String {
            switch self {
            case .badges: return "rosette"
            case .cards: return "rectangle.stack.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment picker
            segmentPicker

            // Content based on selection
            if selectedSegment == .badges {
                BadgeCollectionView()
            } else {
                CardCollectionView()
            }
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(CollectionSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedSegment = segment
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: segment.icon)
                        Text(segment.title)
                    }
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(selectedSegment == segment ? .white : AppTheme.textPrimary(for: colorScheme))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedSegment == segment ? AppTheme.vibrantTeal : AppTheme.card(for: colorScheme))
                    )
                }
            }
        }
        .padding()
        .background(AppTheme.card(for: colorScheme))
    }
}

// MARK: - Badge Collection View

struct BadgeCollectionView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedCategory: BadgeDisplayCategory = .all

    enum BadgeDisplayCategory: String, CaseIterable {
        case all = "All"
        case unlocked = "Unlocked"
        case locked = "Locked"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(BadgeDisplayCategory.allCases, id: \.self) { category in
                        FilterChip(
                            title: category.rawValue,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, AppTheme.Spacing.small)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: AppTheme.Spacing.medium
                ) {
                    // Placeholder badges
                    ForEach(sampleBadges) { badge in
                        BadgeCard(badge: badge)
                    }
                }
                .padding()
            }
        }
    }

    // Sample badges for demonstration
    private var sampleBadges: [DisplayBadge] {
        [
            DisplayBadge(id: "1", name: "First Steps", icon: "figure.walk", isUnlocked: true, rarity: .bronze),
            DisplayBadge(id: "2", name: "Quick Learner", icon: "brain.head.profile", isUnlocked: true, rarity: .bronze),
            DisplayBadge(id: "3", name: "Bookworm", icon: "book.fill", isUnlocked: true, rarity: .silver),
            DisplayBadge(id: "4", name: "7 Day Streak", icon: "flame.fill", isUnlocked: false, rarity: .silver),
            DisplayBadge(id: "5", name: "Challenge Master", icon: "trophy.fill", isUnlocked: false, rarity: .gold),
            DisplayBadge(id: "6", name: "Super Star", icon: "star.fill", isUnlocked: false, rarity: .gold),
            DisplayBadge(id: "7", name: "Time Champion", icon: "clock.fill", isUnlocked: false, rarity: .platinum),
            DisplayBadge(id: "8", name: "Legend", icon: "crown.fill", isUnlocked: false, rarity: .diamond),
        ]
    }
}

// Simple badge display model
private struct DisplayBadge: Identifiable {
    let id: String
    let name: String
    let icon: String
    let isUnlocked: Bool
    let rarity: BadgeRarity

    enum BadgeRarity {
        case bronze, silver, gold, platinum, diamond

        var color: Color {
            switch self {
            case .bronze: return AppTheme.Rarity.bronze
            case .silver: return AppTheme.Rarity.silver
            case .gold: return AppTheme.Rarity.gold
            case .platinum: return AppTheme.Rarity.platinum
            case .diamond: return AppTheme.Rarity.diamond
            }
        }
    }
}

private struct BadgeCard: View {
    let badge: DisplayBadge
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? badge.rarity.color.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 70, height: 70)

                Image(systemName: badge.icon)
                    .font(.system(size: 28))
                    .foregroundColor(badge.isUnlocked ? badge.rarity.color : .gray.opacity(0.5))

                if !badge.isUnlocked {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 70, height: 70)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }

            Text(badge.name)
                .font(AppTheme.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(badge.isUnlocked ? AppTheme.textPrimary(for: colorScheme) : .gray)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Card Collection View

struct CardCollectionView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                // Coming soon message
                comingSoonCard

                // Preview of what's coming
                previewSection
            }
            .padding()
        }
    }

    private var comingSoonCard: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("Cards Coming Soon!")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Collect awesome cards as you learn! Each card tells a story of your achievements.")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, y: 2)
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Preview Series")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            HStack(spacing: AppTheme.Spacing.medium) {
                SeriesPreviewCard(
                    name: "Learning Legends",
                    icon: "book.fill",
                    color: AppTheme.vibrantTeal
                )

                SeriesPreviewCard(
                    name: "Time Masters",
                    icon: "clock.fill",
                    color: AppTheme.playfulCoral
                )

                SeriesPreviewCard(
                    name: "Challenge Champs",
                    icon: "trophy.fill",
                    color: AppTheme.sunnyYellow
                )
            }
        }
    }
}

private struct SeriesPreviewCard: View {
    let name: String
    let icon: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 100)
                .overlay(
                    VStack {
                        Image(systemName: icon)
                            .font(.system(size: 28))
                            .foregroundColor(color)

                        Image(systemName: "questionmark")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )

            Text(name)
                .font(AppTheme.Typography.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : AppTheme.brandedText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.1))
                )
        }
    }
}

// MARK: - Preview

#Preview("Collection Tab") {
    NavigationView {
        CollectionTabView(avatarService: AvatarService.shared)
    }
}
