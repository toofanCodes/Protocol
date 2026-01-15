//
//  SyncHistoryEntry.swift
//  Protocol
//
//  Lightweight model for persisted sync history events.
//  Stored as JSON file, not SwiftData, for simplicity and exportability.
//

import Foundation

/// Represents a single sync operation in the history log
struct SyncHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let action: SyncAction
    let status: SyncResult
    let details: String
    let recordsUploaded: Int
    let recordsDownloaded: Int
    let durationMs: Int
    let errorCode: String?
    let errorMessage: String?
    
    // MARK: - Sync Action Types
    
    enum SyncAction: String, Codable {
        case fullSync           // Normal foreground sync
        case backgroundSync     // BGProcessingTask sync
        case manualSync         // User-initiated "Sync Now"
        case conflictResolution // After user resolves conflict
    }
    
    // MARK: - Sync Result Types
    
    enum SyncResult: String, Codable {
        case success        // All records synced
        case partialSuccess // Some records failed
        case failed         // Sync failed entirely
        case cancelled      // User cancelled
        case skipped        // e.g., already syncing, not signed in
    }
    
    // MARK: - Convenience Initializer
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: SyncAction,
        status: SyncResult,
        details: String = "",
        recordsUploaded: Int = 0,
        recordsDownloaded: Int = 0,
        durationMs: Int = 0,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.status = status
        self.details = details
        self.recordsUploaded = recordsUploaded
        self.recordsDownloaded = recordsDownloaded
        self.durationMs = durationMs
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

// MARK: - Display Helpers

extension SyncHistoryEntry.SyncAction {
    var displayName: String {
        switch self {
        case .fullSync: return "Sync"
        case .backgroundSync: return "Background Sync"
        case .manualSync: return "Manual Sync"
        case .conflictResolution: return "Conflict Resolution"
        }
    }
}

extension SyncHistoryEntry.SyncResult {
    var displayName: String {
        switch self {
        case .success: return "Success"
        case .partialSuccess: return "Partial"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .skipped: return "Skipped"
        }
    }
    
    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .partialSuccess: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled, .skipped: return "minus.circle.fill"
        }
    }
}
