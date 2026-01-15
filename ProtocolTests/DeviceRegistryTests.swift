//
//  DeviceRegistryTests.swift
//  ProtocolTests
//
//  Created on 2026-01-12.
//

import XCTest
@testable import Protocol

/// Tests for DeviceRegistry model used in multi-device sync conflict detection.
final class DeviceRegistryTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInit_StartsEmpty() {
        let registry = DeviceRegistry()
        
        XCTAssertTrue(registry.registeredDevices.isEmpty, "New registry should have no devices")
        XCTAssertEqual(registry.lastModifiedBy, "", "New registry should have empty lastModifiedBy")
    }
    
    // MARK: - isDeviceRegistered Tests
    
    func testIsDeviceRegistered_WhenEmpty_ReturnsFalse() {
        let registry = DeviceRegistry()
        
        XCTAssertFalse(registry.isDeviceRegistered(deviceID: "test-device-id"),
                      "Empty registry should return false for any device ID")
    }
    
    func testIsDeviceRegistered_WhenDeviceExists_ReturnsTrue() {
        var registry = DeviceRegistry()
        let device = createTestDevice(id: "device-123")
        registry.registeredDevices.append(device)
        
        XCTAssertTrue(registry.isDeviceRegistered(deviceID: "device-123"),
                     "Should return true for registered device")
    }
    
    func testIsDeviceRegistered_WhenDifferentDevice_ReturnsFalse() {
        var registry = DeviceRegistry()
        let device = createTestDevice(id: "device-123")
        registry.registeredDevices.append(device)
        
        XCTAssertFalse(registry.isDeviceRegistered(deviceID: "device-456"),
                      "Should return false for unregistered device")
    }
    
    // MARK: - lastOtherDevice Tests
    
    func testLastOtherDevice_WhenEmpty_ReturnsNil() {
        let registry = DeviceRegistry()
        
        XCTAssertNil(registry.lastOtherDevice(excluding: "current-device"),
                    "Empty registry should return nil")
    }
    
    func testLastOtherDevice_WhenOnlyCurrentDevice_ReturnsNil() {
        var registry = DeviceRegistry()
        registry.registeredDevices.append(createTestDevice(id: "current-device"))
        
        XCTAssertNil(registry.lastOtherDevice(excluding: "current-device"),
                    "Should return nil when only current device is registered")
    }
    
    func testLastOtherDevice_ExcludesSimulators() {
        var registry = DeviceRegistry()
        registry.registeredDevices.append(createTestDevice(id: "simulator-1", isSimulator: true))
        registry.registeredDevices.append(createTestDevice(id: "current-device"))
        
        XCTAssertNil(registry.lastOtherDevice(excluding: "current-device"),
                    "Should exclude simulators from other devices")
    }
    
    func testLastOtherDevice_ReturnsCorrectDevice() {
        var registry = DeviceRegistry()
        
        let olderDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let newerDate = Date()
        
        registry.registeredDevices.append(createTestDevice(id: "device-old", lastSyncDate: olderDate))
        registry.registeredDevices.append(createTestDevice(id: "device-new", lastSyncDate: newerDate))
        registry.registeredDevices.append(createTestDevice(id: "current-device"))
        
        let result = registry.lastOtherDevice(excluding: "current-device")
        
        XCTAssertEqual(result?.deviceID, "device-new",
                      "Should return the most recently synced other device")
    }
    
    // MARK: - registerDevice Tests
    
    @MainActor
    func testRegisterDevice_AddsNewDevice() async {
        var registry = DeviceRegistry()
        let identity = DeviceIdentity.shared
        
        registry.registerDevice(identity: identity)
        
        XCTAssertEqual(registry.registeredDevices.count, 1, "Should add one device")
        XCTAssertEqual(registry.registeredDevices.first?.deviceID, identity.deviceID)
        XCTAssertEqual(registry.lastModifiedBy, identity.deviceID)
    }
    
    @MainActor
    func testRegisterDevice_FirstDeviceIsPrimary() async {
        var registry = DeviceRegistry()
        let identity = DeviceIdentity.shared
        
        registry.registerDevice(identity: identity)
        
        XCTAssertTrue(registry.registeredDevices.first?.isPrimary ?? false,
                     "First registered device should be primary")
    }
    
    @MainActor
    func testRegisterDevice_UpdatesExistingDevice() async {
        var registry = DeviceRegistry()
        let identity = DeviceIdentity.shared
        
        // First registration
        registry.registerDevice(identity: identity)
        let firstSyncDate = registry.registeredDevices.first?.lastSyncDate
        
        // Wait a tiny bit to ensure time difference
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Second registration (update)
        registry.registerDevice(identity: identity)
        let secondSyncDate = registry.registeredDevices.first?.lastSyncDate
        
        XCTAssertEqual(registry.registeredDevices.count, 1, "Should not duplicate device")
        XCTAssertNotEqual(firstSyncDate, secondSyncDate, "lastSyncDate should be updated")
    }
    
    @MainActor
    func testRegisterDevice_UpdatesLastModified() async {
        var registry = DeviceRegistry()
        let identity = DeviceIdentity.shared
        
        let beforeDate = Date()
        registry.registerDevice(identity: identity)
        let afterDate = Date()
        
        XCTAssertGreaterThanOrEqual(registry.lastModifiedAt, beforeDate)
        XCTAssertLessThanOrEqual(registry.lastModifiedAt, afterDate)
        XCTAssertEqual(registry.lastModifiedBy, identity.deviceID)
    }
    
    // MARK: - Codable Tests
    
    func testCodable_RoundTrip() throws {
        var registry = DeviceRegistry()
        registry.registeredDevices.append(createTestDevice(id: "device-1"))
        registry.registeredDevices.append(createTestDevice(id: "device-2", isSimulator: true))
        registry.lastModifiedBy = "device-1"
        registry.lastModifiedAt = Date()
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(registry)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeviceRegistry.self, from: data)
        
        XCTAssertEqual(decoded.registeredDevices.count, 2)
        XCTAssertEqual(decoded.registeredDevices[0].deviceID, "device-1")
        XCTAssertEqual(decoded.registeredDevices[1].isSimulator, true)
        XCTAssertEqual(decoded.lastModifiedBy, "device-1")
    }
    
    // MARK: - Helpers
    
    private func createTestDevice(
        id: String,
        isSimulator: Bool = false,
        lastSyncDate: Date = Date()
    ) -> DeviceRegistry.RegisteredDevice {
        DeviceRegistry.RegisteredDevice(
            deviceID: id,
            deviceName: "Test Device",
            deviceType: isSimulator ? "Simulator" : "iPhone",
            isSimulator: isSimulator,
            firstSyncDate: Date(),
            lastSyncDate: lastSyncDate,
            isPrimary: false
        )
    }
}
