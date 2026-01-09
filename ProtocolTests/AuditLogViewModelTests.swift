//
//  AuditLogViewModelTests.swift
//  ProtocolTests
//
//  Tests for AuditLogViewModel logic.
//

import XCTest
@testable import Protocol

@MainActor
final class AuditLogViewModelTests: XCTestCase {
    
    var viewModel: AuditLogViewModel!
        
    override func setUp() async throws {
        viewModel = AuditLogViewModel(auditLogger: AuditLogger.shared)
        // Ensure clean state
        await AuditLogger.shared.clearAll()
    }
    
    override func tearDown() async throws {
        await AuditLogger.shared.clearAll()
    }
    
    func testFilteringByOperation() async {
        // Given
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "1", entityName: "Create Op")
        await AuditLogger.shared.logDelete(entityType: .moleculeTemplate, entityId: "2", entityName: "Delete Op")
        
        await viewModel.loadEntries()
        XCTAssertEqual(viewModel.entries.count, 2)
        
        // When
        viewModel.operationFilter = .create
        
        // Then
        XCTAssertEqual(viewModel.filteredEntries.count, 1)
        XCTAssertEqual(viewModel.filteredEntries.first?.operation, .create)
        
        // When
        viewModel.operationFilter = .delete
        
        // Then
        XCTAssertEqual(viewModel.filteredEntries.count, 1)
        XCTAssertEqual(viewModel.filteredEntries.first?.operation, .delete)
    }
    
    func testFilteringByEntity() async {
        // Given
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "1", entityName: "Molecule")
        await AuditLogger.shared.logCreate(entityType: .atomTemplate, entityId: "2", entityName: "Atom")
        
        await viewModel.loadEntries()
        
        // When
        viewModel.entityFilter = .moleculeTemplate
        
        // Then
        XCTAssertEqual(viewModel.filteredEntries.count, 1)
        XCTAssertEqual(viewModel.filteredEntries.first?.entityType, .moleculeTemplate)
    }
    
    func testDateRangeFiltering() async {
        // Given
        // Since we can't easily inject past dates into AuditLogger (it uses Date()), 
        // we can testing that strict ranges exclude "now" if we set range to past.
        
        await AuditLogger.shared.logCreate(entityType: .moleculeTemplate, entityId: "1")
        await viewModel.loadEntries()
        
        // When setting range to last year
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        
        viewModel.startDate = lastYear
        viewModel.endDate = lastMonth
        
        // Then
        XCTAssertTrue(viewModel.filteredEntries.isEmpty)
        
        // When setting range to include today
        viewModel.endDate = Date()
        
        // Then
        XCTAssertFalse(viewModel.filteredEntries.isEmpty)
    }
    
    func testResetFilters() {
        // Given
        viewModel.operationFilter = .create
        viewModel.entityFilter = .moleculeTemplate
        viewModel.showFilters = true
        
        // When
        viewModel.resetFilters()
        
        // Then
        XCTAssertNil(viewModel.operationFilter)
        XCTAssertNil(viewModel.entityFilter)
        // Date resets are harder to exact match but check not-nil
        XCTAssertNotNil(viewModel.startDate)
    }
}
