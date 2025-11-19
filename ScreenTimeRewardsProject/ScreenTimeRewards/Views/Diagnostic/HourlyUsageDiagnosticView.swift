//
//  HourlyUsageDiagnosticView.swift
//  ScreenTimeRewards
//
//  Created for diagnostic purposes to track hourly usage patterns
//

import SwiftUI
import Charts
import Combine

/// Diagnostic view showing hourly usage breakdown for each app
/// Helps identify iOS Screen Time API overcounting patterns
@available(iOS 16.0, *)
struct HourlyUsageDiagnosticView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var diagnosticData = HourlyUsageDiagnosticData.shared

    let category: AppUsage.AppCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(headerColor)

                Text("Hourly Usage (Diagnostic)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Button(action: {
                    diagnosticData.clearData()
                }) {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(headerColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if diagnosticData.hasData(for: category) {
                // Chart
                Chart {
                    ForEach(diagnosticData.getHourlyData(for: category), id: \.hour) { dataPoint in
                        BarMark(
                            x: .value("Hour", hourLabel(dataPoint.hour)),
                            y: .value("Minutes", dataPoint.minutes)
                        )
                        .foregroundStyle(barColor)
                        .annotation(position: .top) {
                            if dataPoint.minutes > 0 {
                                Text("\(dataPoint.minutes)m")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(height: 180)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Stats
                HStack(spacing: 16) {
                    statItem(
                        icon: "clock.fill",
                        label: "Total Today",
                        value: "\(diagnosticData.getTotalMinutes(for: category))m"
                    )

                    Divider()
                        .frame(height: 30)

                    statItem(
                        icon: "chart.line.uptrend.xyaxis",
                        label: "Events Fired",
                        value: "\(diagnosticData.getTotalEvents(for: category))"
                    )

                    Divider()
                        .frame(height: 30)

                    statItem(
                        icon: "exclamationmark.triangle.fill",
                        label: "Rejected",
                        value: "\(diagnosticData.getRejectedEvents(for: category))"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                Text("No usage data recorded yet")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            diagnosticData.startTracking()
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }

    @ViewBuilder
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    private var headerColor: Color {
        category == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }

    private var barColor: Color {
        category == .learning ? AppTheme.vibrantTeal : AppTheme.playfulCoral
    }
}

// MARK: - Data Model

@MainActor
class HourlyUsageDiagnosticData: ObservableObject {
    static let shared = HourlyUsageDiagnosticData()

    struct HourlyDataPoint {
        let hour: Int
        let minutes: Int
        let eventCount: Int
    }

    @Published private var learningHourlyUsage: [Int: Int] = [:]  // hour -> minutes
    @Published private var rewardHourlyUsage: [Int: Int] = [:]
    @Published private var learningEventCount: [Int: Int] = [:]   // hour -> event count
    @Published private var rewardEventCount: [Int: Int] = [:]
    @Published private var learningRejectedCount: Int = 0
    @Published private var rewardRejectedCount: Int = 0

    private var isTracking = false

    private init() {}

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true

        // Subscribe to Screen Time notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScreenTimeThresholdFired"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleThresholdFired(notification)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScreenTimeEventRejected"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleEventRejected(notification)
        }
    }

    private func handleThresholdFired(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let category = userInfo["category"] as? String,
              let duration = userInfo["duration"] as? TimeInterval else {
            return
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minutes = Int(duration / 60)

        if category == "learning" {
            learningHourlyUsage[hour, default: 0] += minutes
            learningEventCount[hour, default: 0] += 1
        } else if category == "reward" {
            rewardHourlyUsage[hour, default: 0] += minutes
            rewardEventCount[hour, default: 0] += 1
        }
    }

    private func handleEventRejected(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let category = userInfo["category"] as? String else {
            return
        }

        if category == "learning" {
            learningRejectedCount += 1
        } else if category == "reward" {
            rewardRejectedCount += 1
        }
    }

    func hasData(for category: AppUsage.AppCategory) -> Bool {
        if category == .learning {
            return !learningHourlyUsage.isEmpty
        } else {
            return !rewardHourlyUsage.isEmpty
        }
    }

    func getHourlyData(for category: AppUsage.AppCategory) -> [HourlyDataPoint] {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        let usage = category == .learning ? learningHourlyUsage : rewardHourlyUsage
        let events = category == .learning ? learningEventCount : rewardEventCount

        // Get last 12 hours of data
        let startHour = max(0, currentHour - 11)

        return (startHour...currentHour).map { hour in
            HourlyDataPoint(
                hour: hour,
                minutes: usage[hour] ?? 0,
                eventCount: events[hour] ?? 0
            )
        }
    }

    func getTotalMinutes(for category: AppUsage.AppCategory) -> Int {
        let usage = category == .learning ? learningHourlyUsage : rewardHourlyUsage
        return usage.values.reduce(0, +)
    }

    func getTotalEvents(for category: AppUsage.AppCategory) -> Int {
        let events = category == .learning ? learningEventCount : rewardEventCount
        return events.values.reduce(0, +)
    }

    func getRejectedEvents(for category: AppUsage.AppCategory) -> Int {
        return category == .learning ? learningRejectedCount : rewardRejectedCount
    }

    func clearData() {
        learningHourlyUsage.removeAll()
        rewardHourlyUsage.removeAll()
        learningEventCount.removeAll()
        rewardEventCount.removeAll()
        learningRejectedCount = 0
        rewardRejectedCount = 0
    }
}
