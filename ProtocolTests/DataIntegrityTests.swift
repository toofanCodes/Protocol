//
//  DataIntegrityTests.swift
//  ProtocolTests
//
//  Critical tests for data loss and leak prevention.
//

import XCTest
import SwiftData
@testable import Protocol

@MainActor
final class DataIntegrityTests: XCTestCase {
    
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
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
    }
    
    override func tearDownWithError() throws {
        context = nil
        container = nil
    }
    
    // MARK: - Orphan Prevention Tests
    
    func testDeleteTemplate_DoesNotCreateOrphanInstances() throws {
        // Given: A template with instances
        let template = MoleculeTemplate(
            title: "Test",
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1, 2, 3, 4, 5, 6, 7]
        )
        context.insert(template)
        
        let instance1 = MoleculeInstance(scheduledDate: Date(), parentTemplate: template)
        let instance2 = MoleculeInstance(
            scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            parentTemplate: template
        )
        context.insert(instance1)
        context.insert(instance2)
        template.instances = [instance1, instance2]
        try context.save()
        
        // When: Template is deleted
        context.delete(template)
        try context.save()
        
        // Then: All instances should be deleted (cascade delete)
        let descriptor = FetchDescriptor<MoleculeInstance>()
        let remainingInstances = try context.fetch(descriptor)
        XCTAssertEqual(remainingInstances.count, 0, "No orphan instances should remain after template deletion")
    }
    
    func testDeleteAtomTemplate_DoesNotAffectOtherAtoms() throws {
        // Given: A template with multiple atoms
        let template = MoleculeTemplate(
            title: "Test",
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1]
        )
        context.insert(template)
        
        let atom1 = AtomTemplate(title: "Atom 1", order: 0, parentMoleculeTemplate: template)
        let atom2 = AtomTemplate(title: "Atom 2", order: 1, parentMoleculeTemplate: template)
        context.insert(atom1)
        context.insert(atom2)
        template.atomTemplates = [atom1, atom2]
        try context.save()
        
        // When: One atom is deleted
        context.delete(atom1)
        try context.save()
        
        // Then: Other atom should remain, template should be intact
        let templateDescriptor = FetchDescriptor<MoleculeTemplate>()
        let templates = try context.fetch(templateDescriptor)
        XCTAssertEqual(templates.count, 1, "Template should still exist")
        XCTAssertEqual(templates.first?.atomTemplates.count, 1, "One atom should remain")
        XCTAssertEqual(templates.first?.atomTemplates.first?.title, "Atom 2", "Correct atom should remain")
    }
    
    // MARK: - Relationship Integrity Tests
    
    func testInstance_MaintainsParentRelationship() throws {
        // Given
        let template = MoleculeTemplate(
            title: "Parent",
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1]
        )
        context.insert(template)
        
        let instance = MoleculeInstance(scheduledDate: Date(), parentTemplate: template)
        context.insert(instance)
        try context.save()
        
        // When: Fetch instance fresh
        let descriptor = FetchDescriptor<MoleculeInstance>()
        let fetchedInstances = try context.fetch(descriptor)
        
        // Then: Parent relationship should be maintained
        XCTAssertNotNil(fetchedInstances.first?.parentTemplate)
        XCTAssertEqual(fetchedInstances.first?.parentTemplate?.title, "Parent")
    }
    
    func testAtomInstance_MaintainsParentRelationship() throws {
        // Given
        let moleculeInstance = MoleculeInstance(scheduledDate: Date())
        context.insert(moleculeInstance)
        
        let atomInstance = AtomInstance(title: "Task", parentMoleculeInstance: moleculeInstance)
        context.insert(atomInstance)
        moleculeInstance.atomInstances = [atomInstance]
        try context.save()
        
        // When: Fetch atom fresh
        let descriptor = FetchDescriptor<AtomInstance>()
        let fetchedAtoms = try context.fetch(descriptor)
        
        // Then: Parent relationship should be maintained
        XCTAssertNotNil(fetchedAtoms.first?.parentMoleculeInstance)
    }
    
    // MARK: - Soft Delete Integrity Tests
    
    func testArchiveTemplate_PreservesHistoricalData() throws {
        // Given: A template with past instances
        let template = MoleculeTemplate(
            title: "Historical",
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1]
        )
        context.insert(template)
        
        // Past instance (should be preserved)
        let pastInstance = MoleculeInstance(
            scheduledDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            isCompleted: true,
            parentTemplate: template
        )
        context.insert(pastInstance)
        template.instances = [pastInstance]
        try context.save()
        
        // When: Template is archived
        template.isArchived = true
        try context.save()
        
        // Then: Past instance should still exist
        let descriptor = FetchDescriptor<MoleculeInstance>()
        let instances = try context.fetch(descriptor)
        XCTAssertEqual(instances.count, 1, "Historical instance should be preserved")
        XCTAssertTrue(instances.first?.isCompleted ?? false, "Completion status preserved")
    }
    
    // MARK: - Completion Cascade Integrity Tests
    
    func testMarkComplete_SetsCompletedAtTimestamp() throws {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date())
        context.insert(instance)
        XCTAssertNil(instance.completedAt)
        
        // When
        instance.markComplete()
        
        // Then
        XCTAssertNotNil(instance.completedAt, "completedAt should be set")
        XCTAssertTrue(instance.isCompleted)
    }
    
    func testMarkIncomplete_ClearsCompletedAtTimestamp() throws {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date(), isCompleted: true)
        instance.completedAt = Date()
        context.insert(instance)
        
        // When
        instance.markIncomplete()
        
        // Then
        XCTAssertNil(instance.completedAt, "completedAt should be cleared")
        XCTAssertFalse(instance.isCompleted)
    }
    
    // MARK: - Data Consistency Tests
    
    func testGenerateInstances_IsIdempotent() throws {
        // Given: A template
        let template = MoleculeTemplate(
            title: "Daily",
            baseTime: Date(),
            recurrenceFreq: .daily,
            recurrenceDays: [1, 2, 3, 4, 5, 6, 7]
        )
        context.insert(template)
        try context.save()
        
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        
        // When: Generate instances twice
        let firstRun = template.generateInstances(until: futureDate, in: context)
        for instance in firstRun {
            context.insert(instance)
        }
        try context.save()
        
        let secondRun = template.generateInstances(until: futureDate, in: context)
        
        // Then: Second run should return empty (no duplicates)
        XCTAssertEqual(secondRun.count, 0, "Idempotent generation should not create duplicates")
        
        // Verify total count is same as first run
        let descriptor = FetchDescriptor<MoleculeInstance>()
        let allInstances = try context.fetch(descriptor)
        XCTAssertEqual(allInstances.count, firstRun.count, "No duplicate instances should exist")
    }
}
