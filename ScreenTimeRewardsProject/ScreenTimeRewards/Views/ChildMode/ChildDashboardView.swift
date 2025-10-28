import SwiftUI
import FamilyControls

struct ChildDashboardView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Points card
                pointsCard

                // Learning apps section
                if !viewModel.usedLearningApps.isEmpty {
                    learningAppsSection
                }

                // Reward apps section
                if !viewModel.usedRewardApps.isEmpty {
                    rewardAppsSection
                }

                // Empty state
                if viewModel.usedLearningApps.isEmpty && viewModel.usedRewardApps.isEmpty {
                    emptyStateView
                }

                Spacer()
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private extension ChildDashboardView {
    var pointsCard: some View {
        VStack(spacing: 12) {
            Text("Your Points")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(viewModel.availableLearningPoints)")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.blue)

            HStack(spacing: 30) {
                VStack {
                    Text("\(viewModel.learningRewardPoints)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Total Earned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(viewModel.reservedLearningPoints)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Reserved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.1))
        )
    }

    var learningAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
                Text("Learning Apps")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(viewModel.usedLearningApps) { snapshot in
                learningAppCard(snapshot: snapshot)
            }
        }
    }

    func learningAppCard(snapshot: LearningAppSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                        .fontWeight(.medium)
                } else {
                    Text(snapshot.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(viewModel.formatTime(snapshot.totalSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(snapshot.earnedPoints) pts earned")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    var rewardAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.orange)
                Text("Reward Apps")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(viewModel.usedRewardApps) { snapshot in
                rewardAppCard(snapshot: snapshot)
            }
        }
    }

    func rewardAppCard(snapshot: RewardAppSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .font(.body)
                        .fontWeight(.medium)
                } else {
                    Text(snapshot.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(viewModel.formatTime(snapshot.totalSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    if viewModel.unlockedRewardApps[snapshot.token] != nil {
                        Text("Unlocked")
                            .font(.caption)
                            .foregroundColor(.green)
                        Image(systemName: "lock.open.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Locked")
                            .font(.caption)
                            .foregroundColor(.red)
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Apps Used Yet")
                .font(.title3)
                .fontWeight(.medium)

            Text("Start using learning apps to earn points!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ChildDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ChildDashboardView()
            .environmentObject(AppUsageViewModel())
    }
}