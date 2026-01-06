//
//  AuditLoggerTests.swift
//  ProtocolTests
//
//  Tests for AuditLogger functionality.
//

import XCTest
@testable import Protocol

final class AuditLoggerTests: XCTestCase {
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        // Clear any existing logs for a clean slate
        await AuditLogger.shared.clearAll()
    }
    
    override func tearDown() async throws {
        // Clean up after tests
        await AuditLogger.shared.clearAll()
    }
    
    // MARK: - Entry Creation Tests
    
    func testLogCreate_AddsEntry() async throws {
        // When
        await AuditLogger.shared.logCreate(
            entityType: .moleculeTemplate,
            entityId: "test-123",
            entityName: "Morning Routine"
        )
        
        // Then
        let entries = await AuditLogger.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.operation, .create)
        XCTAssertEqual(entries.first?.entityType, .moleculeTemplate)
        XCTAssertEqual(entries.first?.entityId, "test-123")
        XCTAssertEqual(entries.first?.entityName, "Morning Routine")
    }
    
    func testLogUpdate_CapturesFieldChanges() async throws {
        // Given
        let changes = [
            FieldChange(field: "title", oldValue: "Old Title", newValue: "New Title"),
            FieldChange(field: "notes", oldValue: nil, newValue: "Added notes")
        ]
        
        // When
        await AuditLogger.shared.logUpdate(
            entityType: .moleculeInstance,
            entityId: "instance-456",
            entityName: "Test Instance",
            changes: changes
        )
        
        // Then
        let entries = await AuditLogger.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.operation, .update)
        XCTAssertEqual(entries.first?.changes?.count, 2)
        XCTAssertEqual(entries.first?.changes?.first?.field, "title")
    }
    
    func testLogDelete_AddsEntry() async throws {
        // When
        await AuditLogger.shared.logDelete(
            entityType: .atomTemplate,
            entityId: "atom-789",
            entityName: "Deleted Atom"
        )
        
        // Then
        let entries = await AuditLogger.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.operation, .delete)
        XCTAssertEqual(entries.first?.entityType, .atomTemplate)
    }
    
    func testLogBulkCreate_AddsEntry() async throws {
        // When
        await AuditLogger.shared.logBulkCreate(
            entityType: .moleculeInstance,
            count: 30,
            additionalInfo: "Generated instances"
        )
        
        // Then
        let entries = await AuditLogger.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.operation, .bulkCreate)
        XCTAssertEqual(entries.first?.entityName, "30 items")
    }
    
    func testLogBulkDelete_AddsEntry() async throws {
        // When
        await AuditLogger.shared.logBulkDelete(
            entityType: .atomInstance,
            count: 5,
            additionalInfo: "Cleanup operation"
        )
        
        // Then
        let entries = await AuditLogger.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.operation, .bulkDelete)
        XCTAssertEqual(entries.first?.additionalInfo, "Cleanup operation")
    }
    
    // MARK: - Field Change Helper Tests
    
    func testFieldChange_ReturnsNilForSameValues() {
        // When
        let change = AuditLogger.fieldChange("title", old: "Same", new: "Same")
        
        // Then
        XCTAssertNil(change)
    }
    
    func testFieldChange_ReturnsChangeForDifferentValues() {
        // When
        let change = AuditLogger.fieldChange("title", old: "Old", new: "New")
        
        // Then
        XCTAssertNotNil(change)
        XCTAssertEqual(change?.field, "title")
        XCTAssertEqual(change?.oldValue, "Old")
        XCTAssertEqual(change?.newValue, "New")
    }
    
    // MARK: - Entry Ordering Tests
    
    func testGetEntries_ReturnsMostRecentFirst() async throws {
        // Given
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "1", entityName: "First")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "2", entityName: "Second")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "3", entityName: "Third")
        
        // When
        let entries = await AuditLogger.shared.getEntries()
        
        // Then
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].entityName, "Third")
        XCTAssertEqual(entries[1].entityName, "Second")
        XCTAssertEqual(entries[2].entityName, "First")
    }
    
    // MARK: - Export Tests
    
    func testExportAsJSON_ReturnsValidJSON() async throws {
        // Given
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "export-test", entityName: "Export Test")
        
        // When
        let jsonData = await AuditLogger.shared.exportAsJSON()
        
        // Then
        XCTAssertNotNil(jsonData)
        
        // Verify it's valid JSON
        let decoded = try JSONSerialization.jsonObject(with: jsonData!, options: [])
        XCTAssertTrue(decoded is [[String: Any]])
    }
    
    // MARK: - Summary Tests
    
    func testEntrySummary_CreateOperation() {
        // Given
        let entry = AuditLogEntry(
            operation: .create,
            entityType: .moleculeTemplate,
            entityId: "123",
            entityName: "Test",
            callSite: "Test.swift:1"
        )
        
        // Then
        XCTAssertEqual(entry.summary, "Created MoleculeTemplate: Test")
    }
    
    func testEntrySummary_UpdateOperation() {
        // Given
        let entry = AuditLogEntry(
            operation: .update,
            entityType: .moleculeInstance,
            entityId: "456",
            entityName: "Updated",
            changes: [FieldChange(field: "title", oldValue: "A", newValue: "B")],
            callSite: "Test.swift:2"
        )
        
        // Then
        XCTAssertEqual(entry.summary, "Updated MoleculeInstance: Updated (1 field)")
    }
    
    func testEntrySummary_DeleteOperation() {
        // Given
        let entry = AuditLogEntry(
            operation: .delete,
            entityType: .atomTemplate,
            entityId: "789",
            entityName: "Deleted",
            callSite: "Test.swift:3"
        )
        
        // Then
        XCTAssertEqual(entry.summary, "Deleted AtomTemplate: Deleted")
    }
}
