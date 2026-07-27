//
//  RecountMinutesLink.swift
//  ScreenTimeRewards
//
//  Child-facing entry point to the usage recount — the same rebuild a parent runs
//  from Settings → "Recalculate Usage". Older devices occasionally miss Screen Time
//  events, and the kid is the one looking at the wrong number; this lets them
//  trigger the correction without waiting for a parent.
//
//  Deliberately quiet. A recount zeroes today's totals while iOS replays them, so
//  goals read as unmet and reward apps re-lock for a few minutes. It must never
//  look like a "get more time" button.
//

import SwiftUI

struct RecountMinutesLink: View {
    /// Called with a status message when a recount starts and with nil when it
    /// should be dismissed. The dashboard renders it as a top banner so the
    /// explanation stays visible after the kid scrolls away from this link.
    var onStatusChange: (String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showConfirm = false
    @State private var lastRecountAt: Date?
    @State private var now = Date()

    /// A recount runs for minutes (iOS replays usage in waves), so the lock has to
    /// survive the app being closed — an in-memory lock would let a re-press restart
    /// a half-finished rebuild from zero. Written by `healUsageData`, so a recount
    /// the parent started also holds this button.
    private static let cooldown: TimeInterval = 30 * 60
    private static let recountingPhase: TimeInterval = 3 * 60
    private static let appGroupID = "group.com.screentimerewards.shared"
    private static let lastRecountKey = "last_manual_heal_at"

    private var elapsed: TimeInterval? {
        lastRecountAt.map { now.timeIntervalSince($0) }
    }

    private var isCoolingDown: Bool {
        guard let elapsed else { return false }
        return elapsed >= 0 && elapsed < Self.cooldown
    }

    private var isRecounting: Bool {
        guard let elapsed else { return false }
        return elapsed >= 0 && elapsed < Self.recountingPhase
    }

    var body: some View {
        Button(action: { showConfirm = true }) {
            HStack(spacing: 6) {
                if isRecounting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(AppTheme.textSecondary(for: colorScheme))
                } else {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            // accentText, not vibrantTeal: the link sits on the plain background
            // rather than a card, and raw teal on the dark navy fails contrast.
            .foregroundColor(isCoolingDown
                ? AppTheme.textSecondary(for: colorScheme)
                : AppTheme.accentText(for: colorScheme))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isCoolingDown)
        .accessibilityLabel(label)
        .accessibilityHint(isCoolingDown
            ? "Already counting. You can do this again later."
            : "Counts today's minutes again using your iPhone's own record.")
        .onAppear { loadLastRecount() }
        .task(id: lastRecountAt) {
            // Only ticks while the label can still change; stops on its own once
            // the cooldown is over.
            while !Task.isCancelled && isCoolingDown {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                now = Date()
            }
        }
        .alert("Recount my minutes?", isPresented: $showConfirm) {
            Button("Not now", role: .cancel) { }
            Button("Recount") {
                Task { await runRecount() }
            }
        } message: {
            Text("We'll ask your iPhone to count today's minutes again. It takes a few minutes, and your fun apps might lock while we count. You only need to do this once.")
        }
    }

    private var label: String {
        if isRecounting {
            return String(localized: "Counting your minutes…")
        }
        if isCoolingDown {
            return String(localized: "Counted a few minutes ago")
        }
        return String(localized: "Recount my minutes")
    }

    private func loadLastRecount() {
        now = Date()
        guard let stored = UserDefaults(suiteName: Self.appGroupID)?
            .double(forKey: Self.lastRecountKey), stored > 0 else { return }
        lastRecountAt = Date(timeIntervalSince1970: stored)
    }

    private func runRecount() async {
        // Lock immediately on tap. `healUsageData` writes the durable timestamp a
        // moment later; this optimistic value keeps the button from being pressed
        // twice while the restart is in flight.
        lastRecountAt = Date()
        now = Date()

        onStatusChange(String(localized: "Counting your minutes… your fun apps may lock while we check."))

        _ = await ScreenTimeService.shared.healUsageData(reason: "child_dashboard_recount")

        // No "done" moment exists — iOS delivers the corrected usage in waves over
        // several minutes. Show the note long enough to read, then let the live
        // dashboard climb behind it.
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        onStatusChange(nil)
    }
}

/// Top-of-dashboard note shown while a recount is in flight. Matches the existing
/// child banners (full-width strip, not a modal spinner) so the kid can keep using
/// the screen and see the numbers rebuild.
struct RecountStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.vibrantTeal)
    }
}

#Preview("Recount Link") {
    VStack {
        RecountStatusBanner(message: "Counting your minutes… your fun apps may lock while we check.")
        RecountMinutesLink { _ in }
        Spacer()
    }
}
