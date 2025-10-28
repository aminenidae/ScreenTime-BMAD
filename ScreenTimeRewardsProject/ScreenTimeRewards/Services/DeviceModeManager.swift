//
//  DeviceModeManager.swift
//  ScreenTimeRewards
//

import Foundation
import Combine

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
    
    private init() {
        // Load or generate device ID first
        if let existingID = userDefaults.string(forKey: deviceIDKey) {
            self.deviceID = existingID
        } else {
            let newID = UUID().uuidString
            userDefaults.set(newID, forKey: deviceIDKey)
            self.deviceID = newID
        }
        
        // Load or generate device name
        if let existingName = userDefaults.string(forKey: deviceNameKey) {
            self.deviceName = existingName
        } else {
            self.deviceName = "Device"  // Default name if we can't get device name
            userDefaults.set(deviceName, forKey: deviceNameKey)
        }
        
        // Load persisted mode last
        if let modeRaw = userDefaults.string(forKey: deviceModeKey),
           let mode = DeviceMode(rawValue: modeRaw) {
            self.currentMode = mode
        }
    }
    
    func setDeviceMode(_ mode: DeviceMode, deviceName: String? = nil) {
        self.currentMode = mode
        userDefaults.set(mode.rawValue, forKey: deviceModeKey)
        
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
    
    var isParentDevice: Bool {
        currentMode == .parentDevice
    }
    
    var isChildDevice: Bool {
        currentMode == .childDevice
    }
    
    var needsDeviceSelection: Bool {
        currentMode == nil
    }
}