import SwiftUI
import FamilyControls
import ManagedSettings

struct LearningTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()

    private var hasLearningApps: Bool {
        !viewModel.learningApps.isEmpty
    }

    var body: some View {
        let usageTimes = viewModel.getUsageTimes()

        return NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    totalPointsCard
                    learningAppsSection(usageTimes: usageTimes)
                    addLearningAppsButton
                    viewAllLearningAppsButton
                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Learning")
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
                fixedCategory: .learning,
                usageTimes: usageTimes,
                onSave: {
                    viewModel.onCategoryAssignmentSave()
                    viewModel.startMonitoring()
                }
            )
        }
    }
}

private extension LearningTabView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Text("Learning Apps")
                .font(.title2)
                .fontWeight(.bold)

            Text("Apps that earn points when used")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    var totalPointsCard: some View {
        VStack(spacing: 8) {
            Text("Total Points Earned")
                .font(.headline)

            Text("\(viewModel.learningRewardPoints)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.blue)

            Text("from \(viewModel.formatTime(viewModel.learningTime)) of learning")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
        .padding(.horizontal)
    }

    @ViewBuilder
    func learningAppsSection(usageTimes: [ApplicationToken: TimeInterval]) -> some View {
        if hasLearningApps {
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Learning Apps (\(viewModel.learningApps.count))")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(Array(viewModel.learningApps.enumerated()), id: \.offset) { index, token in
                    learningAppRow(
                        index: index,
                        token: token,
                        usageTime: usageTimes[token],
                        pointsPerMinute: viewModel.rewardPoints[token]
                    )
                    .padding(.horizontal)
                }
            }
        }
    }

    var addLearningAppsButton: some View {
        Button(action: viewModel.requestAuthorizationAndOpenPicker) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(hasLearningApps ? "Add More Apps" : "Select Learning Apps")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    var viewAllLearningAppsButton: some View {
        if hasLearningApps {
            Button(action: { viewModel.isCategoryAssignmentPresented = true }) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("View All Learning Apps")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    func learningAppRow(
        index: Int,
        token: ManagedSettings.ApplicationToken,
        usageTime: TimeInterval?,
        pointsPerMinute: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if #available(iOS 15.2, *) {
                    Label(token)
                        .font(.body)
                } else {
                    Text("Learning App \(index + 1)")
                        .font(.body)
                }

                Spacer()

                if let earnRate = pointsPerMinute {
                    Text("+\(earnRate) pts/min")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
            }

            if let usageTime, usageTime > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)

                    Text("Used: \(viewModel.formatTime(usageTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let earnRate = pointsPerMinute {
                        let minutesUsed = Int(usageTime / 60)
                        let pointsEarned = minutesUsed * earnRate
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(pointsEarned) pts earned")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct LearningTabView_Previews: PreviewProvider {
    static var previews: some View {
        LearningTabView()
    }
}
