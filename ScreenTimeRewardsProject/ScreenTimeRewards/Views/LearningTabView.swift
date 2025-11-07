import SwiftUI
import FamilyControls
import ManagedSettings

struct LearningTabView: View {
    @EnvironmentObject var viewModel: AppUsageViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme

    private var hasLearningApps: Bool {
        !viewModel.learningSnapshots.isEmpty
    }

    // Calculate total points per hour from all learning apps
    private var totalPointsPerHour: Int {
        viewModel.learningSnapshots.reduce(0) { sum, snapshot in
            sum + (snapshot.pointsPerMinute * 60)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Colors.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                navigationBar

                // Main Content
                ScrollView {
                    VStack(spacing: 0) {
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        if !viewModel.learningSnapshots.isEmpty {
                            selectedAppsSection
                        }

                        // Bottom padding for FAB
                        Color.clear.frame(height: 100)
                    }
                }
            }

            // Floating Action Button
            addAppsButton
        }
        .navigationBarHidden(true)
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
    }
}

private extension LearningTabView {
    // MARK: - Navigation Bar
    var navigationBar: some View {
        HStack(spacing: 0) {
            // Back Button
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Colors.text(for: colorScheme))
                    .frame(width: 48, height: 48)
            }

            Spacer()

            // Title
            Text("Learning Apps")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Colors.text(for: colorScheme))

            Spacer()

            // Spacer for centering
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Colors.card(for: colorScheme)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    // MARK: - Summary Card
    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total Learning Points per Hour")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Colors.text(for: colorScheme))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalPointsPerHour)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Colors.actionBlue)
                        .tracking(-0.5)

                    Text("This is the total potential points your child can earn every hour from the selected apps.")
                        .font(.system(size: 14))
                        .foregroundColor(Colors.lightSlateGray(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Colors.mutedTeal(for: colorScheme))
        .cornerRadius(12)
    }

    // MARK: - Selected Apps Section
    var selectedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Apps")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Colors.text(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(viewModel.learningSnapshots) { snapshot in
                    learningAppRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - App Row
    @ViewBuilder
    func learningAppRow(snapshot: LearningAppSnapshot) -> some View {
        HStack(spacing: 16) {
            // App Icon
            if #available(iOS 15.2, *) {
                Label(snapshot.token)
                    .labelStyle(.iconOnly)
                    .frame(width: 56, height: 56)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "app.fill")
                            .foregroundColor(.gray)
                    )
            }

            // App Info
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName.isEmpty ? "Learning App" : snapshot.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.text(for: colorScheme))
                    .lineLimit(1)

                Text("+\(snapshot.pointsPerMinute * 60) Points/hour")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.lightSlateGray(for: colorScheme))
                    .lineLimit(2)
            }

            Spacer()

            // Remove Button
            Button(action: {
                removeLearningApp(snapshot.token)
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Colors.softRed)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .frame(minHeight: 72)
        .background(
            Colors.card(for: colorScheme)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Add Apps Button (FAB)
    var addAppsButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    Colors.background(for: colorScheme).opacity(0),
                    Colors.background(for: colorScheme)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Button(action: {
                viewModel.pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
                viewModel.presentPickerWithRetry(for: .learning)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add Learning App")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Colors.actionBlue)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Colors.background(for: colorScheme))
        }
    }

    // MARK: - Helper Methods
    private func removeLearningApp(_ token: ApplicationToken) {
        #if DEBUG
        let appName = viewModel.resolvedDisplayName(for: token) ?? "Unknown App"
        print("[LearningTabView] Requesting removal of learning app: \(appName)")
        #endif

        let warningMessage = viewModel.getRemovalWarningMessage(for: token)
        #if DEBUG
        print("[LearningTabView] Removal warning: \(warningMessage)")
        #endif

        viewModel.removeApp(token)
    }
}

// MARK: - Design Tokens
private extension LearningTabView {
    struct Colors {
        // Primary Colors
        static let actionBlue = Color(hex: "137fec")
        static let softRed = Color(hex: "ef4444")

        // Background Colors
        static func background(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "101922") : Color(hex: "f6f7f8")
        }

        // Card Colors
        static func card(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "1d2935") : Color(hex: "ffffff")
        }

        // Teal Colors (for summary card)
        static func mutedTeal(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "1a3b3a") : Color(hex: "e0f2f1")
        }

        // Text Colors
        static func text(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "e1e3e5") : Color(hex: "111418")
        }

        static func lightSlateGray(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color.gray.opacity(0.8) : Color(hex: "617589")
        }
    }
}

struct LearningTabView_Previews: PreviewProvider {
    static var previews: some View {
        LearningTabView()
            .environmentObject(AppUsageViewModel())
    }
}
