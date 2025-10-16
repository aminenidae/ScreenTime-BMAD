import SwiftUI
import FamilyControls
import ManagedSettings

struct AppUsageView: View {
    @StateObject private var viewModel = AppUsageViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
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
                
                // Category summaries
                HStack {
                    VStack {
                        Text("Educational")
                            .font(.headline)
                        Text(viewModel.formatTime(viewModel.educationalTime))
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(10)
                    
                    VStack {
                        Text("Entertainment")
                            .font(.headline)
                        Text(viewModel.formatTime(viewModel.entertainmentTime))
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // Monitoring configuration
                configurationSection

                // App usage list
                List(viewModel.appUsages) { appUsage in
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
                        
                        Text(viewModel.formatTime(appUsage.totalTime))
                            .font(.headline)
                    }
                }
                
                // Control buttons
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
                .padding(.horizontal)
                
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
                .padding(.horizontal)
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
        .familyActivityPicker(isPresented: $viewModel.isFamilyPickerPresented, selection: $viewModel.familySelection)
        .onChange(of: viewModel.familySelection) { newSelection in
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
        .sheet(isPresented: $viewModel.isCategoryAssignmentPresented) {
            CategoryAssignmentView(
                selection: viewModel.familySelection,
                categoryAssignments: $viewModel.categoryAssignments,
                onSave: {
                    viewModel.onCategoryAssignmentSave()
                }
            )
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
                ForEach(AppUsage.AppCategory.allCases, id: \.self) { category in
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
                            in: 5...120,
                            step: 5
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
            
            #if DEBUG
            Button(action: {
                #if DEBUG
                print("[AppUsageView] Configure with Test Applications button tapped")
                #endif
                viewModel.configureWithTestApplications()
            }) {
                Text("Configure with Test Applications")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            #endif
        }
        .padding(.bottom)
    }
}

struct AppUsageView_Previews: PreviewProvider {
    static var previews: some View {
        AppUsageView()
    }
}
