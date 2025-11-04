import SwiftUI

struct ParentChallengesTabView: View {
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingChallengeBuilder = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 1.0, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Create Challenge Button
                    createChallengeButton

                    // Active Challenges List
                    if !viewModel.activeChallenges.isEmpty {
                        activeChallengesSection
                    } else {
                        emptyStateView
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChallengeBuilder) {
            ChallengeBuilderView()
        }
        .task {
            await viewModel.loadChallenges()
        }
    }
}

// MARK: - Subviews

private extension ParentChallengesTabView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Challenges")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Motivate learning with goals and rewards")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    var createChallengeButton: some View {
        Button(action: {
            showingChallengeBuilder = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Create Custom Challenge")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Challenges (\(viewModel.activeChallenges.count))")
                .font(.headline)
                .padding(.horizontal)

            ForEach(viewModel.activeChallenges) { challenge in
                NavigationLink(destination: ChallengeDetailView(challenge: challenge)) {
                    ParentChallengeCard(challenge: challenge, progress: viewModel.challengeProgress[challenge.challengeID ?? ""])
                }
                .buttonStyle(PlainButtonStyle())
            }
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

            Text("Create a challenge to motivate your child's learning")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
}