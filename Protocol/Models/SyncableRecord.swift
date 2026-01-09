//
//  SyncableRecord.swift
//  Protocol
//
//  Created on 2026-01-07.
//

import Foundation

/// Protocol for models that support incremental sync with remote storage
/// All syncable records must be identifiable, track modifications, and support soft-delete
protocol SyncableRecord {
    /// Unique identifier for sync operations
    var syncID: UUID { get }
    
    /// Timestamp of last modification (used for conflict resolution)
    var lastModified: Date { get set }
    
    /// Soft-delete flag (deleted records are synced as tombstones, not physically removed)
    var isDeleted: Bool { get set }
    
    /// Serializes the record to JSON for sync
    /// Relationships are stored as UUID references, not nested objects
    func toSyncJSON() -> Data?
}

// MARK: - ISO8601 Date Formatter for Sync

extension SyncableRecord {
    /// Shared ISO8601 formatter for consistent date serialization
    static var syncDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
