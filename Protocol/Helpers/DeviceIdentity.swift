//
//  DeviceIdentity.swift
//  Protocol
//
//  Created on 2026-01-09.
//

import Foundation
import UIKit
import Security

/// Provides stable device identification for sync conflict detection.
/// Uses identifierForVendor with Keychain fallback for persistence across reinstalls.
@MainActor
final class DeviceIdentity: ObservableObject {
    static let shared = DeviceIdentity()
    
    // MARK: - Types
    
    enum DeviceType: String, Codable {
        case iPhone = "iPhone"
        case iPad = "iPad"
        case simulator = "Simulator"
        case unknown = "Unknown"
    }
    
    // MARK: - Published Properties
    
    /// Unique identifier for this device (persists across app reinstalls)
    let deviceID: String
    
    /// Human-readable device name (e.g., "John's iPhone 15 Pro")
    let deviceName: String
    
    /// Type of device
    let deviceType: DeviceType
    
    /// Whether this is a simulator
    let isSimulator: Bool
    
    // MARK: - Private Constants
    
    private let keychainService = "com.protocol.device"
    private let keychainAccount = "deviceID"
    
    // MARK: - Initialization
    
    private init() {
        // Detect simulator
        #if targetEnvironment(simulator)
        self.isSimulator = true
        self.deviceType = .simulator
        #else
        self.isSimulator = false
        
        // Detect device type
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            self.deviceType = .iPhone
        case .pad:
            self.deviceType = .iPad
        default:
            self.deviceType = .unknown
        }
        #endif
        
        // Get device name
        self.deviceName = UIDevice.current.name
        
        // Get or create stable device ID
        self.deviceID = DeviceIdentity.getOrCreateDeviceID(
            service: keychainService,
            account: keychainAccount
        )
    }
    
    // MARK: - Static Helpers
    
    /// Gets existing device ID from Keychain or creates a new one
    private static func getOrCreateDeviceID(service: String, account: String) -> String {
        // Try to get from Keychain first
        if let existingID = getFromKeychain(service: service, account: account) {
            return existingID
        }
        
        // Try identifierForVendor
        let newID: String
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            newID = vendorID
        } else {
            // Fallback: Generate new UUID
            newID = UUID().uuidString
        }
        
        // Store in Keychain for persistence
        saveToKeychain(id: newID, service: service, account: account)
        
        return newID
    }
    
    /// Retrieves device ID from Keychain
    private static func getFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return id
    }
    
    /// Saves device ID to Keychain
    private static func saveToKeychain(id: String, service: String, account: String) {
        guard let data = id.data(using: .utf8) else { return }
        
        // Delete existing if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    // MARK: - Public API
    
    /// Returns a dictionary representation for sync metadata
    func toDict() -> [String: Any] {
        return [
            "deviceID": deviceID,
            "deviceName": deviceName,
            "deviceType": deviceType.rawValue,
            "isSimulator": isSimulator
        ]
    }
    
    /// Returns a short display string for the device
    var shortDescription: String {
        if isSimulator {
            return "Simulator"
        }
        return "\(deviceName) (\(deviceType.rawValue))"
    }
}

// MARK: - Device Registry Model

/// Represents the device registry stored on Google Drive
struct DeviceRegistry: Codable {
    var registeredDevices: [RegisteredDevice]
    var lastModifiedBy: String
    var lastModifiedAt: Date
    
    struct RegisteredDevice: Codable, Identifiable {
        var id: String { deviceID }
        let deviceID: String
        let deviceName: String
        let deviceType: String
        let isSimulator: Bool
        var firstSyncDate: Date
        var lastSyncDate: Date
        var isPrimary: Bool
    }
    
    init() {
        self.registeredDevices = []
        self.lastModifiedBy = ""
        self.lastModifiedAt = Date()
    }
    
    /// Checks if a device is already registered
    func isDeviceRegistered(deviceID: String) -> Bool {
        registeredDevices.contains { $0.deviceID == deviceID }
    }
    
    /// Gets the last device that synced (excluding current device)
    func lastOtherDevice(excluding currentDeviceID: String) -> RegisteredDevice? {
        registeredDevices
            .filter { $0.deviceID != currentDeviceID && !$0.isSimulator }
            .sorted { $0.lastSyncDate > $1.lastSyncDate }
            .first
    }
    
    /// Registers or updates a device
    mutating func registerDevice(identity: DeviceIdentity) {
        let now = Date()
        
        if let index = registeredDevices.firstIndex(where: { $0.deviceID == identity.deviceID }) {
            // Update existing
            registeredDevices[index].lastSyncDate = now
        } else {
            // Add new
            let newDevice = RegisteredDevice(
                deviceID: identity.deviceID,
                deviceName: identity.deviceName,
                deviceType: identity.deviceType.rawValue,
                isSimulator: identity.isSimulator,
                firstSyncDate: now,
                lastSyncDate: now,
                isPrimary: registeredDevices.isEmpty // First device is primary
            )
            registeredDevices.append(newDevice)
        }
        
        lastModifiedBy = identity.deviceID
        lastModifiedAt = now
    }
}
