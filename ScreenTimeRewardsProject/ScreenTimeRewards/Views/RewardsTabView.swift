import SwiftUI
import FamilyControls
import ManagedSettings

struct RewardsTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()

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

                    // Selected reward apps list
                    if !viewModel.rewardApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Selected Reward Apps (\(viewModel.rewardApps.count))")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(viewModel.rewardApps.enumerated()), id: \.offset) { index, token in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        if #available(iOS 15.2, *) {
                                            Label(token)
                                                .font(.body)
                                        } else {
                                            Text("Reward App \(index + 1)")
                                                .font(.body)
                                        }

                                        Spacer()

                                        if let cost = viewModel.rewardPoints[token] {
                                            Text("\(cost) pts/min")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                    }

                                    // Show individual app usage time
                                    if let usageTime = viewModel.getUsageTimes()[token], usageTime > 0 {
                                        HStack {
                                            Image(systemName: "clock.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                            Text("Used: \(viewModel.formatTime(usageTime))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            // Show points spent on this specific app
                                            if let cost = viewModel.rewardPoints[token] {
                                                let minutesUsed = Int(usageTime / 60)
                                                let pointsSpent = minutesUsed * cost
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text("\(pointsSpent) pts spent")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Add reward apps button
                    Button(action: {
                        viewModel.requestAuthorizationAndOpenPicker()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(viewModel.rewardApps.isEmpty ? "Select Reward Apps" : "Add More Apps")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // View all reward apps button - only show if there are reward apps
                    if !viewModel.rewardApps.isEmpty {
                        Button(action: {
                            viewModel.isCategoryAssignmentPresented = true
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
                    if !viewModel.rewardApps.isEmpty {
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
            .navigationTitle("Rewards")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { newSelection in
            viewModel.onPickerSelectionChange()

            if !newSelection.applications.isEmpty {
                viewModel.isCategoryAssignmentPresented = true
            }
        }
        .sheet(isPresented: $viewModel.isCategoryAssignmentPresented) {
            CategoryAssignmentView(
                selection: viewModel.familySelection,
                categoryAssignments: $viewModel.categoryAssignments,
                rewardPoints: $viewModel.rewardPoints,
                fixedCategory: .reward,  // Auto-categorize as Reward
                usageTimes: viewModel.getUsageTimes(),  // Pass usage times for display
                onSave: {
                    viewModel.onCategoryAssignmentSave()

                    // Immediately shield (block) reward apps
                    viewModel.blockRewardApps()

                    // Start monitoring usage
                    viewModel.startMonitoring()
                }
            )
        }
    }
}

struct RewardsTabView_Previews: PreviewProvider {
    static var previews: some View {
        RewardsTabView()
    }
}
