import SwiftUI
import FamilyControls
import ManagedSettings

struct ChallengeBuilderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appUsageViewModel: AppUsageViewModel
    @StateObject private var challengeViewModel = ChallengeViewModel()
    @State private var title = ""
    @State private var description = ""
    @State private var goalType: ChallengeGoalType = .dailyQuest
    @State private var targetMinutes: Double = 60
    @State private var targetPoints: Double = 500
    @State private var streakDays = 7
    @State private var bonusPercentage = 10
    @State private var selectedLearningAppIDs: Set<String> = []
    @State private var selectedRewardAppIDs: Set<String> = []
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hasEndDate = false
    @State private var activeDays: Set<Int> = [1, 2, 3, 4, 5] // Mon-Fri
    @State private var startTime = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var repeatWeekly = true
    private let contentMaxWidth: CGFloat = 560

    var body: some View {
        ZStack {
            Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Navigation Bar
                customNavBar

                // Main content
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 0) {
                            challengeDetailsSection
                            setTheGoalSection
                            defineRewardSection
                            scheduleSection
                        }
                        .padding(.bottom, 100) // Space for fixed bottom button
                        .frame(maxWidth: contentMaxWidth, alignment: .center)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Fixed bottom button
            VStack {
                Spacer()
                bottomActionButton
            }
        }
        .navigationBarHidden(true)
        .onChange(of: goalType) { newValue in
            normalizeTargets(for: newValue)
        }
    }

    // MARK: - Custom Navigation Bar
    private var customNavBar: some View {
        HStack(spacing: 0) {
            // Back button
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Colors.primary)
                    .frame(width: 48, height: 48)
            }

            Spacer()

            // Title
            Text("New Challenge")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Colors.text)

            Spacer()

            // Save button
            Button(action: {
                saveChallenge()
            }) {
                Text("Save")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(title.isEmpty ? Colors.text.opacity(0.3) : Colors.primary)
                    .frame(width: 48, height: 48)
            }
            .disabled(title.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Colors.background.opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Colors.border),
            alignment: .bottom
        )
    }

    // MARK: - Challenge Details Section
    private var challengeDetailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Challenge Details")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.top, 32)
                .padding(.bottom, 8)

            // Content card
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Challenge Name")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    TextField("e.g., Weekday Reading Goal", text: $title)
                        .font(.system(size: 16))
                        .foregroundColor(Colors.text)
                        .padding(12)
                        .background(Colors.inputBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Colors.border, lineWidth: 1)
                        )
                }

                Divider()
                    .background(Colors.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    TextField("Add details about this challenge...", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 16))
                        .foregroundColor(Colors.text)
                        .padding(12)
                        .background(Colors.inputBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Colors.border, lineWidth: 1)
                        )
                }

                Divider()
                    .background(Colors.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Type")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    Picker("Goal Type", selection: $goalType) {
                        ForEach(ChallengeGoalType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Colors.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.border, lineWidth: 1)
                            .background(Colors.inputBackground.cornerRadius(8))
                    )
                }
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Set The Goal Section
    private var setTheGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Set The Goal")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.top, 32)
                .padding(.bottom, 8)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(goalValueTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Colors.text)

                        Spacer()

                        Text(formattedGoalValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Colors.primary)
                    }

                    goalInputControl
                }

                Divider()
                    .background(Colors.border)

                learningAppSelection
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Define Reward Section
    private var defineRewardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Define The Reward")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.top, 32)
                .padding(.bottom, 8)

            VStack(spacing: 16) {
                rewardAppSelection

                Divider()
                    .background(Colors.border)

                bonusPicker

                if !selectedRewardAppIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        let count = selectedRewardAppIDs.count
                        let appText = count == 1 ? "Reward App" : "Reward Apps"
                        Text("Complete this challenge to unlock your \(appText).")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Colors.text)

                        Text("Bonus duration: \(bonusUnlockDurationText)")
                            .font(.system(size: 13))
                            .foregroundColor(Colors.text.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Schedule Section
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Schedule")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.top, 32)
                .padding(.bottom, 8)

            // Content card
            VStack(spacing: 0) {
                // Active Days
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Days")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    HStack(spacing: 0) {
                        ForEach(0..<7) { index in
                            let isSelected = activeDays.contains(index)
                            Button(action: {
                                if isSelected {
                                    activeDays.remove(index)
                                } else {
                                    activeDays.insert(index)
                                }
                            }) {
                                Text(dayLabel(for: index))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isSelected ? .white : Colors.text)
                                    .frame(width: 40, height: 40)
                                    .background(isSelected ? Colors.primary : Colors.inputBackground)
                                    .clipShape(Circle())
                            }
                            if index < 6 {
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)

                Divider()
                    .background(Colors.border)
                    .padding(.leading, 16)

                // From time
                HStack {
                    Text("From")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)
                    Spacer()
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accentColor(Colors.primary)
                }
                .padding(16)

                Divider()
                    .background(Colors.border)
                    .padding(.leading, 16)

                // To time
                HStack {
                    Text("To")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)
                    Spacer()
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accentColor(Colors.primary)
                }
                .padding(16)

                Divider()
                    .background(Colors.border)
                    .padding(.leading, 16)

                // Repeat Weekly toggle
                HStack {
                    Text("Repeat Weekly")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)
                    Spacer()
                    Toggle("", isOn: $repeatWeekly)
                        .labelsHidden()
                        .tint(Colors.primary)
                }
                .padding(16)

                Divider()
                    .background(Colors.border)
                    .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Set End Date", isOn: $hasEndDate)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)
                        .tint(Colors.primary)

                    if hasEndDate {
                        DatePicker(
                            "End Date",
                            selection: $endDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .tint(Colors.primary)
                    }
                }
                .padding(16)
            }
            .background(Colors.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Bottom Action Button
    private var bottomActionButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Colors.background.opacity(0), Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)

            Button(action: {
                saveChallenge()
            }) {
                Text("Create Challenge")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Colors.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Colors.background)
        }
    }

    // MARK: - Helper Functions
    private func dayLabel(for index: Int) -> String {
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        return days[index]
    }

    private var goalValueTitle: String {
        return "Daily Minutes Goal"
    }

    private var formattedGoalValue: String {
        return "\(Int(targetMinutes)) min"
    }

    @ViewBuilder
    private var goalInputControl: some View {
        switch goalType {
        case .dailyQuest:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.gray)
                    Slider(
                        value: $targetMinutes,
                        in: minuteRange(for: goalType),
                        step: minuteStep(for: goalType)
                    )
                    .accentColor(Colors.primary)
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .foregroundColor(.gray)
                }

                HStack {
                    Text("\(Int(minuteRange(for: goalType).lowerBound)) min")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(minuteRange(for: goalType).upperBound)) min")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private func minuteRange(for type: ChallengeGoalType) -> ClosedRange<Double> {
        return 15...240
    }

    private func minuteStep(for type: ChallengeGoalType) -> Double {
        return 5
    }

    private var pointsTargetRange: ClosedRange<Double> {
        100...1000
    }

    private var learningAppSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Learning Apps")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.text)
                Spacer()
                if !selectedLearningAppIDs.isEmpty {
                    Text("\(selectedLearningAppIDs.count) selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Colors.primary)
                }
            }

            if appUsageViewModel.learningSnapshots.isEmpty {
                Text("Add learning apps from the Learning tab to target them here.")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.text.opacity(0.7))
            } else {
                VStack(spacing: 8) {
                    ForEach(appUsageViewModel.learningSnapshots) { snapshot in
                        AppSelectionRow(
                            token: snapshot.token,
                            displayName: appUsageViewModel.resolvedDisplayName(for: snapshot.token) ?? snapshot.displayName,
                            isSelected: selectedLearningAppIDs.contains(snapshot.logicalID),
                            onToggle: { toggleLearningApp(snapshot.logicalID) }
                        )
                    }
                }
            }

            if selectedLearningAppIDs.isEmpty {
                Text("All learning apps count if none are selected.")
                    .font(.system(size: 13))
                    .foregroundColor(Colors.text.opacity(0.7))
            } else {
                let count = selectedLearningAppIDs.count
                let appText = count == 1 ? "Learning App" : "Learning Apps"
                Text("Tracking \(count) \(appText)")
                    .font(.system(size: 13))
                    .foregroundColor(Colors.text.opacity(0.8))
            }
        }
    }

    private var rewardAppSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reward Apps")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.text)
                Spacer()
                if !selectedRewardAppIDs.isEmpty {
                    Text("\(selectedRewardAppIDs.count) selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Colors.primary)
                }
            }

            if appUsageViewModel.rewardSnapshots.isEmpty {
                Text("Assign apps to the Reward category to unlock them as prizes.")
                    .font(.system(size: 14))
                    .foregroundColor(Colors.text.opacity(0.7))
            } else {
                VStack(spacing: 8) {
                    ForEach(appUsageViewModel.rewardSnapshots) { snapshot in
                        AppSelectionRow(
                            token: snapshot.token,
                            displayName: appUsageViewModel.resolvedDisplayName(for: snapshot.token) ?? (snapshot.displayName.isEmpty ? "Reward App" : snapshot.displayName),
                            isSelected: selectedRewardAppIDs.contains(snapshot.logicalID),
                            onToggle: { toggleRewardApp(snapshot.logicalID) }
                        )
                    }
                }
            }
        }
    }

    private var bonusPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bonus Percentage")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Colors.text)
                Spacer()
                Text("+\(bonusPercentage)%")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Colors.primary)
            }

            Picker("Bonus Percentage", selection: $bonusPercentage) {
                ForEach(bonusOptions, id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectedLearningDisplayNames: [String] {
        // Don't show any text - the UI already shows "4 selected" which is sufficient
        []
    }

    private var selectedRewardDisplayNames: [String] {
        // Don't show any text - the UI already shows count which is sufficient
        []
    }

    private var learningSnapshotsByID: [String: LearningAppSnapshot] {
        appUsageViewModel.learningSnapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.logicalID] = snapshot
        }
    }

    private var rewardSnapshotsByID: [String: RewardAppSnapshot] {
        appUsageViewModel.rewardSnapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.logicalID] = snapshot
        }
    }

    private var bonusOptions: [Int] {
        [5, 10, 15, 20, 25]
    }

    private let baseRewardUnlockMinutes = 30

    private var bonusUnlockDurationText: String {
        let bonusDuration = baseRewardUnlockMinutes + (baseRewardUnlockMinutes * bonusPercentage / 100)
        let appText = selectedRewardAppIDs.count == 1 ? "" : " each"
        return "\(bonusDuration) minutes\(appText)"
    }

    private var appGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 90), spacing: 12)]
    }

    private func toggleLearningApp(_ logicalID: String) {
        if selectedLearningAppIDs.contains(logicalID) {
            selectedLearningAppIDs.remove(logicalID)
        } else {
            selectedLearningAppIDs.insert(logicalID)
        }
    }

    private func toggleRewardApp(_ logicalID: String) {
        if selectedRewardAppIDs.contains(logicalID) {
            selectedRewardAppIDs.remove(logicalID)
        } else {
            selectedRewardAppIDs.insert(logicalID)
        }
    }

    private func normalizeTargets(for goalType: ChallengeGoalType) {
        let range = minuteRange(for: goalType)
        targetMinutes = min(max(targetMinutes, range.lowerBound), range.upperBound)
    }

    private func saveChallenge() {
        let targetValue = Int(targetMinutes)

        let learningIDs = Array(selectedLearningAppIDs)
        let rewardIDs = Array(selectedRewardAppIDs)
        let activeDayList = activeDays.isEmpty ? nil : Array(activeDays).sorted()
        let creatorID = DeviceModeManager.shared.deviceID

        Task {
            await challengeViewModel.createChallenge(
                title: title,
                description: description,
                goalType: goalType,
                targetValue: targetValue,
                bonusPercentage: bonusPercentage,
                targetApps: learningIDs.isEmpty ? nil : learningIDs,
                rewardApps: rewardIDs.isEmpty ? nil : rewardIDs,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                activeDays: activeDayList,
                startTime: startTime,
                endTime: endTime,
                createdBy: creatorID,
                assignedTo: creatorID
            )
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Design Tokens
extension ChallengeBuilderView {
    struct Colors {
        static let primary = Color(hex: "#007AFF")
        static let secondary = Color(hex: "#34C759")
        static let background = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#000000") : UIColor(hex: "#F2F2F7")
        })
        static let cardBackground = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#1C1C1E") : UIColor.white
        })
        static let inputBackground = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#2C2C2E") : UIColor(hex: "#F2F2F7")
        })
        static let text = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#F2F2F7") : UIColor(hex: "#1C1C1E")
        })
        static let border = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#3A3A3C") : UIColor(hex: "#E5E5EA")
        })
    }
}

