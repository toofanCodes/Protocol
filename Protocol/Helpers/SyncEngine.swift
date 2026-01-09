//
//  SyncEngine.swift
//  Protocol
//
//  Created on 2026-01-08.
//

import Foundation
import SwiftData
import Combine

// MARK: - Sync Status Enum

/// Represents the current state of sync operations
enum SyncStatus: Equatable {
    case idle
    case syncing(String)  // Message like "Downloading..."
    case success(String)  // Message like "Synced 3↓ 2↑"
    case failed(String)   // Error message
    
    var isActive: Bool {
        if case .syncing = self { return true }
        return false
    }
    
    var message: String {
        switch self {
        case .idle: return ""
        case .syncing(let msg): return msg
        case .success(let msg): return msg
        case .failed(let msg): return msg
        }
    }
}

// MARK: - Sync Engine

/// Orchestrates bidirectional sync between local SwiftData and Google Drive.
/// All sync operations are fail-safe and never crash the app.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    
    // MARK: - Published State
    
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?
    
    /// Convenience computed properties for backward compatibility
    var isSyncing: Bool { syncStatus.isActive }
    var syncError: String? {
        if case .failed(let msg) = syncStatus { return msg }
        return nil
    }
    
    // MARK: - Private
    
    private let lastSyncKey = "com.protocol.sync.lastSyncDate"
    
    private init() {
        // Load last sync date
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = timestamp
        }
    }
    
    // MARK: - Public API (Fail-Safe)
    
    /// Performs a full sync in a completely sandboxed manner.
    /// This method NEVER throws and NEVER crashes the app.
    /// Safe to call from anywhere, including app launch.
    /// - Parameter context: ModelContext for SwiftData operations
    func performFullSyncSafely(context: ModelContext) {
        // Fire and forget - runs in detached task
        Task.detached(priority: .utility) { [weak self] in
            await self?.executeSync(context: context)
        }
    }
    
    /// Internal sync execution with full error handling
    private func executeSync(context: ModelContext) async {
        // Check if user is signed in
        let isSignedIn = await MainActor.run { GoogleAuthManager.shared.isSignedIn }
        guard isSignedIn else {
            AppLogger.sync.debug("Sync skipped: User not signed in")
            return
        }
        
        // Prevent concurrent syncs
        let alreadySyncing = await MainActor.run { self.syncStatus.isActive }
        guard !alreadySyncing else {
            AppLogger.sync.debug("Sync skipped: Already in progress")
            return
        }
        
        // Start sync
        await MainActor.run { self.syncStatus = .syncing("Syncing...") }
        
        do {
            // Phase 1: Pull remote changes
            await MainActor.run { self.syncStatus = .syncing("Downloading...") }
            let downloadedCount = try await DriveService.shared.reconcileFromRemote(context: context)
            
            // Phase 2: Push local changes
            await MainActor.run { self.syncStatus = .syncing("Uploading...") }
            let uploadedCount = try await DriveService.shared.uploadPendingRecords(context: context)
            
            // Success
            let now = Date()
            await MainActor.run {
                self.lastSyncDate = now
                UserDefaults.standard.set(now, forKey: self.lastSyncKey)
                
                let message = downloadedCount + uploadedCount > 0
                    ? "Synced \(downloadedCount)↓ \(uploadedCount)↑"
                    : "Up to date"
                self.syncStatus = .success(message)
            }
            
            AppLogger.sync.info("✅ Sync complete: \(downloadedCount) down, \(uploadedCount) up")
            
            // Auto-hide success after delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if case .success = self.syncStatus {
                    self.syncStatus = .idle
                }
            }
            
        } catch {
            // Catch ALL errors - never propagate
            let errorMessage = error.localizedDescription
            AppLogger.sync.error("❌ Sync failed: \(errorMessage)")
            
            await MainActor.run {
                self.syncStatus = .failed("Sync failed")
            }
        }
    }
    
    /// Legacy method - now delegates to safe version
    func performFullSync(context: ModelContext) async {
        performFullSyncSafely(context: context)
    }
    
    /// Clears error state
    func clearError() {
        if case .failed = syncStatus {
            syncStatus = .idle
        }
    }
    
    /// Dismisses any visible status
    func dismissStatus() {
        syncStatus = .idle
    }
}

