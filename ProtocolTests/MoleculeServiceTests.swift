//
//  MoleculeServiceTests.swift
//  ProtocolTests
//
//  Unit tests for MoleculeService CRUD operations.
//

import XCTest
import SwiftData
@testable import Protocol

@MainActor
final class MoleculeServiceTests: XCTestCase {
    
    var container: ModelContainer!
    var context: ModelContext!
    var service: MoleculeService!
    
    override func setUpWithError() throws {
        // Create in-memory container for isolated testing
        let schema = Schema([
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self,
            WorkoutSet.self,
            UserSettings.self,
            PersistentAuditLog.self
        ])
        
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        service = MoleculeService(modelContext: context)
    }
    
    override func tearDownWithError() throws {
        service = nil
        context = nil
        container = nil
    }
    
    // MARK: - Helper Methods
    
    private func createTestTemplate(
        title: String = "Test Routine",
        withAtoms: Bool = true
    ) -> MoleculeTemplate {
        let template = MoleculeTemplate(
            title: title,
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1, 2, 3, 4, 5, 6, 7]
        )
        context.insert(template)
        
        if withAtoms {
            let atom1 = AtomTemplate(title: "Task 1", order: 0, parentMoleculeTemplate: template)
            let atom2 = AtomTemplate(title: "Task 2", order: 1, parentMoleculeTemplate: template)
            context.insert(atom1)
            context.insert(atom2)
            template.atomTemplates = [atom1, atom2]
        }
        
        try? context.save()
        return template
    }
    
    private func createTestInstance(for template: MoleculeTemplate? = nil) -> MoleculeInstance {
        let instance = MoleculeInstance(
            scheduledDate: Date(),
            parentTemplate: template
        )
        context.insert(instance)
        
        // Add atom instances
        let atom1 = AtomInstance(title: "Task 1", order: 0, parentMoleculeInstance: instance)
        let atom2 = AtomInstance(title: "Task 2", order: 1, parentMoleculeInstance: instance)
        context.insert(atom1)
        context.insert(atom2)
        instance.atomInstances = [atom1, atom2]
        
        try? context.save()
        return instance
    }
    
    // MARK: - Template Tests
    
    func testCreateTemplate_InsertsIntoContext() throws {
        // Given
        let template = createTestTemplate(title: "Morning Routine")
        
        // Then
        XCTAssertNotNil(template.id)
        XCTAssertEqual(template.title, "Morning Routine")
        XCTAssertEqual(template.atomTemplates.count, 2)
    }
    
    func testCreateTemplate_GeneratesInstances() throws {
        // Given
        let template = createTestTemplate()
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        
        // When
        let instances = template.generateInstances(until: futureDate, in: context)
        
        // Then
        XCTAssertGreaterThan(instances.count, 0, "Should generate at least one instance")
        
        // Each instance should have atom instances
        for instance in instances {
            XCTAssertEqual(instance.atomInstances.count, 2, "Each instance should have 2 atoms")
        }
    }
    
    func testDeleteTemplate_ArchivesTemplate() async throws {
        // Given
        let template = createTestTemplate()
        XCTAssertFalse(template.isArchived)
        
        // When
        try await service.deleteTemplate(template)
        
        // Then
        XCTAssertTrue(template.isArchived, "Template should be marked as archived")
    }
    
    // MARK: - Instance Tests
    
    func testMarkComplete_SetsCompletedFlag() throws {
        // Given
        let instance = createTestInstance()
        XCTAssertFalse(instance.isCompleted)
        
        // When
        service.markComplete(instance)
        
        // Then
        XCTAssertTrue(instance.isCompleted)
        XCTAssertNotNil(instance.completedAt)
    }
    
    func testMarkComplete_CascadesToAtoms() throws {
        // Given
        let instance = createTestInstance()
        XCTAssertFalse(instance.atomInstances[0].isCompleted)
        XCTAssertFalse(instance.atomInstances[1].isCompleted)
        
        // When
        service.markComplete(instance)
        
        // Then
        XCTAssertTrue(instance.atomInstances[0].isCompleted, "First atom should be completed")
        XCTAssertTrue(instance.atomInstances[1].isCompleted, "Second atom should be completed")
    }
    
    func testMarkIncomplete_RevertsCompletionState() throws {
        // Given
        let instance = createTestInstance()
        service.markComplete(instance)
        XCTAssertTrue(instance.isCompleted)
        
        // When
        service.markIncomplete(instance)
        
        // Then
        XCTAssertFalse(instance.isCompleted)
        XCTAssertNil(instance.completedAt)
    }
    
    func testMarkIncomplete_CascadesToAtoms() throws {
        // Given
        let instance = createTestInstance()
        service.markComplete(instance)
        XCTAssertTrue(instance.atomInstances[0].isCompleted)
        
        // When
        service.markIncomplete(instance)
        
        // Then
        XCTAssertFalse(instance.atomInstances[0].isCompleted, "First atom should be incomplete")
        XCTAssertFalse(instance.atomInstances[1].isCompleted, "Second atom should be incomplete")
    }
    
    func testSnooze_MovesScheduledTime() throws {
        // Given
        let instance = createTestInstance()
        let originalTime = instance.scheduledDate
        
        // When
        service.snooze(instance, byMinutes: 15)
        
        // Then
        let expectedTime = Calendar.current.date(byAdding: .minute, value: 15, to: originalTime)!
        XCTAssertEqual(
            instance.scheduledDate.timeIntervalSince1970,
            expectedTime.timeIntervalSince1970,
            accuracy: 1.0,
            "Scheduled time should be moved by 15 minutes"
        )
    }
}