struct AppSelectionButton: View {
    let token: ManagedSettings.ApplicationToken
    let displayName: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    // App icon with proper sizing
                    if #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.iconOnly)
                            .scaleEffect(2.2)
                            .frame(width: 56, height: 56)
                            .clipped()
                            .background(Color.clear)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.gray)
                            )
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(ChallengeBuilderView.Colors.primary)
                            .background(Circle().fill(Color.white).padding(2))
                            .offset(x: 4, y: -4)
                    }
                }

                // Use Label with smaller font (8pt) for long names
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(ChallengeBuilderView.Colors.text)
                        .multilineTextAlignment(.center)
                        .frame(width: 82, height: 28)
                } else {
                    Text(displayName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(ChallengeBuilderView.Colors.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .frame(width: 82, height: 28)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(width: 90)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                        ? ChallengeBuilderView.Colors.primary.opacity(0.08)
                        : ChallengeBuilderView.Colors.inputBackground
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? ChallengeBuilderView.Colors.primary : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct AppSelectionRow: View {
    let token: ManagedSettings.ApplicationToken
    let displayName: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // App icon - standardized smaller size
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.35)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        )
                }

                // App name
                VStack(alignment: .leading, spacing: 4) {
                    if #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderView.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(displayName.isEmpty ? "App" : displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderView.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(12)
            .frame(height: 88)
            .background(isSelected ? ChallengeBuilderView.Colors.primary.opacity(0.1) : ChallengeBuilderView.Colors.inputBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? ChallengeBuilderView.Colors.primary : ChallengeBuilderView.Colors.border.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
