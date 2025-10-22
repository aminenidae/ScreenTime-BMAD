import SwiftUI
import FamilyControls
import ManagedSettings

struct LearningTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()

    private var hasLearningApps: Bool {
        !viewModel.learningSnapshots.isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    totalPointsCard
                    learningAppsSection
                    addLearningAppsButton
                    viewAllLearningAppsButton
                    Spacer()
                }
                .padding(.vertical)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .navigationTitle("Learning")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { newSelection in
            viewModel.onPickerSelectionChange()

            if viewModel.isFamilyPickerPresented && !newSelection.applications.isEmpty {
                viewModel.isCategoryAssignmentPresented = true
            }
        }
        .sheet(isPresented: $viewModel.isCategoryAssignmentPresented) {
            CategoryAssignmentView(
                selection: viewModel.familySelection,
                categoryAssignments: $viewModel.categoryAssignments,
                rewardPoints: $viewModel.rewardPoints,
                fixedCategory: .learning,
                usageTimes: viewModel.getUsageTimes(),
                onSave: {
                    viewModel.onCategoryAssignmentSave()
                    viewModel.startMonitoring()
                },
                onCancel: {
                    viewModel.cancelCategoryAssignment()
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

    var learningAppsSection: some View {
        Group {
            if !viewModel.learningSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Learning Apps (\(viewModel.learningSnapshots.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(viewModel.learningSnapshots) { snapshot in
                        learningAppRow(snapshot: snapshot)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    var addLearningAppsButton: some View {
        Button(action: { viewModel.presentLearningPicker() }) {
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
    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                } else {
                    Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                        .font(.body)
                }

                Spacer()

                Text("+\(snapshot.pointsPerMinute) pts/min")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }

            if snapshot.totalSeconds > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)

                    Text("Used: \(viewModel.formatTime(snapshot.totalSeconds))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let minutesUsed = Int(snapshot.totalSeconds / 60)
                    let pointsEarned = minutesUsed * snapshot.pointsPerMinute
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(pointsEarned) pts earned")
                        .font(.caption)
                        .foregroundColor(.blue)
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
