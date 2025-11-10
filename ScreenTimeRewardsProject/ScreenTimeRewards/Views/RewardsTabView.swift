import SwiftUI
import FamilyControls
import ManagedSettings

struct RewardsTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Use shared view model
    @State private var unlockMinutes: [ApplicationToken: Int] = [:]  // Track minutes for each app
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Top App Bar
                    HStack {
                        Button(action: {
                            // Back action - handle dismissal if needed
                        }) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 20))
                                .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))
                                .frame(width: 40, height: 40)
                        }

                        Spacer()

                        Text("Reward Apps")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.27)
                            .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))

                        Spacer()

                        // Placeholder for balance
                        Color.clear
                            .frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(
                        (colorScheme == .dark ? Colors.cardDark : Colors.cardLight)
                            .opacity(0.8)
                            .background(.ultraThinMaterial)
                    )

                    // Main content
                    VStack(spacing: 0) {
                        // Points Summary Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Points Available")
                                    .font(.system(size: 16))
                                    .foregroundColor(Colors.textSecondary(colorScheme: colorScheme))

                                Spacer()

                                Button(action: {
                                    // Show help info
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(Colors.textSecondary(colorScheme: colorScheme))
                                }
                            }

                            Text("\(viewModel.availableLearningPoints)")
                                .font(.system(size: 48, weight: .bold))
                                .tracking(-0.96)
                                .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))

                            if viewModel.reservedLearningPoints > 0 {
                                Text("\(viewModel.reservedLearningPoints) points reserved")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Colors.accent)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Colors.cardDark : Colors.cardLight)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        .padding(4)

                        // Section Header
                        Text("All Reward Apps")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.27)
                            .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        // List of Reward Apps
                        rewardAppsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
            .background(colorScheme == .dark ? Colors.backgroundDark : Colors.backgroundLight)

            // Floating Action Button
            Button(action: {
                // FIX: Ensure picker state is clean before presenting
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                // HARDENING FIX: Use retry logic for picker presentation with reward context
                viewModel.presentPickerWithRetry(for: .reward)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.refresh()
        }
        // NOTE: Picker and sheet presentation handled by MainTabView to avoid conflicts
    }
}

