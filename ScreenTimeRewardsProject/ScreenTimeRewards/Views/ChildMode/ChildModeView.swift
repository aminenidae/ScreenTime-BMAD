import SwiftUI

struct ChildModeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            Group {
                if viewModel.activeChallenges.count == 1,
                   let singleChallenge = viewModel.activeChallenges.first {
                    // Single challenge: Show detail view directly as main view
                    SingleChallengeMainView(
                        challenge: singleChallenge,
                        progress: viewModel.challengeProgress[singleChallenge.challengeID ?? ""]
                    )
                    .environmentObject(viewModel)
                    .environmentObject(sessionManager)
                } else {
                    // Multiple challenges or none: Show tab view
                    ChildChallengesTabView()
                        .environmentObject(viewModel)
                        .environmentObject(sessionManager)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Ensure challenges are loaded
            Task {
                await viewModel.loadChallengeData()
            }
        }
    }
}

/// Wrapper view for single challenge mode - shows challenge detail as the main child view
struct SingleChallengeMainView: View {
    let challenge: Challenge
    let progress: ChallengeProgress?
    @EnvironmentObject var viewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            // Embed the challenge detail content directly
            ChildChallengeDetailView(
                challenge: challenge,
                progress: progress
            )
            .environmentObject(viewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(challenge.title ?? "Today's Quest")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    sessionManager.exitToSelection()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }
}

struct ChildModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChildModeView()
            .environmentObject(SessionManager.shared)
            .environmentObject(AppUsageViewModel())
    }
}
