import SwiftUI
import FamilyControls
import ManagedSettings

struct LearningTabView: View {
    @StateObject private var viewModel = AppUsageViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header info
                    VStack(spacing: 8) {
                        Text("Learning Apps")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Apps that earn points when used")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    // Total points earned display
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

                    // Selected learning apps list
                    if !viewModel.learningApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Selected Learning Apps (\(viewModel.learningApps.count))")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(viewModel.learningApps.enumerated()), id: \.offset) { index, token in
                                HStack {
                                    if #available(iOS 15.2, *) {
                                        Label(token)
                                            .font(.body)
                                    } else {
                                        Text("Learning App \(index + 1)")
                                            .font(.body)
                                    }

                                    Spacer()

                                    if let earnRate = viewModel.rewardPoints[token] {
                                        Text("+\(earnRate) pts/min")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Add learning apps button
                    Button(action: {
                        viewModel.requestAuthorizationAndOpenPicker()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(viewModel.learningApps.isEmpty ? "Select Learning Apps" : "Add More Apps")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // View all learning apps button - only show if there are learning apps
                    if !viewModel.learningApps.isEmpty {
                        Button(action: {
                            viewModel.isCategoryAssignmentPresented = true
                        }) {
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
                fixedCategory: .learning,  // Auto-categorize as Learning
                usageTimes: viewModel.getUsageTimes(),  // Pass usage times for display
                onSave: {
                    viewModel.onCategoryAssignmentSave()

                    // Start monitoring usage (no shield for learning apps)
                    viewModel.startMonitoring()
                }
            )
        }
    }
}

struct LearningTabView_Previews: PreviewProvider {
    static var previews: some View {
        LearningTabView()
    }
}
