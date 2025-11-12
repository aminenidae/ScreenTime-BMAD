//
//  PerAppProgressView.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-11.
//

import SwiftUI
import ManagedSettings
import FamilyControls

struct PerAppProgressView: View {
    let challenge: Challenge
    let appProgressRecords: [AppProgress]
    let learningSnapshots: [LearningAppSnapshot]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("App Progress")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            if appProgressRecords.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(appProgressRecords, id: \.appProgressID) { appProgress in
                        if let snapshot = learningSnapshots.first(where: { $0.logicalID == appProgress.appLogicalID }) {
                            appProgressRow(appProgress: appProgress, snapshot: snapshot)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private var emptyState: some View {
        Text("No app-specific progress yet. Start using your learning apps!")
            .font(.system(size: 14))
            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            .padding(.vertical, 8)
    }

    private func appProgressRow(appProgress: AppProgress, snapshot: LearningAppSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // App icon
                if #available(iOS 15.2, *) {
                    Label(snapshot.token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.2)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    // App name
                    if #available(iOS 15.2, *) {
                        Label(snapshot.token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    }

                    Text("\(appProgress.currentMinutes)/\(appProgress.targetMinutes) min")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                if appProgress.isCompleted {
                    ZStack {
                        Circle()
                            .fill(AppTheme.vibrantTeal.opacity(0.2))
                            .frame(width: 32, height: 32)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                } else {
                    Text("\(Int(progressPercentage(appProgress)))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 999)
                        .fill(appProgress.isCompleted ? AppTheme.vibrantTeal : AppTheme.sunnyYellow)
                        .frame(width: geometry.size.width * min(progressPercentage(appProgress) / 100, 1.0), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appProgress.isCompleted ?
                      AppTheme.vibrantTeal.opacity(colorScheme == .dark ? 0.15 : 0.1) :
                      colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            appProgress.isCompleted ? AppTheme.vibrantTeal.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    private func progressPercentage(_ appProgress: AppProgress) -> Double {
        guard appProgress.targetMinutes > 0 else { return 0 }
        return (Double(appProgress.currentMinutes) / Double(appProgress.targetMinutes)) * 100
    }
}
