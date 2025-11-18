import SwiftUI
import DeviceActivity

/// Invisible view that triggers the DeviceActivityReport extension when a refresh is requested.
struct HiddenUsageReportView: View {
    private let reportContext = DeviceActivityReport.Context("total-usage-sync")
    @State private var refreshTrigger = false
    @State private var filterEndTime = Date()

    init() {
        NSLog("[HiddenUsageReportView] 🏗️ Initializing HiddenUsageReportView")
        print("[HiddenUsageReportView] 🏗️ Initializing HiddenUsageReportView")
    }

    var body: some View {
        DeviceActivityReport(
            reportContext,
            filter: createFilter(endTime: filterEndTime)
        )
        .id(refreshTrigger)
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            NSLog("[HiddenUsageReportView] 👁️ View appeared")
            print("[HiddenUsageReportView] 👁️ View appeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenTimeService.reportRefreshRequestedNotification)) { _ in
            NSLog("[HiddenUsageReportView] 📡 Received reportRefreshRequested notification")
            print("[HiddenUsageReportView] 📡 Received reportRefreshRequested notification")

            // Update filter end time to force extension refresh
            filterEndTime = Date()
            refreshTrigger.toggle()

            NSLog("[HiddenUsageReportView] 🔄 Updated filter to end at: \(filterEndTime)")
            print("[HiddenUsageReportView] 🔄 Updated filter to end at: \(filterEndTime)")
        }
        .onChange(of: refreshTrigger) { newValue in
            NSLog("[HiddenUsageReportView] 🔄 Refresh trigger changed to: \(newValue)")
            print("[HiddenUsageReportView] 🔄 Refresh trigger changed to: \(newValue)")
        }
    }

    private func createFilter(endTime: Date) -> DeviceActivityFilter {
        let midnight = Calendar.current.startOfDay(for: endTime)

        NSLog("[HiddenUsageReportView] 🔍 Creating filter: \(midnight) to \(endTime)")

        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: midnight, end: endTime)),
            users: .all,
            devices: .all
        )
    }
}
