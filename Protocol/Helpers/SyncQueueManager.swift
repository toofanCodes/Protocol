//
//  SyncQueueManager.swift
//  Protocol
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftData
import Combine

/// Tracks dirty records that need to be synced to the cloud.
/// Manages a persistent queue of pending uploads, prioritizing recent user activity.
class SyncQueueManager: ObservableObject {
    static let shared = SyncQueueManager()
    
    // MARK: - Types
    
    struct PendingSyncItem: Codable, Identifiable, Equatable {
        var id: UUID { syncID }
        let syncID: UUID
        let modelType: String // e.g., "MoleculeInstance"
        let itemCreatedAt: Date? // Used for priority logic
        let queuedAt: Date
        
        static func == (lhs: PendingSyncItem, rhs: PendingSyncItem) -> Bool {
            lhs.syncID == rhs.syncID && lhs.modelType == rhs.modelType
        }
    }
    
    // MARK: - Properties
    
    @Published private(set) var queue: [PendingSyncItem] = []
    private let userDefaultsKey = "com.protocol.sync.pendingQueue"
    private let recentActivityThreshold: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - Initialization
    
    private init() {
        loadQueue()
    }
    
    // MARK: - Queue Management
    
    /// Adds a record to the sync queue.
    /// If the record is already queued, it updates the timestamp (moves to back of its priority group).
    func addToQueue(_ record: any SyncableRecord) {
        let modelType = String(describing: type(of: record))
        
        // Try to cast to a type that has createdAt if possible, or pass it in explicitly?
        // Since SyncableRecord doesn't strictly require 'createdAt', we'll rely on optional casting
        // or just accept nil for priority if unknown.
        var createdAt: Date? = nil
        
        // Attempt to extract creation date for priority logic
        if let instance = record as? MoleculeInstance {
            createdAt = instance.createdAt
        } else if let template = record as? MoleculeTemplate {
            createdAt = template.createdAt
        } else if let atomT = record as? AtomTemplate {
            createdAt = atomT.createdAt
        }
        
        let newItem = PendingSyncItem(
            syncID: record.syncID,
            modelType: modelType,
            itemCreatedAt: createdAt,
            queuedAt: Date()
        )
        
        insertOrUpdate(newItem)
        saveQueue()
    }
    
    /// Removes an item from the queue (e.g., after successful upload)
    func removeFromQueue(_ item: PendingSyncItem) {
        queue.removeAll { $0 == item }
        saveQueue()
    }
    
    /// Clears the entire queue
    func clearQueue() {
        queue.removeAll()
        saveQueue()
    }
    
    /// Queues ALL existing records for sync (one-time initial sync)
    /// - Parameter context: ModelContext to query records from
    /// - Returns: Number of records queued
    @MainActor
    func queueAllRecords(context: ModelContext) -> Int {
        var count = 0
        
        // Queue all MoleculeTemplates
        let templateDescriptor = FetchDescriptor<MoleculeTemplate>()
        if let templates = try? context.fetch(templateDescriptor) {
            for template in templates {
                addToQueue(template)
                count += 1
                
                // Also queue all atoms for this template
                for atom in template.atomTemplates {
                    addToQueue(atom)
                    count += 1
                }
            }
        }
        
        // Queue all MoleculeInstances
        let instanceDescriptor = FetchDescriptor<MoleculeInstance>()
        if let instances = try? context.fetch(instanceDescriptor) {
            for instance in instances {
                addToQueue(instance)
                count += 1
            }
        }
        
        print("📦 Queued \(count) records for initial sync")
        return count
    }
    
    // MARK: - Prioritization
    
    /// Returns the pending items sorted by upload priority.
    /// Priority 1: Recent MoleculeInstances (created < 24h ago) - "Current Session"
    /// Priority 2: Everything else (Historical data, templates)
    func getPriorityQueue() -> [PendingSyncItem] {
        let now = Date()
        
        return queue.sorted { item1, item2 in
            let isItem1Recent = isRecent(item1, now: now)
            let isItem2Recent = isRecent(item2, now: now)
            
            if isItem1Recent && !isItem2Recent {
                return true // Item 1 comes first
            } else if !isItem1Recent && isItem2Recent {
                return false // Item 2 comes first
            } else {
                // Same priority level: FIFO (oldest queued first)
                return item1.queuedAt < item2.queuedAt
            }
        }
    }
    
    private func isRecent(_ item: PendingSyncItem, now: Date) -> Bool {
        // Only prioritize MoleculeInstances recently created
        guard item.modelType == "MoleculeInstance", let created = item.itemCreatedAt else {
            return false
        }
        return now.timeIntervalSince(created) < recentActivityThreshold
    }
    
    // MARK: - File Naming
    
    /// Generates a standard filename for Google Drive
    /// Format: [ModelType]_[syncID].json
    func generateFilename(for item: PendingSyncItem) -> String {
        return "\(item.modelType)_\(item.syncID.uuidString).json"
    }
    
    // MARK: - Persistence
    
    private func saveQueue() {
        if let encoded = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([PendingSyncItem].self, from: data) {
            queue = decoded
        }
    }
    
    // MARK: - Helper (Private)
    
    private func insertOrUpdate(_ item: PendingSyncItem) {
        // Remove existing entry for this ID if present (to update it)
        queue.removeAll { $0 == item }
        queue.append(item)
    }
}
