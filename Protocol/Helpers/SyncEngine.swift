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
    case syncing(String)            // Message like "Downloading..."
    case success(String)            // Message like "Synced 3↓ 2↑"
    case failed(String)             // Error message
    case simulatorBlocked           // Sync blocked on simulator
    case conflictDetected(SyncConflictInfo)  // Awaiting user resolution
    case awaitingUserDecision       // User is choosing resolution
    
    var isActive: Bool {
        switch self {
        case .syncing: return true
        case .awaitingUserDecision: return true
        default: return false
        }
    }
    
    var message: String {
        switch self {
        case .idle: return ""
        case .syncing(let msg): return msg
        case .success(let msg): return msg
        case .failed(let msg): return msg
        case .simulatorBlocked: return "Sync disabled on simulator"
        case .conflictDetected(let info): return "Conflict with \(info.otherDeviceName)"
        case .awaitingUserDecision: return "Waiting for decision..."
        }
    }
    
    // Equatable conformance for conflictDetected
    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.syncing(let l), .syncing(let r)): return l == r
        case (.success(let l), .success(let r)): return l == r
        case (.failed(let l), .failed(let r)): return l == r
        case (.simulatorBlocked, .simulatorBlocked): return true
        case (.conflictDetected(let l), .conflictDetected(let r)): return l.id == r.id
        case (.awaitingUserDecision, .awaitingUserDecision): return true
        default: return false
        }
    }
}

// MARK: - Sync Engine

