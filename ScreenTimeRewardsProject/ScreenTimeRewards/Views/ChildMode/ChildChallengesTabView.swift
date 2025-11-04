import SwiftUI

struct ChildChallengesTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Active Challenges
                if !viewModel.activeChallenges.isEmpty {
                    activeChallengesSection
                } else {
                    emptyStateView
                }

                // Streak Section
                if viewModel.currentStreak > 0 {
                    streakSection
                }

                // Badges Section
                badgesSection

                Spacer()
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadChallengeData()
        }
    }
}

// MARK: - Subviews

private extension ChildChallengesTabView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Text("⭐")
                .font(.system(size: 60))

            Text("Your Challenges")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Complete goals to earn bonus points!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Challenges")
                .font(.headline)
                .padding(.horizontal)

            ForEach(viewModel.activeChallenges) { challenge in
                ChildChallengeCard(
                    challenge: challenge,
                    progress: viewModel.challengeProgress[challenge.challengeID ?? ""]
                )
            }
        }
    }

    var streakSection: some View {
        VStack(spacing: 12) {
            Text("🔥")
                .font(.system(size: 80))

            Text("\(viewModel.currentStreak) Day Streak!")
                .font(.title)
                .fontWeight(.bold)

            Text("Keep it going! Come back tomorrow to continue your streak.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.1))
        )
    }

    var badgesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Badges")
                .font(.headline)
                .padding(.horizontal)

            // TODO: Implement badge grid in Phase 4
            Text("Badge system coming soon!")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Active Challenges")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Ask your parent to create a challenge for you!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }
}