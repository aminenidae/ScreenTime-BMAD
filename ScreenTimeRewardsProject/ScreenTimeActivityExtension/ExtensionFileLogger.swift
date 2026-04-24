import Foundation

/// Rotating-file logger for the DeviceActivityMonitor extension.
///
/// Writes one file per day under the App Group container at:
///   `Logs/ext-log-YYYY-MM-DD.log`
///
/// Append-only via `FileHandle` (no in-memory buffer, no read-then-rewrite),
/// so the writer respects the extension's 6 MB hard memory ceiling. Each line
/// is written via a single `write(Data)` call which is atomic for small payloads.
///
/// Retention: once per day, on first write of a new day, files older than
/// `retentionDays` are deleted. Default = 7.
///
/// **No size cap per day** — by user decision, capture all log lines so that
/// future incidents can be debugged from the full record rather than fragments
/// trimmed by the legacy size-based UserDefaults logger. Daily file size is
/// expected to land in the 3–8 MB range for a heavy 10-app day; a full week
/// stays comfortably under 60 MB.
///
/// Failure mode: any I/O error is swallowed (logging must never break the
/// recording path). The legacy `UserDefaults`-backed `debugLog` continues to
/// receive every line unchanged, so this writer is purely additive.
///
/// NOTE: This file is on disk but must be added to the
/// ScreenTimeActivityExtension target (and optionally to the
/// ScreenTimeRewards target) in Xcode before it will compile.
final class ExtensionFileLogger {
    static let shared = ExtensionFileLogger()

    /// App Group identifier — must match the extension's `appGroupIdentifier`
    /// constant in `DeviceActivityMonitorExtension.swift`.
    static let appGroupID = "group.com.screentimerewards.shared"

    /// Number of daily log files to retain. Older files are deleted on the
    /// first write of each new day.
    private let retentionDays = 7

    /// Subdirectory under the App Group container.
    private let subdir = "Logs"

    /// File-name prefix. Combined with `YYYY-MM-DD.log`.
    private let prefix = "ext-log-"

    /// Cached date string ("YYYY-MM-DD") of the last write. When this changes,
    /// the writer triggers retention pruning.
    private var lastWrittenDate: String = ""

    /// Serialize writes from concurrent contexts in the rare case the extension
    /// is invoked re-entrantly. POSIX `O_APPEND` makes single small writes
    /// atomic across processes; this lock just protects our cached state.
    private let lock = NSLock()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {}

    /// Append a single line to today's log file. The caller is expected to
    /// already have formatted the line (timestamp, session ID, etc.); a
    /// trailing newline is added if not present.
    ///
    /// Safe to call from any thread. Never throws — I/O failures are silent.
    func appendLine(_ line: String) {
        guard let baseURL = Self.containerLogsURL() else { return }
        let today = Self.dateFormatter.string(from: Date())

        lock.lock()
        let needsPrune = (today != lastWrittenDate)
        lastWrittenDate = today
        lock.unlock()

        // Ensure the directory exists. Cheap to call repeatedly; FileManager
        // returns success if the directory already exists with `withIntermediateDirectories: true`.
        try? FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileURL = baseURL.appendingPathComponent("\(prefix)\(today).log")

        // Ensure the file exists so FileHandle(forWritingTo:) doesn't fail.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        let payload = line.hasSuffix("\n") ? line : line + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Swallow: logging must never break the recording path. The
            // legacy UserDefaults-backed log still has the line.
        }

        if needsPrune {
            pruneOldFiles(in: baseURL, today: today)
        }
    }

    /// URL of today's log file (may not exist yet). Useful for the
    /// Diagnostics export UI in the parent Settings tab.
    func currentLogFileURL() -> URL? {
        guard let baseURL = Self.containerLogsURL() else { return nil }
        let today = Self.dateFormatter.string(from: Date())
        return baseURL.appendingPathComponent("\(prefix)\(today).log")
    }

    /// All retained log file URLs, newest first. Returns `[]` if the
    /// container is unavailable or the directory doesn't exist yet.
    func allLogFileURLs() -> [URL] {
        guard let baseURL = Self.containerLogsURL() else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // newest first by date in name
    }

    /// Delete all rotating log files. Used by the Diagnostics "Clear logs"
    /// button. Failures are silent.
    func deleteAllLogFiles() {
        for url in allLogFileURLs() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private

    /// Container `Logs/` directory under the App Group. Creates nothing
    /// (caller does that on first write).
    private static func containerLogsURL() -> URL? {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return container.appendingPathComponent("Logs", isDirectory: true)
    }

    /// Delete log files older than `retentionDays` days, identified by the
    /// date in the file name. Called once per day on the first write of a
    /// new day. Files with malformed names are ignored (left in place).
    private func pruneOldFiles(in baseURL: URL, today: String) {
        guard let cutoff = Self.dateFormatter.date(from: today)?
            .addingTimeInterval(-Double(retentionDays) * 86_400) else { return }
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".log") else { continue }
            let datePart = String(name.dropFirst(prefix.count).dropLast(".log".count))
            guard let fileDate = Self.dateFormatter.date(from: datePart) else { continue }
            if fileDate < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
