//
//  SyncJSONRoundTripTests.swift
//  ProtocolTests
//
//  Created on 2026-01-08.
//

import XCTest
import SwiftData
@testable import Protocol

/// Tests that verify all fields survive serialization → upload → download → deserialization
final class SyncJSONRoundTripTests: XCTestCase {
    
    // MARK: - Helper
    
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
    
    // MARK: - MoleculeTemplate Round Trip
    
    func testMoleculeTemplate_AllFieldsRoundTrip() throws {
        let original = MoleculeTemplate(
            id: UUID(),
            title: "Test Habit",
            baseTime: Date(),
            recurrenceFreq: .weekly,
            recurrenceDays: [1, 3, 5],
            endRuleType: .afterOccurrences,
            endRuleDate: nil,
            endRuleCount: 30,
            notes: "Test notes",
            compound: "Health",
            alertOffsets: [0, 15, 60],
            isAllDay: true,
            iconSymbol: "🏃"
        )
        original.isPinned = true
        original.sortOrder = 5
        original.iconFrameRaw = "hexagon"
        original.themeColorHex = "#FF5733"
        
        guard let jsonData = original.toSyncJSON() else {
            XCTFail("Failed to serialize MoleculeTemplate")
            return
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        XCTAssertNotNil(json["syncID"], "syncID should be present")
        XCTAssertNotNil(json["title"], "title should be present")
        XCTAssertNotNil(json["baseTime"], "baseTime should be present")
        XCTAssertNotNil(json["recurrenceFreq"], "recurrenceFreq should be present")
        XCTAssertNotNil(json["recurrenceDays"], "recurrenceDays should be present")
        XCTAssertNotNil(json["endRuleType"], "endRuleType should be present")
        XCTAssertNotNil(json["endRuleCount"], "endRuleCount should be present")
        XCTAssertNotNil(json["notes"], "notes should be present")
        XCTAssertNotNil(json["compound"], "compound should be present")
        XCTAssertNotNil(json["alertOffsets"], "alertOffsets should be present")
        XCTAssertEqual(json["isAllDay"] as? Bool, true, "isAllDay should be true")
        XCTAssertNotNil(json["iconSymbol"], "iconSymbol should be present")
        XCTAssertEqual(json["isPinned"] as? Bool, true, "isPinned should be true")
        XCTAssertEqual(json["sortOrder"] as? Int, 5, "sortOrder should be 5")
        XCTAssertEqual(json["iconFrameRaw"] as? String, "hexagon", "iconFrameRaw should be hexagon")
        XCTAssertEqual(json["themeColorHex"] as? String, "#FF5733", "themeColorHex should match")
        
        XCTAssertEqual(json["title"] as? String, "Test Habit")
        XCTAssertEqual(json["recurrenceFreq"] as? String, "weekly")
        XCTAssertEqual(json["recurrenceDays"] as? [Int], [1, 3, 5])
    }
    
    // MARK: - MoleculeInstance Round Trip
    
    func testMoleculeInstance_AllFieldsRoundTrip() throws {
        let original = MoleculeInstance(
            id: UUID(),
            scheduledDate: Date(),
            isCompleted: true,
            isException: true,
            exceptionTitle: "Custom Title",
            exceptionTime: Date().addingTimeInterval(3600),
            alertOffsets: [0, 30],
            isAllDay: false,
            notes: "Instance notes"
        )
        original.completedAt = Date()
        original.originalScheduledDate = Date().addingTimeInterval(-86400)
        
        guard let jsonData = original.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to serialize MoleculeInstance")
            return
        }
        
        XCTAssertNotNil(json["syncID"])
        XCTAssertNotNil(json["scheduledDate"])
        XCTAssertEqual(json["isCompleted"] as? Bool, true)
        XCTAssertEqual(json["isException"] as? Bool, true)
        XCTAssertEqual(json["exceptionTitle"] as? String, "Custom Title")
        XCTAssertNotNil(json["exceptionTime"])
        XCTAssertNotNil(json["alertOffsets"])
        XCTAssertEqual(json["isAllDay"] as? Bool, false)
        XCTAssertNotNil(json["completedAt"])
        XCTAssertNotNil(json["originalScheduledDate"])
        XCTAssertEqual(json["notes"] as? String, "Instance notes")
    }
    
    // MARK: - AtomTemplate Round Trip
    
    func testAtomTemplate_AllFieldsRoundTrip() throws {
        let original = AtomTemplate(
            id: UUID(),
            title: "Bench Press",
            inputType: .value,
            targetValue: 91.0,
            unit: "kg",
            order: 2,
            targetSets: 4,
            targetReps: 12,
            defaultRestTime: 90,
            videoURL: "https://example.com/video",
            iconSymbol: "🏋️"
        )
        original.iconFrameRaw = "square"
        original.themeColorHex = "#00FF00"
        
        guard let jsonData = original.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to serialize AtomTemplate")
            return
        }
        
        XCTAssertNotNil(json["syncID"])
        XCTAssertEqual(json["title"] as? String, "Bench Press")
        XCTAssertEqual(json["inputType"] as? String, "value")
        XCTAssertEqual(json["targetValue"] as? Double, 91.0)
        XCTAssertEqual(json["unit"] as? String, "kg")
        XCTAssertEqual(json["order"] as? Int, 2)
        XCTAssertEqual(json["targetSets"] as? Int, 4)
        XCTAssertEqual(json["targetReps"] as? Int, 12)
        XCTAssertEqual(json["defaultRestTime"] as? Double, 90)
        XCTAssertEqual(json["videoURL"] as? String, "https://example.com/video")
        XCTAssertEqual(json["iconSymbol"] as? String, "🏋️")
        XCTAssertEqual(json["iconFrameRaw"] as? String, "square")
        XCTAssertEqual(json["themeColorHex"] as? String, "#00FF00")
    }
    
    // MARK: - Tombstone Tests
    
    func testMoleculeTemplate_DeletedRecord_HasTombstoneFlag() throws {
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Deleted Habit",
            baseTime: Date()
        )
        template.isArchived = true
        
        guard let jsonData = template.toSyncJSON(),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to serialize")
            return
        }
        
        XCTAssertEqual(json["isDeleted"] as? Bool, true, "Archived templates should have isDeleted=true")
    }
}
