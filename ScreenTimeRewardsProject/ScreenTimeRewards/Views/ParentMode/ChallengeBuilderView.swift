import SwiftUI

struct ChallengeBuilderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var title = ""
    @State private var description = ""
    @State private var goalType: ChallengeGoalType = .dailyMinutes
    @State private var targetValue = 60
    @State private var bonusPercentage = 10
    @State private var selectedLearningApps: [String] = []
    @State private var selectedRewardApps: [String] = []
    @State private var startDate = Date()
    @State private var endDate: Date?
    @State private var isActive = true
    @State private var showingAppPicker = false
    @State private var errorMessage: String?
    @State private var activeDays: Set<Int> = [1, 2, 3, 4, 5] // Mon-Fri
    @State private var startTime = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var repeatWeekly = true

    var body: some View {
        ZStack {
            Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Navigation Bar
                customNavBar

                // Main content
                ScrollView {
                    VStack(spacing: 0) {
                        challengeDetailsSection
                        setTheGoalSection
                        defineRewardSection
                        scheduleSection
                    }
                    .padding(.bottom, 100) // Space for fixed bottom button
                }
            }

            // Fixed bottom button
            VStack {
                Spacer()
                bottomActionButton
            }
        }
        .navigationBarHidden(true)
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
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 8)

            // Content card
            VStack(spacing: 16) {
                // Challenge Name
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

                // Goal Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Type")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    CustomSegmentedControl(
                        selection: $goalType,
                        options: [.dailyMinutes, .weeklyMinutes],
                        labels: ["Time Spent", "Tasks Completed"]
                    )
                }
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Set The Goal Section
    private var setTheGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Set The Goal")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 8)

            // Content card
            VStack(spacing: 16) {
                // Duration slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Colors.text)
                        Spacer()
                        Text("\(targetValue) min")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Colors.primary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .foregroundColor(.gray)

                        Slider(value: Binding(
                            get: { Double(targetValue) },
                            set: { targetValue = Int($0) }
                        ), in: 0...120, step: 5)
                        .accentColor(Colors.primary)

                        Image(systemName: "hourglass.bottomhalf.filled")
                            .foregroundColor(.gray)
                    }
                }

                Divider()
                    .background(Colors.border)

                // Learning Apps
                VStack(alignment: .leading, spacing: 12) {
                    Text("Learning Apps")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        // Selected app examples (placeholder)
                        AppIconView(name: "Khan Kids", isSelected: true, onTap: {})
                        AppIconView(name: "Duolingo", isSelected: false, onTap: {})
                        AppIconView(name: "Brilliant", isSelected: false, onTap: {})
                        AddAppButton(onTap: {})
                    }
                }
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Define Reward Section
    private var defineRewardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Define The Reward")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 8)

            // Content card
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reward Apps")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Colors.text)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        // Selected app examples (placeholder)
                        AppIconView(name: "YT Kids", isSelected: true, onTap: {})
                        AppIconView(name: "TikTok", isSelected: false, onTap: {})
                        AppIconView(name: "Roblox", isSelected: false, onTap: {})
                        AddAppButton(onTap: {})
                    }
                }
            }
            .padding(16)
            .background(Colors.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Schedule Section
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Schedule")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Colors.text)
                .padding(.horizontal, 16)
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
            }
            .background(Colors.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 16)
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
                targetApps: selectedLearningApps.isEmpty ? nil : selectedLearningApps,
                startDate: startDate,
                endDate: endDate,
                createdBy: DeviceModeManager.shared.deviceID,
                assignedTo: DeviceModeManager.shared.deviceID
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

// MARK: - Custom Segmented Control
struct CustomSegmentedControl: View {
    @Binding var selection: ChallengeGoalType
    let options: [ChallengeGoalType]
    let labels: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(zip(options.indices, options)), id: \.0) { index, option in
                Button(action: {
                    selection = option
                }) {
                    Text(labels[index])
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(selection == option ? ChallengeBuilderView.Colors.primary : ChallengeBuilderView.Colors.text.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            selection == option ?
                            (colorScheme == .dark ? Color(hex: "#3A3A3C") : .white) :
                            Color.clear
                        )
                        .cornerRadius(6)
                        .shadow(color: selection == option ? .black.opacity(0.1) : .clear, radius: 2, y: 1)
                }
            }
        }
        .padding(4)
        .background(ChallengeBuilderView.Colors.inputBackground)
        .cornerRadius(8)
    }
}

// MARK: - App Icon View
struct AppIconView: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? ChallengeBuilderView.Colors.secondary : Color.clear, lineWidth: 2)
                        )

                    if isSelected {
                        Circle()
                            .fill(ChallengeBuilderView.Colors.secondary)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 4, y: -4)
                    }
                }

                Text(name)
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderView.Colors.text.opacity(0.9))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Add App Button
struct AddAppButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ChallengeBuilderView.Colors.inputBackground)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(ChallengeBuilderView.Colors.primary)
                    )

                Text("Add App")
                    .font(.system(size: 12))
                    .foregroundColor(ChallengeBuilderView.Colors.primary)
                    .lineLimit(1)
            }
        }
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