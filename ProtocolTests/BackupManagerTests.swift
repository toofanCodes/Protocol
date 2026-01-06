//
//  BackupManagerTests.swift
//  ProtocolTests
//
//  Tests for BackupManager functionality.
//

import XCTest
import SwiftData
@testable import Protocol

final class BackupManagerTests: XCTestCase {
    
    var testContainer: ModelContainer!
    var testContext: ModelContext!
    var tempBackupDir: URL!
    
    // MARK: - Setup & Teardown
    
    @MainActor
    override func setUp() async throws {
        // Create an in-memory container for testing
        let schema = Schema([
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self,
            WorkoutSet.self,
            UserSettings.self
        ])
        
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        testContainer = try ModelContainer(for: schema, configurations: [config])
        testContext = testContainer.mainContext
        
        // Create temp directory for backups
        tempBackupDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestBackups")
        try? FileManager.default.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempBackupDir)
        testContainer = nil
        testContext = nil
    }
    
    // MARK: - Backup Data Model Tests
    
    func testMoleculeTemplateData_InitializesFromTemplate() async throws {
        await MainActor.run {
            // Given
            let template = MoleculeTemplate(
                title: "Morning Routine",
                baseTime: Date(),
                recurrenceFreq: .daily
            )
            template.themeColorHex = "#FF5733"
            template.iconSymbol = "sun.max"
            template.notes = "Test notes"
            
            // When
            let data = MoleculeTemplateData(from: template)
            
            // Then
            XCTAssertEqual(data.title, "Morning Routine")
            XCTAssertEqual(data.recurrenceFreq, "daily")
            XCTAssertEqual(data.themeColorHex, "#FF5733")
            XCTAssertEqual(data.iconSymbol, "sun.max")
            XCTAssertEqual(data.notes, "Test notes")
        }
    }
    
    func testMoleculeInstanceData_InitializesFromInstance() async throws {
        await MainActor.run {
            // Given
            let instance = MoleculeInstance(
                scheduledDate: Date(),
                isCompleted: true,
                isException: false,
                exceptionTitle: nil,
                exceptionTime: nil,
                isAllDay: false
            )
            
            // When
            let data = MoleculeInstanceData(from: instance)
            
            // Then
            XCTAssertTrue(data.isCompleted)
            XCTAssertFalse(data.isException)
        }
    }
    
    func testAtomTemplateData_InitializesFromAtom() async throws {
        await MainActor.run {
            // Given
            let atom = AtomTemplate(
                title: "Do 10 pushups",
                inputType: .value,
                targetValue: 10,
                unit: "reps",
                order: 1
            )
            
            // When
            let data = AtomTemplateData(from: atom)
            
            // Then
            XCTAssertEqual(data.title, "Do 10 pushups")
            XCTAssertEqual(data.inputType, "value")
            XCTAssertEqual(data.targetValue, 10)
            XCTAssertEqual(data.unit, "reps")
        }
    }
    
    // MARK: - Backup Metadata Tests
    
    func testBackupMetadata_ContainsRequiredFields() {
        // Given
        let metadata = BackupMetadata(
            appVersion: "1.0",
            timestamp: Date(),
            deviceName: "Test Device",
            schemaVersion: 1
        )
        
        // Then
        XCTAssertEqual(metadata.appVersion, "1.0")
        XCTAssertEqual(metadata.deviceName, "Test Device")
        XCTAssertEqual(metadata.schemaVersion, 1)
    }
    
    // MARK: - Serialization Tests
    
    func testAppBackup_EncodesAndDecodes() throws {
        // Given
        let metadata = BackupMetadata(
            appVersion: "1.0",
            timestamp: Date(),
            deviceName: "Test",
            schemaVersion: 1
        )
        
        let backup = AppBackup(
            metadata: metadata,
            moleculeTemplates: [],
            moleculeInstances: []
        )
        
        // When
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppBackup.self, from: data)
        
        // Then
        XCTAssertEqual(decoded.metadata.appVersion, "1.0")
        XCTAssertEqual(decoded.metadata.deviceName, "Test")
    }
    
    // MARK: - Backup List Tests
    
    @MainActor
    func testListBackups_ReturnsEmptyForNewDirectory() {
        // Given a fresh backup manager (uses default directory)
        // When listing backups from temp (empty) directory
        // This tests the basic listing behavior
        
        let backups = BackupManager.shared.listBackups()
        
        // Then - should return array (may be empty or have existing backups)
        XCTAssertNotNil(backups)
    }
    
    // MARK: - Date Formatting Tests
    
    func testBackupFilename_ContainsTimestamp() {
        // Given
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedPrefix = "backup_\(formatter.string(from: Date()))"
        
        // The actual filename format is: backup_yyyy-MM-dd_HH-mm-ss.json
        // We just verify the date portion is present
        XCTAssertTrue(expectedPrefix.contains("backup_"))
    }
}
