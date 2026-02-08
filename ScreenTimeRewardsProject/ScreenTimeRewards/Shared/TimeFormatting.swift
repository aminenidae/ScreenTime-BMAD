import Foundation

/// Unified time formatting utility for consistent display across the app
/// All views should use these formatters for time display
enum TimeFormatting {

    /// Format seconds as human-readable time
    /// - Returns: "Xh Ym", "Xm", "<1 minute", or "0 minutes" depending on value
    /// - Examples:
    ///   - 0 → "0 minutes"
    ///   - 30 → "<1 minute"
    ///   - 60 → "1 minute"
    ///   - 90 → "1 minute"
    ///   - 120 → "2 minutes"
    ///   - 3600 → "1 hour"
    ///   - 3660 → "1h 1m"
    ///   - 5400 → "1h 30m"
    static func formatSeconds(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)

        if totalSeconds == 0 {
            return "0 minutes"
        }

        if totalSeconds < 60 {
            return "<1 minute"
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours) \(hours == 1 ? "hour" : "hours")"
            }
        } else {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
    }

    /// Format seconds as compact time (no text, just numbers and units)
    /// - Returns: "Xh Ym", "Xm", "<1m", or "0m" depending on value
    /// - Examples:
    ///   - 0 → "0m"
    ///   - 30 → "<1m"
    ///   - 60 → "1m"
    ///   - 90 → "1m"
    ///   - 120 → "2m"
    ///   - 3600 → "1h"
    ///   - 3660 → "1h 1m"
    ///   - 5400 → "1h 30m"
    static func formatSecondsCompact(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)

        if totalSeconds == 0 {
            return "0m"
        }

        if totalSeconds < 60 {
            return "<1m"
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }

    /// Format seconds as HH:MM:SS (for technical displays)
    /// - Returns: "HH:MM:SS" format
    /// - Examples:
    ///   - 0 → "00:00:00"
    ///   - 30 → "00:00:30"
    ///   - 90 → "00:01:30"
    ///   - 3665 → "01:01:05"
    static func formatSecondsAsTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Format Int32 seconds (for CloudKit records)
    /// Uses compact format
    static func formatSeconds(_ seconds: Int32) -> String {
        return formatSecondsCompact(TimeInterval(seconds))
    }

    /// Format Int seconds
    /// Uses compact format
    static func formatSeconds(_ seconds: Int) -> String {
        return formatSecondsCompact(TimeInterval(seconds))
    }
}