private extension RewardsTabView {
    var rewardAppsSection: some View {
        Group {
            if !viewModel.rewardSnapshots.isEmpty {
                // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
                let columns = horizontalSizeClass == .regular ? [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ] : [
                    GridItem(.flexible())
                ]

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.rewardSnapshots) { snapshot in
                        rewardAppRow(snapshot: snapshot)
                    }
                }
            } else {
                Text("No reward apps selected")
                    .font(.system(size: 16))
                    .foregroundColor(Colors.textSecondary(colorScheme: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    @ViewBuilder
    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        let isUnlocked = viewModel.unlockedRewardApps[snapshot.token] != nil

        // Standardized icon sizes (match Learning tab)
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 25 : 34
        let iconScale: CGFloat = horizontalSizeClass == .regular ? 1.05 : 1.35
        let fallbackIconSize: CGFloat = horizontalSizeClass == .regular ? 18 : 24

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // App Icon - Device-specific larger size
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(iconScale)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: iconSize, height: iconSize)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: fallbackIconSize))
                                .foregroundColor(.gray)
                        )
                }

                // App Info - using Label with 8pt font for long names
                VStack(alignment: .leading, spacing: 4) {
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))
                    } else {
                        Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Text("\(snapshot.pointsPerMinute) pts/min")
                        .font(.system(size: 12))
                        .foregroundColor(Colors.textSecondary(colorScheme: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // Status Icon and Toggle
                VStack(spacing: 8) {
                    // Status Icon (lock/unlock)
                    Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isUnlocked ? Colors.secondary : Colors.textSecondary(colorScheme: colorScheme))

                    // Custom Toggle
                    Toggle("", isOn: Binding(
                        get: { viewModel.unlockedRewardApps[snapshot.token] != nil },
                        set: { isOn in
                            if isOn {
                                let minutes = unlockMinutes[snapshot.token] ?? 15
                                viewModel.unlockRewardApp(token: snapshot.token, minutes: minutes)
                            } else {
                                viewModel.lockRewardApp(token: snapshot.token)
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(CustomToggleStyle())
                }
            }
            .padding(12)

            // Points adjustment section
            VStack(spacing: 8) {
                Divider()
                    .background(Colors.textSecondary(colorScheme: colorScheme).opacity(0.2))

                HStack(spacing: 12) {
                    Text("Points per minute:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Colors.textPrimary(colorScheme: colorScheme))

                    Spacer()

                    // Stepper control
                    HStack(spacing: 8) {
                        Button(action: {
                            adjustPoints(for: snapshot.token, delta: -1)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(snapshot.pointsPerMinute > 1 ? Colors.primary : Colors.textSecondary(colorScheme: colorScheme).opacity(0.3))
                        }
                        .disabled(snapshot.pointsPerMinute <= 1)

                        Text("\(snapshot.pointsPerMinute)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Colors.primary)
                            .frame(minWidth: 40)

                        Button(action: {
                            adjustPoints(for: snapshot.token, delta: 1)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Colors.primary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(colorScheme == .dark ? Colors.cardDark : Colors.cardLight)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func isUnlocked(_ token: ApplicationToken) -> Bool {
        viewModel.unlockedRewardApps[token] != nil
    }

    // Task M: Add method to remove a reward app
    private func removeRewardApp(_ token: ApplicationToken) {
        #if DEBUG
        let appName = viewModel.resolvedDisplayName(for: token) ?? "Unknown App"
        print("[RewardsTabView] Requesting removal of reward app: \(appName)")
        #endif

        // Show confirmation alert
        // In a real implementation, this would show an alert dialog
        let warningMessage = viewModel.getRemovalWarningMessage(for: token)
        #if DEBUG
        print("[RewardsTabView] Removal warning: \(warningMessage)")
        #endif

        // Proceed with removal
        viewModel.removeApp(token)
    }

    private func adjustPoints(for token: ApplicationToken, delta: Int) {
        let currentPoints = viewModel.rewardPoints[token] ?? 1
        let newPoints = max(1, currentPoints + delta)

        #if DEBUG
        let appName = viewModel.resolvedDisplayName(for: token) ?? "Unknown App"
        print("[RewardsTabView] Adjusting points for \(appName): \(currentPoints) -> \(newPoints)")
        #endif

        viewModel.rewardPoints[token] = newPoints
        viewModel.saveCategoryAssignments()

        // Refresh snapshots to update UI with new point values
        viewModel.refreshSnapshotsOnly()
    }

    // Helper function to determine font size based on app name length
    private func appNameFontSize(for appName: String) -> CGFloat {
        let nameLength = appName.count
        if nameLength > 20 {
            return 13 // Smaller font for very long names
        } else if nameLength > 15 {
            return 14 // Medium font for long names
        } else {
            return 16 // Normal font for short names
        }
    }
}

// MARK: - Design Tokens
private extension RewardsTabView {
    struct Colors {
        static let primary = Color(red: 0.29, green: 0.56, blue: 0.89) // #4A90E2
        static let secondary = Color(red: 0.31, green: 0.89, blue: 0.76) // #50E3C2
        static let accent = Color(red: 0.96, green: 0.65, blue: 0.14) // #F5A623

        static let backgroundLight = Color(red: 0.97, green: 0.98, blue: 0.98) // #F8F9FA
        static let backgroundDark = Color(red: 0.06, green: 0.09, blue: 0.13) // #101622

        static let cardLight = Color.white // #FFFFFF
        static let cardDark = Color(red: 0.09, green: 0.13, blue: 0.19) // #182030

        static func textPrimary(colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white : Color(red: 0.29, green: 0.29, blue: 0.29) // #4A4A4A
        }

        static func textSecondary(colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(red: 0.67, green: 0.67, blue: 0.67) : Color(red: 0.61, green: 0.61, blue: 0.61) // #9B9B9B / gray-400
        }
    }
}

// MARK: - Custom Toggle Style
struct CustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 15.5)
                    .fill(configuration.isOn ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.gray.opacity(0.3))
                    .frame(width: 51, height: 31)

                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

struct RewardsTabView_Previews: PreviewProvider {
    static var previews: some View {
        RewardsTabView()
            .environmentObject(AppUsageViewModel())  // Provide a view model for previews
    }
}
