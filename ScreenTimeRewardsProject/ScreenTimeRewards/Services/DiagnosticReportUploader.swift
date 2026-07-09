//
//  DiagnosticReportUploader.swift
//  ScreenTimeRewards
//
//  Silent upload of extension diagnostic logs to Firebase via callable Cloud
//  Function (`submitDiagnosticReport`). One-tap UX for parents/users:
//
//      let refId = try await DiagnosticReportUploader.shared.upload()
//      // → returns "RPT-A4B92C", user can quote it in support email
//
//  No share-sheet, no Files-app, no email composer — log content never leaves
//  the app's process via a user-visible surface. The function-side handler
//  writes to Firestore `diagnosticReports/{id}` which is gated by deny-all
//  client-read rules; only admin SDK can read.
//

import Foundation
import UIKit
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
final class DiagnosticReportUploader {

    static let shared = DiagnosticReportUploader()
    private init() {}

    private let appGroupID = "group.com.screentimerewards.shared"

    /// Upload all retained extension log files + device context to the
    /// diagnosticReports Firestore collection via callable function.
    /// Returns the user-quotable reference ID (e.g. "RPT-A4B92C").
    func upload(notes: String? = nil) async throws -> String {
        #if canImport(FirebaseFunctions)
        let logFiles = collectLogFiles()
        guard !logFiles.isEmpty else {
            throw UploadError.noLogs
        }

        let deviceInfo = collectDeviceInfo()

        var payload: [String: Any] = [
            "logFiles": logFiles.map { ["name": $0.name, "content": $0.contentBase64] },
            "deviceInfo": deviceInfo
        ]
        if let notes, !notes.isEmpty {
            payload["notes"] = notes
        }

        let functions = Functions.functions()
        let result = try await functions.httpsCallable("submitDiagnosticReport").call(payload)

        guard let response = result.data as? [String: Any],
              let reportId = response["reportId"] as? String else {
            throw UploadError.invalidResponse
        }
        return reportId
        #else
        throw UploadError.firebaseUnavailable
        #endif
    }

    // MARK: - Private helpers

    private struct LogFile {
        let name: String
        let contentBase64: String
    }

    /// Read all rotating log files from the App Group `Logs/` directory and
    /// base64-encode the content for transport.
    private func collectLogFiles() -> [LogFile] {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return []
        }
        let logsURL = container.appendingPathComponent("Logs", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Newest first, log files only.
        let sorted = urls
            .filter { $0.lastPathComponent.hasPrefix("ext-log-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        return sorted.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return LogFile(
                name: url.lastPathComponent,
                contentBase64: data.base64EncodedString()
            )
        }
    }

    private func collectDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        let info = Bundle.main.infoDictionary

        let deviceId = UserDefaults(suiteName: appGroupID)?
            .string(forKey: "device_id") ?? UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

        // Battery snapshot is persisted by AppDelegate to App Group on every
        // scenePhase .active and on every UIDevice.batteryStateDidChangeNotification.
        let appGroupDefaults = UserDefaults(suiteName: appGroupID)
        let batState = appGroupDefaults?.integer(forKey: "last_known_battery_state") ?? 0
        let batLevel = appGroupDefaults?.double(forKey: "last_known_battery_level") ?? -1
        let batStateString: String = {
            switch batState {
            case 1: return "unplugged"
            case 2: return "charging"
            case 3: return "full"
            default: return "unknown"
            }
        }()

        var dict: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": device.name,
            "deviceModel": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "batteryState": batStateString,
            "batteryLevel": batLevel
        ]
        if let info {
            if let v = info["CFBundleShortVersionString"] as? String { dict["appVersion"] = v }
            if let b = info["CFBundleVersion"] as? String { dict["buildNumber"] = b }
            if let bid = info["CFBundleIdentifier"] as? String { dict["bundleIdentifier"] = bid }
        }
        return dict
    }

    enum UploadError: LocalizedError {
        case noLogs
        case invalidResponse
        case firebaseUnavailable

        var errorDescription: String? {
            switch self {
            case .noLogs: return String(localized: "No diagnostic logs to upload yet.")
            case .invalidResponse: return String(localized: "Upload completed but server returned an unexpected response.")
            case .firebaseUnavailable: return String(localized: "Firebase isn't available in this build.")
            }
        }
    }
}
