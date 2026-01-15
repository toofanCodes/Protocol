//
//  DeviceIdentityTests.swift
//  ProtocolTests
//
//  Created on 2026-01-12.
//

import XCTest
@testable import Protocol

/// Tests for DeviceIdentity singleton and its Keychain-based persistence.
/// Note: Some tests verify behavior that depends on the test environment (simulator).
@MainActor
final class DeviceIdentityTests: XCTestCase {
    
    // MARK: - Device ID Tests
    
    func testDeviceID_IsNotEmpty() {
        let identity = DeviceIdentity.shared
        XCTAssertFalse(identity.deviceID.isEmpty, "Device ID should never be empty")
    }
    
    func testDeviceID_IsValidUUID() {
        let identity = DeviceIdentity.shared
        let uuid = UUID(uuidString: identity.deviceID)
        XCTAssertNotNil(uuid, "Device ID should be a valid UUID string")
    }
    
    func testDeviceID_IsPersistent() {
        // Access singleton twice - should return same ID
        let id1 = DeviceIdentity.shared.deviceID
        let id2 = DeviceIdentity.shared.deviceID
        XCTAssertEqual(id1, id2, "Device ID should be consistent across accesses")
    }
    
    // MARK: - Device Name Tests
    
    func testDeviceName_IsNotEmpty() {
        let identity = DeviceIdentity.shared
        XCTAssertFalse(identity.deviceName.isEmpty, "Device name should never be empty")
    }
    
    // MARK: - Simulator Detection Tests
    
    func testIsSimulator_ReturnsExpectedValue() {
        let identity = DeviceIdentity.shared
        
        #if targetEnvironment(simulator)
        XCTAssertTrue(identity.isSimulator, "isSimulator should be true when running on simulator")
        XCTAssertEqual(identity.deviceType, .simulator, "deviceType should be .simulator")
        #else
        XCTAssertFalse(identity.isSimulator, "isSimulator should be false on real device")
        XCTAssertNotEqual(identity.deviceType, .simulator, "deviceType should not be .simulator on real device")
        #endif
    }
    
    func testDeviceType_IsValid() {
        let identity = DeviceIdentity.shared
        let validTypes: [DeviceIdentity.DeviceType] = [.iPhone, .iPad, .simulator, .unknown]
        XCTAssertTrue(validTypes.contains(identity.deviceType), "Device type should be a valid enum case")
    }
    
    // MARK: - toDict Tests
    
    func testToDict_ContainsAllRequiredFields() {
        let identity = DeviceIdentity.shared
        let dict = identity.toDict()
        
        XCTAssertNotNil(dict["deviceID"] as? String, "toDict should contain deviceID")
        XCTAssertNotNil(dict["deviceName"] as? String, "toDict should contain deviceName")
        XCTAssertNotNil(dict["deviceType"] as? String, "toDict should contain deviceType")
        XCTAssertNotNil(dict["isSimulator"] as? Bool, "toDict should contain isSimulator")
    }
    
    func testToDict_ValuesMatchProperties() {
        let identity = DeviceIdentity.shared
        let dict = identity.toDict()
        
        XCTAssertEqual(dict["deviceID"] as? String, identity.deviceID)
        XCTAssertEqual(dict["deviceName"] as? String, identity.deviceName)
        XCTAssertEqual(dict["deviceType"] as? String, identity.deviceType.rawValue)
        XCTAssertEqual(dict["isSimulator"] as? Bool, identity.isSimulator)
    }
    
    // MARK: - Short Description Tests
    
    func testShortDescription_IsNotEmpty() {
        let identity = DeviceIdentity.shared
        XCTAssertFalse(identity.shortDescription.isEmpty, "Short description should never be empty")
    }
    
    func testShortDescription_SimulatorFormat() {
        let identity = DeviceIdentity.shared
        
        #if targetEnvironment(simulator)
        XCTAssertEqual(identity.shortDescription, "Simulator", "Simulator should return 'Simulator' as short description")
        #else
        XCTAssertTrue(identity.shortDescription.contains(identity.deviceType.rawValue),
                     "Short description should contain device type on real device")
        #endif
    }
}
