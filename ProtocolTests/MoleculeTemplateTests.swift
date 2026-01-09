//
//  MoleculeTemplateTests.swift
//  ProtocolTests
//
//  Created by Protocol Architect on 2026-01-07.
//

import XCTest
import SwiftData
@testable import Protocol

@MainActor
final class MoleculeTemplateTests: XCTestCase {
    
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
        container = nil
        context = nil
    }
    
    // MARK: - Generation Tests
    
    func testGenerateInstances_Daily_CreateCorrectCount() {
        // Given
        let start = Calendar.current.startOfDay(for: Date())
        let template = MoleculeTemplate(
            title: "Daily Habit",
            baseTime: start,
            recurrenceFreq: .daily
        )
        context.insert(template)
        
        // When: Generating for 5 days
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let instances = template.generateInstances(from: start, until: end, in: context)
        
        // Then
        XCTAssertEqual(instances.count, 5, "Should generate 5 instances for 5 days")
        
        // Verify dates
        for (index, instance) in instances.enumerated() {
            let expectedDate = Calendar.current.date(byAdding: .day, value: index, to: start)!
            XCTAssertTrue(Calendar.current.isDate(instance.scheduledDate, inSameDayAs: expectedDate))
        }
    }
    
    func testGenerateInstances_EndRuleCount_StopsEventually() {
        // Given
        let start = Calendar.current.startOfDay(for: Date())
        let template = MoleculeTemplate(
            title: "Limited Habit",
            baseTime: start,
            recurrenceFreq: .daily
        )
        template.endRuleType = .afterOccurrences
        template.endRuleCount = 3
        context.insert(template)
        
        // When: Generates for 10 days
        let end = Calendar.current.date(byAdding: .day, value: 9, to: start)!
        let instances = template.generateInstances(from: start, until: end, in: context)
        
        // Then
        XCTAssertEqual(instances.count, 3, "Should only generate 3 instances due to end rule")
    }
    
    func testGenerateInstances_Idempotency_DoNotDuplicate() {
        // Given
        let start = Calendar.current.startOfDay(for: Date())
        let template = MoleculeTemplate(
            title: "Idempotency Check",
            baseTime: start,
            recurrenceFreq: .daily
        )
        context.insert(template)
        
        // 1. Generate first batch (Day 1-2)
        let mid = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let initialInstances = template.generateInstances(from: start, until: mid, in: context)
        // Save to simulate existing data
        for instance in initialInstances { context.insert(instance) }
        try? context.save()
        XCTAssertEqual(initialInstances.count, 2)
        
        // 2. Generate overlapping batch (Day 1-3)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let newInstances = template.generateInstances(from: start, until: end, in: context)
        
        // Then: Should only generate Day 3 (1 new instance)
        XCTAssertEqual(newInstances.count, 1, "Should only generate the 1 missing instance")
        XCTAssertTrue(Calendar.current.isDate(newInstances.first!.scheduledDate, inSameDayAs: end))
    }
}
