import SwiftUI
import FamilyControls
import ManagedSettings

struct RewardsTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Use shared view model
    @State private var unlockMinutes: [ApplicationToken: Int] = [:]  // Track minutes for each app

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header info with points display
                VStack(spacing: 8) {
                    Text("Reward Apps")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Apps that cost points to use")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Points display
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(viewModel.availableLearningPoints)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Available Points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text("\(viewModel.reservedLearningPoints)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Text("Reserved Points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding()

                rewardAppsSection

                // Add reward apps button
                Button(action: {
                    // FIX: Ensure picker state is clean before presenting
                    viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                    // HARDENING FIX: Use retry logic for picker presentation with reward context
                    viewModel.presentPickerWithRetry(for: .reward)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(viewModel.rewardSnapshots.isEmpty ? "Select Reward Apps" : "Add More Apps")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // View all reward apps button - only show if there are reward apps
                if !viewModel.rewardSnapshots.isEmpty {
                    Button(action: {
                        viewModel.showAllRewardApps()
                    }) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("View All Reward Apps")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { _ in
            viewModel.onPickerSelectionChange()
        }
        .onChange(of: viewModel.isFamilyPickerPresented) { isPresented in
            if !isPresented {
                viewModel.onFamilyPickerDismissed()
            }
        }
        // Task 0: Sheet moved to MainTabView
    }
}

private extension RewardsTabView {
    var rewardAppsSection: some View {
        Group {
            if !viewModel.rewardSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Reward Apps (\(viewModel.rewardSnapshots.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(viewModel.rewardSnapshots) { snapshot in
                        rewardAppRow(snapshot: snapshot)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func rewardAppRow(snapshot: RewardAppSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Lock status icon
                Image(systemName: isUnlocked(snapshot.token) ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(isUnlocked(snapshot.token) ? .green : .red)
                    .font(.title3)

                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName)
                        .font(.body)
                }

                Spacer()

                // Task M: Add remove button for reward apps
                Button(action: {
                    // Show confirmation and remove app
                    removeRewardApp(snapshot.token)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())

                Text("\(snapshot.pointsPerMinute) pts/min")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }

            // Unlocked status display
            if let unlockedApp = viewModel.unlockedRewardApps[snapshot.token] {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.green)
                        Text("\(unlockedApp.remainingMinutes) min remaining")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(unlockedApp.reservedPoints) pts reserved")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    Button(action: {
                        viewModel.lockRewardApp(token: snapshot.token)
                    }) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Lock & Return Points")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            } else {
                // Locked status - show unlock button
                let canUnlock = viewModel.canUnlockRewardApp(token: snapshot.token)
                let minimumPoints = snapshot.pointsPerMinute * 15

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Minimum: 15 min (\(minimumPoints) pts)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Stepper("", value: Binding(
                            get: { unlockMinutes[snapshot.token] ?? 15 },
                            set: { unlockMinutes[snapshot.token] = max(15, $0) }
                        ), in: 15...120, step: 5)
                        Text("\(unlockMinutes[snapshot.token] ?? 15) min")
                            .font(.caption)
                            .frame(minWidth: 50)
                    }

                    Button(action: {
                        let minutes = unlockMinutes[snapshot.token] ?? 15
                        viewModel.unlockRewardApp(token: snapshot.token, minutes: minutes)
                    }) {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            let minutes = unlockMinutes[snapshot.token] ?? 15
                            let cost = snapshot.pointsPerMinute * minutes
                            Text("Unlock • \(cost) pts for \(minutes) min")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(canUnlock.canUnlock ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(!canUnlock.canUnlock)

                    if !canUnlock.canUnlock, let reason = canUnlock.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                }
            }

            // Usage stats
            if snapshot.totalSeconds > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)

                    Text("Used: \(viewModel.formatTime(snapshot.totalSeconds))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let minutesUsed = Int(snapshot.totalSeconds / 60)
                    let pointsSpent = minutesUsed * snapshot.pointsPerMinute
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(pointsSpent) pts spent")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
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
}

struct RewardsTabView_Previews: PreviewProvider {
    static var previews: some View {
        RewardsTabView()
            .environmentObject(AppUsageViewModel())  // Provide a view model for previews
    }
}
