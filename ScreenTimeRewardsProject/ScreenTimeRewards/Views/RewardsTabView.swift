import SwiftUI
import FamilyControls
import ManagedSettings

struct RewardsTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel  // Task 0: Use shared view model

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header info
                    VStack(spacing: 8) {
                        Text("Reward Apps")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Apps that cost points to use")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    rewardAppsSection

                    // Add reward apps button
                    Button(action: {
                        viewModel.presentRewardPicker()
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

                    // Unlock all reward apps button - only show if there are reward apps
                    if !viewModel.rewardSnapshots.isEmpty {
                        Button(action: {
                            viewModel.unlockRewardApps()
                        }) {
                            HStack {
                                Image(systemName: "lock.open.fill")
                                Text("Unlock All Reward Apps")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
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
            .navigationTitle("Rewards")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
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