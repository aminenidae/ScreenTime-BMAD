import SwiftUI
import FamilyControls
import ManagedSettings

struct AppUsageView: View {
    @StateObject private var viewModel = AppUsageViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Monitoring status
                    HStack {
                        Circle()
                            .fill(viewModel.isMonitoring ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(viewModel.isMonitoring ? "Monitoring Active" : "Monitoring Inactive")
                            .font(.caption)
                    }
                    .padding(.bottom)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Category summaries with time and reward points
                    HStack {
                        VStack {
                            Text("Learning")
                                .font(.headline)
                            Text(viewModel.formatTime(viewModel.learningTime))
                                .font(.title2)
                            Text("\(viewModel.learningRewardPoints) pts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(10)
                        
                        VStack {
                            Text("Reward")
                                .font(.headline)
                            Text(viewModel.formatTime(viewModel.rewardTime))
                                .font(.title2)
                            Text("\(viewModel.rewardRewardPoints) pts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    // Total reward points display
                    HStack {
                        VStack {
                            Text("Total Reward Points")
                                .font(.headline)
                            Text("\(viewModel.totalRewardPoints)")
                                .font(.title2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // Monitoring configuration
                    configurationSection

                    // ManagedSettings testing section (DEBUG only)
                    #if DEBUG
                    managedSettingsTestSection
                    #endif

                    // Category adjustment section
                    categoryAdjustmentSection

                    // App usage list
                    VStack(alignment: .leading) {
                        Text("App Usage")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.appUsages) { appUsage in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(appUsage.appName)
                                        .font(.headline)
                                    Text(appUsage.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Category: \(appUsage.category.rawValue)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text(viewModel.formatTime(appUsage.totalTime))
                                        .font(.headline)
                                    // Display reward points for this app
                                    Text("\(appUsage.earnedRewardPoints) pts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Control buttons
                    VStack {
                        HStack {
                            Button(action: {
                                viewModel.startMonitoring()
                            }) {
                                Text("Start Monitoring")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(viewModel.isMonitoring)
                            
                            Button(action: {
                                viewModel.stopMonitoring()
                            }) {
                                Text("Stop Monitoring")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(!viewModel.isMonitoring)
                        }
                        
                        Button(action: {
                            viewModel.resetData()
                        }) {
                            Text("Reset Data")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("ScreenTime Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        #if DEBUG
                        print("[AppUsageView] Picker button tapped - requesting authorization first")
                        #endif
                        viewModel.requestAuthorizationAndOpenPicker()
                    }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)  // Force full-width on iPad
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { newSelection in
            // Notify ViewModel that picker is working (cancel timeout)
            viewModel.onPickerSelectionChange()

            #if DEBUG
            print("[AppUsageView] FamilyActivitySelection changed!")
            print("[AppUsageView] Applications selected: \(newSelection.applications.count)")
            for (index, app) in newSelection.applications.enumerated() {
                print("[AppUsageView]   App \(index):")
                print("[AppUsageView]     Display Name: \(app.localizedDisplayName ?? "NIL ❌")")
                print("[AppUsageView]     Bundle ID: \(app.bundleIdentifier ?? "NIL (OK if display name exists)")")
                print("[AppUsageView]     Token: \(app.token != nil ? "✓" : "NIL ❌")")
            }
            #endif

            // Open category assignment view after selection
            if !newSelection.applications.isEmpty {
                #if DEBUG
                print("[AppUsageView] Opening category assignment for \(newSelection.applications.count) apps")
                #endif
                viewModel.isCategoryAssignmentPresented = true
            }
        }
        .alert("Picker Issue Detected", isPresented: $viewModel.pickerLoadingTimeout) {
            Button("Retry") {
                viewModel.retryPickerOpen()
            }
            Button("Cancel", role: .cancel) {
                viewModel.isFamilyPickerPresented = false
            }
        } message: {
            if let error = viewModel.pickerError {
                Text(error)
            } else {
                Text("The app selector is not responding. Please try again.")
            }
        }
        .sheet(isPresented: $viewModel.isCategoryAssignmentPresented) {
            CategoryAssignmentView(
                selection: viewModel.familySelection,
                categoryAssignments: $viewModel.categoryAssignments,
                rewardPoints: $viewModel.rewardPoints,
                fixedCategory: nil,  // Allow manual categorization in old view
                usageTimes: viewModel.getUsageTimes(),  // Pass usage times for display
                onSave: {
                    viewModel.onCategoryAssignmentSave()
                },
                onCancel: {
                    viewModel.cancelCategoryAssignment()
                }
            )
            // Task M: Pass ViewModel reference to CategoryAssignmentView for duplicate assignment validation
            .environmentObject(viewModel)
        }
    }
}

private extension AppUsageView {
    var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach([AppUsage.AppCategory.learning, AppUsage.AppCategory.reward], id: \.self) { category in
                    HStack {
                        Text(category.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.thresholdValue(for: category)) min")
                            .font(.footnote)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                        Stepper(
                            "",
                            value: Binding(
                                get: { viewModel.thresholdValue(for: category) },
                                set: { newValue in
                                    viewModel.thresholdMinutes[category] = newValue
                                }
                            ),
                            in: 1...120,
                            step: 1
                        )
                        .labelsHidden()
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            Button(action: {
                viewModel.configureMonitoring()
            }) {
                Text("Apply Monitoring Configuration")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }

    var managedSettingsTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🧪 ManagedSettings Testing")
                .font(.headline)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Test app blocking/unlocking functionality")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                // Shield status display
                let status = viewModel.getShieldStatus()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.red)
                            Text("Blocked: \(status.blocked)")
                                .font(.caption)
                        }
                        HStack {
                            Image(systemName: "lock.open.fill")
                                .foregroundColor(.green)
                            Text("Accessible: \(status.accessible)")
                                .font(.caption)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)

                // Test buttons
                Button(action: {
                    viewModel.testBlockRewardApps()
                }) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                        Text("Block Reward Apps")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    viewModel.testUnblockRewardApps()
                }) {
                    HStack {
                        Image(systemName: "lock.open.fill")
                        Text("Unblock Reward Apps")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    viewModel.testClearAllShields()
                }) {
                    HStack {
                        Image(systemName: "shield.slash.fill")
                        Text("Clear All Shields")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // Instructions
                VStack(alignment: .leading, spacing: 4) {
                    Text("Testing Instructions:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Assign apps to categories")
                    Text("2. Tap 'Block Reward Apps'")
                    Text("3. Exit this app (home button)")
                    Text("4. Try opening a Reward app")
                    Text("5. You should see a shield screen")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
    
    var categoryAdjustmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Management")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(spacing: 8) {
                Text("Adjust how your apps are categorized and how many reward points they earn.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    #if DEBUG
                    print("[AppUsageView] Reopen category assignment requested")
                    #endif
                    viewModel.openCategoryAssignmentForAdjustment()
                }) {
                    Text("Adjust Categories & Rewards")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
}

struct AppUsageView_Previews: PreviewProvider {
    static var previews: some View {
        AppUsageView()
    }
}
