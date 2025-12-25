import SwiftUI

struct StreakDetailView: View {
    let appStreaks: [(appName: String, currentStreak: Int, isAtRisk: Bool)]
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(appStreaks, id: \.appName) { streak in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(streak.appName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            if streak.isAtRisk {
                                Text("At Risk")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(AppTheme.sunnyYellow)
                            Text("\(streak.currentStreak)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("All Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
