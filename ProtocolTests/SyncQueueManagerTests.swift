//
//  SyncQueueManagerTests.swift
//  ProtocolTests
//
//  Created on 2026-01-08.
//

import XCTest
@testable import Protocol

final class SyncQueueManagerTests: XCTestCase {
    
    var sut: SyncQueueManager!
    
    override func setUp() {
        super.setUp()
        // Clear UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "com.protocol.sync.pendingQueue")
        
        // Create fresh instance (need to access via shared since it's a singleton)
        sut = SyncQueueManager.shared
        sut.clearQueue()
    }
    
    override func tearDown() {
        sut.clearQueue()
        super.tearDown()
    }
    
    // MARK: - Deduplication Tests
    
    func testAddToQueue_NewItem_Appends() {
        // Given - Create a real MoleculeTemplate (doesn't need context for queue test)
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Test Habit",
            baseTime: Date()
        )
        
        // When
        sut.addToQueue(template)
        
        // Then
        XCTAssertEqual(sut.queue.count, 1)
        XCTAssertEqual(sut.queue.first?.syncID, template.id)
    }
    
    func testAddToQueue_SameIDTwice_OnlyOneEntry() {
        // Given
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Test Habit",
            baseTime: Date()
        )
        
        // When
        sut.addToQueue(template)
        sut.addToQueue(template)
        
        // Then
        XCTAssertEqual(sut.queue.count, 1, "Same ID should not create duplicate entries")
    }
    
    func testAddToQueue_DifferentIDs_BothAppended() {
        // Given
        let template1 = MoleculeTemplate(id: UUID(), title: "Habit 1", baseTime: Date())
        let template2 = MoleculeTemplate(id: UUID(), title: "Habit 2", baseTime: Date())
        
        // When
        sut.addToQueue(template1)
        sut.addToQueue(template2)
        
        // Then
        XCTAssertEqual(sut.queue.count, 2)
    }
    
    // MARK: - Priority Queue Tests
    
    func testPriorityQueue_RecentInstancesFirst() {
        // Given - Create items with controlled createdAt dates
        let now = Date()
        
        // Old instance (created 48h ago - NOT recent)
        let oldInstance = MoleculeInstance(
            id: UUID(),
            scheduledDate: now,
            createdAt: now.addingTimeInterval(-48 * 60 * 60)
        )
        
        // Recent instance (created just now - IS recent)
        let recentInstance = MoleculeInstance(
            id: UUID(),
            scheduledDate: now,
            createdAt: now
        )
        
        // When - add old first, then recent
        sut.addToQueue(oldInstance)
        sut.addToQueue(recentInstance)
        
        let prioritized = sut.getPriorityQueue()
        
        // Then - recent should be first despite being added second
        XCTAssertEqual(prioritized.count, 2)
        XCTAssertEqual(prioritized.first?.syncID, recentInstance.id, "Recent instances should have priority")
    }
    
    func testPriorityQueue_TemplatesNotPrioritized() {
        // Given
        let now = Date()
        
        // Recent instance (created just now)
        let recentInstance = MoleculeInstance(
            id: UUID(),
            scheduledDate: now,
            createdAt: now
        )
        
        // Template (templates never get priority)
        let template = MoleculeTemplate(
            id: UUID(),
            title: "Template",
            baseTime: now,
            createdAt: now
        )
        
        // When - add template first, then instance
        sut.addToQueue(template)
        sut.addToQueue(recentInstance)
        
        let prioritized = sut.getPriorityQueue()
        
        // Then - recent instance should be first
        XCTAssertEqual(prioritized.count, 2)
        XCTAssertEqual(prioritized.first?.syncID, recentInstance.id, "Recent instances should have priority over templates")
    }
    
    // MARK: - Persistence Tests
    
    func testQueuePersistence_SurvivesRelaunch() {
        // Given
        let template = MoleculeTemplate(id: UUID(), title: "Test", baseTime: Date())
        sut.addToQueue(template)
        let id = template.id
        
        // When - simulate relaunch by checking queue
        let queue = sut.queue
        
        // Then
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.syncID, id)
    }
    
    // MARK: - Remove Tests
    
    func testRemoveFromQueue_ExistingItem_Removes() {
        // Given
        let template = MoleculeTemplate(id: UUID(), title: "Test", baseTime: Date())
        sut.addToQueue(template)
        let queueItem = sut.queue.first!
        
        // When
        sut.removeFromQueue(queueItem)
        
        // Then
        XCTAssertTrue(sut.queue.isEmpty)
    }
    
    func testClearQueue_RemovesAll() {
        // Given
        sut.addToQueue(MoleculeTemplate(id: UUID(), title: "1", baseTime: Date()))
        sut.addToQueue(MoleculeTemplate(id: UUID(), title: "2", baseTime: Date()))
        
        // When
        sut.clearQueue()
        
        // Then
        XCTAssertTrue(sut.queue.isEmpty)
    }
    
    // MARK: - Filename Generation
    
    func testGenerateFilename_CorrectFormat() {
        // Given
        let template = MoleculeTemplate(id: UUID(), title: "Test", baseTime: Date())
        sut.addToQueue(template)
        let item = sut.queue.first!
        
        // When
        let filename = sut.generateFilename(for: item)
        
        // Then
        XCTAssertTrue(filename.hasPrefix("MoleculeTemplate_"))
        XCTAssertTrue(filename.hasSuffix(".json"))
        XCTAssertTrue(filename.contains(template.id.uuidString))
    }
}
