//
//  DeviceModeManager.swift
//  ScreenTimeRewards
//

import Foundation
import Combine
import Security

@MainActor
class DeviceModeManager: ObservableObject {
    static let shared = DeviceModeManager()

    @Published private(set) var currentMode: DeviceMode?
    @Published private(set) var deviceID: String
    @Published private(set) var deviceName: String

    private let userDefaults = UserDefaults.standard
    private let deviceModeKey = "deviceMode"
    private let deviceIDKey = "deviceID"
    private let deviceNameKey = "deviceName"

    // Keychain constants for persistent deviceID
    private let keychainService = "com.screentimerewards"
    private let keychainDeviceIDKey = "deviceID"

    private init() {
        // PHASE 3: Differentiate deviceID storage by device mode
        // - Child device: Use Keychain (persists across reinstall to prevent orphaned zones)
        // - Parent device: Use UserDefaults only (reinstall = fresh start, must re-pair)

        // First, check if we have a stored mode
        let storedMode: DeviceMode?
        if let modeRaw = userDefaults.string(forKey: deviceModeKey),
           let mode = DeviceMode(rawValue: modeRaw) {
            storedMode = mode
        } else {
            storedMode = nil
        }

        // Load deviceID based on mode
        if storedMode == .childDevice {
            // CHILD: Use Keychain (persists across reinstall)
            if let keychainID = Self.loadFromKeychain(service: "com.screentimerewards", key: "deviceID") {
                self.deviceID = keychainID
                #if DEBUG
                print("[DeviceModeManager] Child device: Loaded deviceID from Keychain: \(keychainID)")
                #endif
            } else if let existingID = userDefaults.string(forKey: deviceIDKey) {
                // Migrate from UserDefaults to Keychain for child
                self.deviceID = existingID
                Self.saveToKeychain(value: existingID, service: "com.screentimerewards", key: "deviceID")
                #if DEBUG
                print("[DeviceModeManager] Child device: Migrated deviceID to Keychain: \(existingID)")
                #endif
            } else {
                // New child device - generate and save to both
                let newID = UUID().uuidString
                Self.saveToKeychain(value: newID, service: "com.screentimerewards", key: "deviceID")
                userDefaults.set(newID, forKey: deviceIDKey)
                self.deviceID = newID
                #if DEBUG
                print("[DeviceModeManager] Child device: Generated new deviceID: \(newID)")
                #endif
            }
        } else {
            // PARENT or NO MODE YET: Use UserDefaults only
            // If there's a stale Keychain entry from before, remove it to ensure fresh start on reinstall
            if storedMode == .parentDevice {
                Self.deleteFromKeychain(service: "com.screentimerewards", key: "deviceID")
                #if DEBUG
                print("[DeviceModeManager] Parent device: Cleared Keychain deviceID for fresh-start behavior")
                #endif
            }

            if let existingID = userDefaults.string(forKey: deviceIDKey) {
                self.deviceID = existingID
                #if DEBUG
                print("[DeviceModeManager] Parent/New device: Loaded deviceID from UserDefaults: \(existingID)")
                #endif
            } else {
                // Generate new ID (UserDefaults only - will be lost on reinstall for parent)
                let newID = UUID().uuidString
                userDefaults.set(newID, forKey: deviceIDKey)
                self.deviceID = newID
                #if DEBUG
                print("[DeviceModeManager] Parent/New device: Generated new deviceID: \(newID)")
                #endif
            }
        }

        // Load or generate device name
        if let existingName = userDefaults.string(forKey: deviceNameKey) {
            self.deviceName = existingName
        } else {
            self.deviceName = "Device"  // Default name if we can't get device name
            userDefaults.set(deviceName, forKey: deviceNameKey)
        }

        // Set the mode
        self.currentMode = storedMode
    }
    
    func setDeviceMode(_ mode: DeviceMode, deviceName: String? = nil) {
        self.currentMode = mode
        userDefaults.set(mode.rawValue, forKey: deviceModeKey)

        // PHASE 3: Manage Keychain based on mode
        if mode == .childDevice {
            // Child: Save deviceID to Keychain (persist across reinstall)
            Self.saveToKeychain(value: deviceID, service: keychainService, key: keychainDeviceIDKey)
            #if DEBUG
            print("[DeviceModeManager] Child mode: Saved deviceID to Keychain for persistence")
            #endif
        } else {
            // Parent: Clear deviceID from Keychain (fresh start on reinstall)
            Self.deleteFromKeychain(service: keychainService, key: keychainDeviceIDKey)
            #if DEBUG
            print("[DeviceModeManager] Parent mode: Cleared Keychain for fresh-start behavior")
            #endif
        }

        if let name = deviceName {
            self.deviceName = name
            userDefaults.set(name, forKey: deviceNameKey)
        }

        #if DEBUG
        print("[DeviceModeManager] Mode set to: \(mode.displayName)")
        print("[DeviceModeManager] Device ID: \(deviceID)")
        print("[DeviceModeManager] Device Name: \(self.deviceName)")
        #endif
    }
    
    func resetDeviceMode() {
        currentMode = nil
        userDefaults.removeObject(forKey: deviceModeKey)

        #if DEBUG
        print("[DeviceModeManager] Mode reset - will show device selection on next launch")
        #endif
    }

    /// Update the device name
    func setDeviceName(_ name: String) {
        self.deviceName = name
        userDefaults.set(name, forKey: deviceNameKey)

        #if DEBUG
        print("[DeviceModeManager] Device name updated to: \(name)")
        #endif
    }
    
    var isParentDevice: Bool {
        currentMode == .parentDevice
    }
    
    var isChildDevice: Bool {
        currentMode == .childDevice
    }
    
    var needsDeviceSelection: Bool {
        currentMode == nil
    }

    // MARK: - Keychain Helpers

    /// Save a string value to Keychain (persists across app reinstalls)
    private static func saveToKeychain(value: String, service: String, key: String) {
        let data = value.data(using: .utf8)!

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)

        #if DEBUG
        if status != errSecSuccess {
            print("[DeviceModeManager] Keychain save failed with status: \(status)")
        }
        #endif
    }

    /// Load a string value from Keychain
    private static func loadFromKeychain(service: String, key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete a value from Keychain
    private static func deleteFromKeychain(service: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}