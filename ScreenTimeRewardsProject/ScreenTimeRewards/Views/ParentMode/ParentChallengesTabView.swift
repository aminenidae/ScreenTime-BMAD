import SwiftUI

struct ParentChallengesTabView: View {
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingChallengeBuilder = false
    @State private var showSubscriptionPaywall = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabTopBar(title: "Challenges", style: challengeTopBarStyle) {
                    sessionManager.exitToSelection()
                }

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
        }
        .sheet(isPresented: $showingChallengeBuilder) {
            ChallengeBuilderFlowView(viewModel: viewModel)
                .environmentObject(appUsageViewModel)
        }
        .task {
            await viewModel.loadChallenges()
        }
    }
}

// MARK: - Subviews

private extension ParentChallengesTabView {
    var challengeTopBarStyle: TabTopBarStyle {
        TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.sunnyYellow,
            iconBackground: AppTheme.card(for: colorScheme),
            dividerColor: AppTheme.border(for: colorScheme)
        )
    }

    var headerSection: some View {
        VStack(spacing: 8) {
            // Gradient circle with trophy
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.sunnyYellow.opacity(0.3), AppTheme.playfulCoral.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            Text("Challenges")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Motivate learning with goals and rewards")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    var createChallengeButton: some View {
        Button(action: {
            if subscriptionManager.canCreateChallenge {
                showingChallengeBuilder = true
            } else {
                showSubscriptionPaywall = true
            }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Create Custom Challenge")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.vibrantTeal)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView()
        }
    }

    var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Active Challenges")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                ZStack {
                    Circle()
                        .fill(AppTheme.sunnyYellow.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Text("\(viewModel.activeChallenges.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }
            .padding(.horizontal)

            // Use adaptive grid: 2 columns on iPad (regular width), 1 on iPhone (compact width)
            let columns = horizontalSizeClass == .regular ? [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ] : [
                GridItem(.flexible())
            ]

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.activeChallenges) { challenge in
                    NavigationLink(
                        destination: ChallengeDetailView(
                            challenge: challenge,
                            progress: viewModel.challengeProgress[challenge.challengeID ?? ""]
                        )
                        .environmentObject(appUsageViewModel)
                    ) {
                        ParentChallengeCard(
                            challenge: challenge,
                            progress: viewModel.challengeProgress[challenge.challengeID ?? ""]
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))

            Text("No Active Challenges")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("Create a challenge to motivate your child's learning")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
}
