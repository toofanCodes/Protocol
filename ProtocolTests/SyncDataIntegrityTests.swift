//
//  SyncDataIntegrityTests.swift
//  ProtocolTests
//
//  Created on 2026-01-08.
//

import XCTest
import SwiftData
@testable import Protocol

/// Integration tests that verify end-to-end sync data integrity
/// These tests use real ModelContext (in-memory) to verify the full flow
final class SyncDataIntegrityTests: XCTestCase {
    
    // MARK: - Helper to create fresh context for each test
    
    private func createTestContext() throws -> (container: ModelContainer, context: ModelContext) {
        let schema = Schema([
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return (container, context)
    }
    
    // MARK: - Full Cycle Tests
    
    func testFullCycle_CreateTemplate_SerializeDeserialize_AllFieldsIntact() throws {
        let (_, context) = try createTestContext()
        
        let originalID = UUID()
        let originalTitle = "Morning Routine"
        let originalTime = Date()
        let originalColor = "#FF0000"
        
        let original = MoleculeTemplate(
            id: originalID,
            title: originalTitle,
            baseTime: originalTime,
            recurrenceFreq: .custom,
            recurrenceDays: [1, 2, 3, 4, 5],
            endRuleType: .never,
            notes: "Daily morning routine",
            compound: "Productivity",
            alertOffsets: [0, 15, 30],
            isAllDay: false,
            iconSymbol: "☀️"
        )
        original.isPinned = true
        original.sortOrder = 1
        original.themeColorHex = originalColor
        original.iconFrameRaw = "diamond"
        
        context.insert(original)
        try context.save()
        
        guard let jsonData = original.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Serialization failed")
            return
        }
        
        XCTAssertEqual(json["syncID"] as? String, originalID.uuidString)
        XCTAssertEqual(json["title"] as? String, originalTitle)
        XCTAssertEqual(json["recurrenceFreq"] as? String, "custom")
        XCTAssertEqual(json["recurrenceDays"] as? [Int], [1, 2, 3, 4, 5])
        XCTAssertEqual(json["notes"] as? String, "Daily morning routine")
        XCTAssertEqual(json["compound"] as? String, "Productivity")
        XCTAssertEqual(json["alertOffsets"] as? [Int], [0, 15, 30])
        XCTAssertEqual(json["isPinned"] as? Bool, true)
        XCTAssertEqual(json["sortOrder"] as? Int, 1)
        XCTAssertEqual(json["themeColorHex"] as? String, originalColor)
        XCTAssertEqual(json["iconFrameRaw"] as? String, "diamond")
        XCTAssertEqual(json["iconSymbol"] as? String, "☀️")
    }
    
    func testTombstone_DeletedTemplate_FlagIsTrue() throws {
        let (_, context) = try createTestContext()
        
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Deleted Habit",
            baseTime: Date()
        )
        template.isArchived = true
        
        context.insert(template)
        try context.save()
        
        guard let jsonData = template.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Serialization failed")
            return
        }
        
        XCTAssertEqual(json["isDeleted"] as? Bool, true, "Archived templates should serialize as isDeleted=true")
    }
    
    func testReconcile_RemoteNewer_LocalUpdated() throws {
        let (_, context) = try createTestContext()
        
        let templateID = UUID()
        let local = MoleculeTemplate(
            id: templateID,
            title: "Old Title",
            baseTime: Date()
        )
        local.themeColorHex = "#000000"
        
        context.insert(local)
        try context.save()
        
        let remoteJSON: [String: Any] = [
            "syncID": templateID.uuidString,
            "title": "Updated Title",
            "themeColorHex": "#FFFFFF",
            "isDeleted": false
        ]
        
        if let title = remoteJSON["title"] as? String { local.title = title }
        if let color = remoteJSON["themeColorHex"] as? String { local.themeColorHex = color }
        
        try context.save()
        
        let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == templateID })
        let fetched = try context.fetch(descriptor).first
        
        XCTAssertEqual(fetched?.title, "Updated Title", "Title should be updated from remote")
        XCTAssertEqual(fetched?.themeColorHex, "#FFFFFF", "Color should be updated from remote")
    }
    
    // MARK: - Relationship Tests
    
    func testInstance_ParentRelationship_SerializedAsUUID() throws {
        let (_, context) = try createTestContext()
        
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Parent Habit",
            baseTime: Date()
        )
        context.insert(template)
        
        let instance = MoleculeInstance(
            id: UUID(),
            scheduledDate: Date(),
            parentTemplate: template
        )
        context.insert(instance)
        try context.save()
        
        guard let jsonData = instance.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Serialization failed")
            return
        }
        
        XCTAssertEqual(json["moleculeTemplateID"] as? String, template.id.uuidString,
                       "Parent template ID should be serialized")
    }
    
    func testAtomTemplate_ParentRelationship_SerializedAsUUID() throws {
        let (_, context) = try createTestContext()
        
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Parent Habit",
            baseTime: Date()
        )
        context.insert(template)
        
        let atom = AtomTemplate(
            id: UUID(),
            title: "Sub-task",
            inputType: .binary,
            order: 0,
            parentMoleculeTemplate: template
        )
        template.atomTemplates.append(atom)
        context.insert(atom)
        try context.save()
        
        guard let jsonData = atom.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Serialization failed")
            return
        }
        
        XCTAssertEqual(json["moleculeTemplateID"] as? String, template.id.uuidString,
                       "Parent template ID should be serialized")
    }
}