/// Orchestrates bidirectional sync between local SwiftData and Google Drive.
/// All sync operations are fail-safe and never crash the app.
/// Includes device-awareness and conflict resolution.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    
    // MARK: - Published State
    
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?
    @Published var pendingConflict: SyncConflictInfo?
    
    /// Convenience computed properties for backward compatibility
    var isSyncing: Bool { syncStatus.isActive }
    var syncError: String? {
        if case .failed(let msg) = syncStatus { return msg }
        return nil
    }
    
    /// Whether a conflict resolution sheet should be shown
    var showConflictSheet: Bool {
        if case .conflictDetected = syncStatus { return true }
        return false
    }
    
    // MARK: - Private
    
    private let lastSyncKey = "com.protocol.sync.lastSyncDate"
    private var pendingContext: ModelContext?
    private var pendingResolution: ConflictResolution?
    
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
        // Simulator safeguard - block sync completely
        #if targetEnvironment(simulator)
        AppLogger.sync.warning("⚠️ Sync blocked on simulator to prevent data conflicts")
        self.syncStatus = .simulatorBlocked
        return
        #endif
        
        // Store context for later use
        pendingContext = context
        
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
        await MainActor.run { self.syncStatus = .syncing("Checking devices...") }
        
        do {
            // Phase 0: Check device registry for conflicts
            let conflictInfo = try await checkForDeviceConflicts(context: context)
            if let conflict = conflictInfo {
                // Conflict detected - wait for user resolution
                await MainActor.run {
                    self.pendingConflict = conflict
                    self.syncStatus = .conflictDetected(conflict)
                }
                AppLogger.sync.info("🔶 Conflict detected with device: \(conflict.otherDeviceName)")
                return
            }
            
            // No conflict - proceed with sync
            await proceedWithSync(context: context)
            
        } catch {
            // Catch ALL errors - never propagate
            let errorMessage = error.localizedDescription
            AppLogger.sync.error("❌ Sync failed: \(errorMessage)")
            
            await MainActor.run {
                self.syncStatus = .failed("Sync failed")
            }
        }
    }
    
    /// Checks device registry and returns conflict info if another device has synced
    private func checkForDeviceConflicts(context: ModelContext) async throws -> SyncConflictInfo? {
        let registry = try await DriveService.shared.fetchDeviceRegistry()
        let currentDeviceID = await MainActor.run { DeviceIdentity.shared.deviceID }
        
        // If this device is already registered, no conflict
        if registry.isDeviceRegistered(deviceID: currentDeviceID) {
            return nil
        }
        
        // If registry is empty, this is the first device - no conflict
        if registry.registeredDevices.isEmpty {
            return nil
        }
        
        // Another device has synced - this is a new device trying to sync
        if let otherDevice = registry.lastOtherDevice(excluding: currentDeviceID) {
            // Count local records
            let localCount = await MainActor.run {
                countLocalRecords(context: context)
            }
            
            return SyncConflictInfo(
                otherDeviceName: otherDevice.deviceName,
                otherDeviceLastSync: otherDevice.lastSyncDate,
                localRecordCount: localCount,
                isOtherDeviceSimulator: otherDevice.isSimulator
            )
        }
        
        return nil
    }
    
    /// Counts total local records for conflict info display
    private nonisolated func countLocalRecords(context: ModelContext) -> Int {
        var count = 0
        
        if let templates = try? context.fetch(FetchDescriptor<MoleculeTemplate>()) {
            count += templates.count
        }
        if let instances = try? context.fetch(FetchDescriptor<MoleculeInstance>()) {
            count += instances.count
        }
        if let atoms = try? context.fetch(FetchDescriptor<AtomTemplate>()) {
            count += atoms.count
        }
        
        return count
    }
    
    /// Handles user's conflict resolution choice
    func handleConflictResolution(_ resolution: ConflictResolution, context: ModelContext) {
        pendingConflict = nil
        
        switch resolution {
        case .useThisDevice:
            // Upload local data, register this device
            AppLogger.sync.info("📱 User chose to use this device's data")
            syncStatus = .syncing("Uploading local data...")
            
            Task.detached(priority: .utility) { [weak self] in
                await self?.uploadLocalDataAndRegister(context: context)
            }
            
        case .useCloudData:
            // Download cloud data, register this device
            AppLogger.sync.info("☁️ User chose to use cloud data")
            syncStatus = .syncing("Downloading cloud data...")
            
            Task.detached(priority: .utility) { [weak self] in
                await self?.downloadCloudDataAndRegister(context: context)
            }
            
        case .cancel:
            AppLogger.sync.info("❌ User cancelled sync")
            syncStatus = .idle
        }
    }
    
    /// Uploads local data and registers this device
    private func uploadLocalDataAndRegister(context: ModelContext) async {
        do {
            // Queue all local records for upload
            let queuedCount = await MainActor.run {
                SyncQueueManager.shared.queueAllRecords(context: context)
            }
            AppLogger.sync.info("📦 Queued \(queuedCount) records for upload")
            
            // Upload
            await MainActor.run { self.syncStatus = .syncing("Uploading \(queuedCount) records...") }
            let uploadedCount = try await DriveService.shared.uploadPendingRecords(context: context)
            
            // Register device
            try await registerCurrentDevice()
            
            await finishSync(downloaded: 0, uploaded: uploadedCount)
        } catch {
            await MainActor.run {
                self.syncStatus = .failed("Upload failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Downloads cloud data and registers this device
    private func downloadCloudDataAndRegister(context: ModelContext) async {
        do {
            // Download from cloud
            await MainActor.run { self.syncStatus = .syncing("Downloading from cloud...") }
            let downloadedCount = try await DriveService.shared.reconcileFromRemote(context: context)
            
            // Register device
            try await registerCurrentDevice()
            
            await finishSync(downloaded: downloadedCount, uploaded: 0)
        } catch {
            await MainActor.run {
                self.syncStatus = .failed("Download failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Registers the current device in the registry
    private func registerCurrentDevice() async throws {
        var registry = try await DriveService.shared.fetchDeviceRegistry()
        let identity = await MainActor.run { DeviceIdentity.shared }
        registry.registerDevice(identity: identity)
        try await DriveService.shared.updateDeviceRegistry(registry)
        AppLogger.sync.info("✅ Device registered: \(identity.shortDescription)")
    }
    
    /// Proceeds with normal sync after conflict check passes
    private func proceedWithSync(context: ModelContext) async {
        do {
            // Phase 1: Pull remote changes
            await MainActor.run { self.syncStatus = .syncing("Downloading...") }
            let downloadedCount = try await DriveService.shared.reconcileFromRemote(context: context)
            
            // Phase 2: Push local changes
            await MainActor.run { self.syncStatus = .syncing("Uploading...") }
            let uploadedCount = try await DriveService.shared.uploadPendingRecords(context: context)
            
            // Update device registry
            try await registerCurrentDevice()
            
            await finishSync(downloaded: downloadedCount, uploaded: uploadedCount)
            
        } catch {
            let errorMessage = error.localizedDescription
            AppLogger.sync.error("❌ Sync failed: \(errorMessage)")
            
            await MainActor.run {
                self.syncStatus = .failed("Sync failed")
            }
        }
    }
    
    /// Finishes sync with success status
    private func finishSync(downloaded: Int, uploaded: Int) async {
        let now = Date()
        await MainActor.run {
            self.lastSyncDate = now
            UserDefaults.standard.set(now, forKey: self.lastSyncKey)
            
            let message = downloaded + uploaded > 0
                ? "Synced \(downloaded)↓ \(uploaded)↑"
                : "Up to date"
            self.syncStatus = .success(message)
        }
        
        AppLogger.sync.info("✅ Sync complete: \(downloaded) down, \(uploaded) up")
        
        // Auto-hide success after delay
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run {
            if case .success = self.syncStatus {
                self.syncStatus = .idle
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
        if case .simulatorBlocked = syncStatus {
            syncStatus = .idle
        }
    }
    
    /// Dismisses any visible status
    func dismissStatus() {
        syncStatus = .idle
    }
}

