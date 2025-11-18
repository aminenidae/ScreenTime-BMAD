import SwiftUI

/// Minimal view to satisfy DeviceActivityReport requirements; primary purpose is data bridging
struct TotalActivityView: View {
    let report: ActivityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Report")
                .font(.headline)

            ForEach(Array(report.appUsageMap.keys.sorted()), id: \.self) { bundleID in
                if let duration = report.appUsageMap[bundleID] {
                    HStack {
                        Text(bundleID)
                            .font(.caption)
                        Spacer()
                        Text("\(Int(duration / 60))m")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding()
    }
}
