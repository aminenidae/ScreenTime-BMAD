import SwiftUI

struct ChallengeBuilderView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var title = ""
    @State private var description = ""
    @State private var goalType: ChallengeGoalType = .dailyMinutes
    @State private var targetValue = 60
    @State private var bonusPercentage = 10
    @State private var selectedApps: [String] = []
    @State private var startDate = Date()
    @State private var endDate: Date?
    @State private var isActive = true
    @State private var showingAppPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    formSection
                }
                .padding()
            }
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChallenge()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("New Challenge")
                .font(.title)
                .fontWeight(.bold)
        }
    }

    private var formSection: some View {
        VStack(spacing: 20) {
            // Title field
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.headline)
                TextField("Enter challenge title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            // Description field
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                TextEditor(text: $description)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Goal Type picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Goal Type")
                    .font(.headline)
                Picker("Goal Type", selection: $goalType) {
                    ForEach(ChallengeGoalType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Target Value slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target Value")
                        .font(.headline)
                    Spacer()
                    Text("\(targetValue) \(targetValueUnit)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(targetValue) },
                    set: { targetValue = Int($0) }
                ), in: targetValueRange, step: targetValueStep)
            }

            // Bonus Percentage slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bonus Percentage")
                        .font(.headline)
                    Spacer()
                    Text("+\(bonusPercentage)%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(bonusPercentage) },
                    set: { bonusPercentage = Int($0) }
                ), in: 5...50, step: 5)
            }

            // App selection (for specific apps goal)
            if goalType == .specificApps {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Apps")
                        .font(.headline)
                    Button(action: {
                        showingAppPicker = true
                    }) {
                        HStack {
                            Text(selectedApps.isEmpty ? "Select Apps" : "\(selectedApps.count) apps selected")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            // Date pickers
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.headline)
                
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                
                Toggle("Set End Date", isOn: Binding(
                    get: { endDate != nil },
                    set: { isOn in
                        endDate = isOn ? Date().addingTimeInterval(86400 * 7) : nil // Default to 1 week
                    }
                ))
                
                if let endDate = endDate {
                    DatePicker("End Date", selection: Binding(
                        get: { endDate },
                        set: { newDate in
                            self.endDate = newDate
                        }
                    ), displayedComponents: .date)
                }
            }

            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var targetValueRange: ClosedRange<Double> {
        switch goalType {
        case .dailyMinutes:
            return 15...240
        case .weeklyMinutes:
            return 60...1440
        case .specificApps:
            return 30...720
        case .streak:
            return 3...30
        }
    }

    private var targetValueStep: Double {
        switch goalType {
        case .streak:
            return 1
        default:
            return 15
        }
    }

    private var targetValueUnit: String {
        switch goalType {
        case .dailyMinutes, .weeklyMinutes, .specificApps:
            return "minutes"
        case .streak:
            return "days"
        }
    }

    private func saveChallenge() {
        Task {
            await viewModel.createChallenge(
                title: title,
                description: description,
                goalType: goalType.rawValue,
                targetValue: targetValue,
                bonusPercentage: bonusPercentage,
                targetApps: selectedApps.isEmpty ? nil : selectedApps,
                startDate: startDate,
                endDate: endDate,
                createdBy: DeviceModeManager.shared.deviceID,
                assignedTo: DeviceModeManager.shared.deviceID // TODO: Get from parent-child relationship
            )
            presentationMode.wrappedValue.dismiss()
        }
    }
}