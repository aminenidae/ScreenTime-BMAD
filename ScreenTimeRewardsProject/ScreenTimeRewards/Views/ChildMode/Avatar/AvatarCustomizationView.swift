//
//  AvatarCustomizationView.swift
//  ScreenTimeRewards
//
//  Allows children to customize their avatar with accessories
//

import SwiftUI

struct AvatarCustomizationView: View {
    @ObservedObject var avatarService: AvatarService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedCategory: AccessoryCategory = .hat
    @State private var showUnlockInfo: AvatarAccessory?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Avatar preview
                avatarPreview

                // Category picker
                categoryPicker

                // Accessory grid
                accessoryGrid
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $showUnlockInfo) { accessory in
            AccessoryUnlockInfoView(accessory: accessory)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Avatar Preview

    private var avatarPreview: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            AvatarView(
                avatarState: avatarService.currentAvatarState,
                size: .hero,
                showMood: true,
                isInteractive: true
            )

            Text(avatarService.currentAvatarState?.avatarDefinition?.name ?? "Your Buddy")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Tap an accessory to equip it!")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .padding(.vertical, AppTheme.Spacing.large)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.vibrantTeal.opacity(0.1),
                    AppTheme.playfulCoral.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.medium) {
                ForEach(AccessoryCategory.allCases, id: \.self) { category in
                    CategoryTab(
                        category: category,
                        isSelected: selectedCategory == category,
                        count: accessoryCount(for: category)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.regular)
            .padding(.vertical, AppTheme.Spacing.medium)
        }
        .background(AppTheme.card(for: colorScheme))
    }

    // MARK: - Accessory Grid

    private var accessoryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.medium),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.medium),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.medium)
                ],
                spacing: AppTheme.Spacing.medium
            ) {
                // "None" option to unequip
                AccessoryGridItem(
                    accessory: nil,
                    isEquipped: equippedAccessoryID(for: selectedCategory) == nil,
                    isUnlocked: true
                ) {
                    Task {
                        await avatarService.unequipAccessory(category: selectedCategory)
                    }
                }

                // All accessories for this category
                ForEach(accessoriesForCategory) { accessory in
                    let isUnlocked = isAccessoryUnlocked(accessory)
                    let isEquipped = equippedAccessoryID(for: selectedCategory) == accessory.id

                    AccessoryGridItem(
                        accessory: accessory,
                        isEquipped: isEquipped,
                        isUnlocked: isUnlocked
                    ) {
                        if isUnlocked {
                            Task {
                                await avatarService.equipAccessory(accessory)
                            }
                        } else {
                            showUnlockInfo = accessory
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.regular)
        }
    }

    // MARK: - Helpers

    private var accessoriesForCategory: [AvatarAccessory] {
        AvatarCatalog.accessories(for: selectedCategory)
    }

    private func accessoryCount(for category: AccessoryCategory) -> Int {
        let total = AvatarCatalog.accessories(for: category).count
        let unlocked = AvatarCatalog.accessories(for: category)
            .filter { isAccessoryUnlocked($0) }
            .count
        return unlocked
    }

    private func isAccessoryUnlocked(_ accessory: AvatarAccessory) -> Bool {
        avatarService.currentAvatarState?.unlockedAccessoryIDs.contains(accessory.id) ?? false
    }

    private func equippedAccessoryID(for category: AccessoryCategory) -> String? {
        avatarService.currentAvatarState?.equippedAccessories.accessoryID(for: category)
    }
}

// MARK: - Category Tab

private struct CategoryTab: View {
    let category: AccessoryCategory
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 20))

                Text(category.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)

                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, height: 60)
            .foregroundColor(isSelected ? .white : AppTheme.brandedText(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.vibrantTeal : AppTheme.vibrantTeal.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accessory Grid Item

private struct AccessoryGridItem: View {
    let accessory: AvatarAccessory?
    let isEquipped: Bool
    let isUnlocked: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(backgroundColor)
                        .frame(width: 80, height: 80)

                    // Icon
                    if let accessory = accessory {
                        Image(systemName: accessory.asset)
                            .font(.system(size: 32))
                            .foregroundColor(isUnlocked ? accessory.rarity.color : .gray)
                    } else {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }

                    // Lock overlay
                    if !isUnlocked {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 80, height: 80)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }

                    // Equipped indicator
                    if isEquipped {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .background(Circle().fill(.white).padding(2))
                            }
                            Spacer()
                        }
                        .frame(width: 80, height: 80)
                        .padding(4)
                    }

                    // Rarity glow
                    if let accessory = accessory, isUnlocked, accessory.rarity.glowIntensity > 0 {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accessory.rarity.color, lineWidth: 2)
                            .frame(width: 80, height: 80)
                    }
                }

                // Name
                Text(accessory?.name ?? "None")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)

                // Rarity
                if let accessory = accessory {
                    Text(accessory.rarity.displayName)
                        .font(.caption2)
                        .foregroundColor(accessory.rarity.color)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isUnlocked || accessory != nil ? 1 : 0.7)
    }

    private var backgroundColor: Color {
        if isEquipped {
            return AppTheme.vibrantTeal.opacity(0.2)
        }
        return AppTheme.card(for: colorScheme)
    }
}

// MARK: - Unlock Info View

private struct AccessoryUnlockInfoView: View {
    let accessory: AvatarAccessory
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(accessory.rarity.color.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: accessory.asset)
                    .font(.system(size: 44))
                    .foregroundColor(accessory.rarity.color)

                // Lock
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                }
                .frame(width: 100, height: 100)
            }

            // Name and rarity
            VStack(spacing: 4) {
                Text(accessory.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(accessory.rarity.displayName)
                    .font(.subheadline)
                    .foregroundColor(accessory.rarity.color)
            }

            // Unlock criteria
            if let criteria = accessory.unlockCriteria {
                VStack(spacing: 8) {
                    Text("How to unlock:")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(criteria.displayDescription)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            }

            Spacer()

            Button("Got it!") {
                dismiss()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.vibrantTeal)
            .cornerRadius(12)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Customization") {
    AvatarCustomizationView(avatarService: AvatarService.shared)
}
