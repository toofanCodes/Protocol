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
    
    // MARK: - Private
    
    private let lastSyncKey = "com.protocol.sync.lastSyncDate"
    private let lastForegroundSyncKey = "com.protocol.sync.lastForegroundSync"
    private let minimumSyncInterval: TimeInterval = 5 * 60  // 5 minutes
    private var pendingResolution: ConflictResolution?
    private var syncStartTime: Date?  // Tracks sync duration for history
    
    // Kept for conflict resolution flow
    private var cachedContainer: ModelContainer?
    
    // MARK: - Dependencies (Internal for Testing)
    
    var driveService: DriveServiceProtocol = DriveService.shared
    var isSignedInCheck: () -> Bool = { GoogleAuthManager.shared.isSignedIn }
    
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
    /// Respects 5-minute throttle to prevent redundant syncs.
    /// - Parameter container: ModelContainer for actor isolation
    func performFullSyncSafely(container: ModelContainer) {
        // Simulator safeguard - block sync completely
        #if targetEnvironment(simulator)
        AppLogger.sync.warning("⚠️ Sync blocked on simulator to prevent data conflicts")
        self.syncStatus = .simulatorBlocked
        return
        #else
        
        // Throttle foreground syncs to prevent redundant work
        if let lastSync = UserDefaults.standard.object(forKey: lastForegroundSyncKey) as? Date {
            let elapsed = Date().timeIntervalSince(lastSync)
            if elapsed < minimumSyncInterval {
                AppLogger.sync.debug("Sync throttled: Last sync \(Int(elapsed))s ago (min: \(Int(self.minimumSyncInterval))s)")
                return
            }
        }
        
        // Mark throttle timestamp
        UserDefaults.standard.set(Date(), forKey: lastForegroundSyncKey)
        
        // Cache container for conflict resolution usage if needed
        cachedContainer = container
        
        // Fire and forget - runs in detached task
        Task.detached(priority: .utility) { [weak self] in
            await self?.executeSync(container: container)
        }
        #endif
    }
    
    /// Force sync bypassing throttle (for manual "Sync Now" button)
    /// - Parameter container: ModelContainer for actor isolation
    func forceSync(container: ModelContainer) {
        UserDefaults.standard.set(Date.distantPast, forKey: lastForegroundSyncKey)
        performFullSyncSafely(container: container)
    }
    
    /// Internal sync execution with full error handling and Actor Isolation
    func executeSync(container: ModelContainer) async {
        // Check if user is signed in
        let isSignedIn = await MainActor.run { self.isSignedInCheck() }
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
        await MainActor.run {
            self.syncStatus = .syncing("Checking devices...")
            self.syncStartTime = Date()
        }
        
        // Initialize Actor
        let actor = SyncDataActor(container: container)
        
        do {
            // Phase 0: Check device registry for conflicts
            let conflictInfo = try await checkForDeviceConflicts(actor: actor)
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
            await proceedWithSync(actor: actor)
            
        } catch {
            // Catch ALL errors - never propagate
            let errorMessage = error.localizedDescription
            let errorCode = (error as? DriveError)?.code ?? "UNKNOWN"
            AppLogger.sync.error("❌ Sync failed: \(errorMessage)")
            
            // Record failure in history
            let duration = await MainActor.run { Date().timeIntervalSince(self.syncStartTime ?? Date()) }
            await MainActor.run {
                SyncHistoryManager.shared.recordSync(
                    action: .fullSync,
                    status: .failed,
                    duration: duration,
                    errorCode: errorCode,
                    errorMessage: errorMessage
                )
                self.syncStatus = .failed("Sync failed")
            }
        }
    }
    
    /// Checks device registry and returns conflict info if another device has synced
    private func checkForDeviceConflicts(actor: SyncDataActor) async throws -> SyncConflictInfo? {
        let registry = try await driveService.fetchDeviceRegistry()
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
            // Count local records via Actor
            let localCount = await actor.countLocalRecords()
            
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
    func handleConflictResolution(_ resolution: ConflictResolution) {
        pendingConflict = nil
        
        guard let container = cachedContainer else {
            AppLogger.sync.error("❌ No cached container for conflict resolution")
            syncStatus = .failed("Internal error: No container")
            return
        }
        
        switch resolution {
        case .useThisDevice:
            // Upload local data, register this device
            AppLogger.sync.info("📱 User chose to use this device's data")
            syncStatus = .syncing("Uploading local data...")
            
            Task.detached(priority: .utility) { [weak self] in
                let actor = SyncDataActor(container: container)
                await self?.uploadLocalDataAndRegister(actor: actor)
            }
            
        case .useCloudData:
            // Download cloud data, register this device
            AppLogger.sync.info("☁️ User chose to use cloud data")
            syncStatus = .syncing("Downloading cloud data...")
            
            Task.detached(priority: .utility) { [weak self] in
                let actor = SyncDataActor(container: container)
                await self?.downloadCloudDataAndRegister(actor: actor)
            }
            
        case .cancel:
            AppLogger.sync.info("❌ User cancelled sync")
            syncStatus = .idle
        }
    }
    
    /// Uploads local data and registers this device
    private func uploadLocalDataAndRegister(actor: SyncDataActor) async {
        do {
            // Queue all local records for upload
            let queuedCount = await actor.queueAllRecords()
            AppLogger.sync.info("📦 Queued \(queuedCount) records for upload")
            
            // Upload
            await MainActor.run { self.syncStatus = .syncing("Uploading \(queuedCount) records...") }
            let uploadedCount = try await driveService.uploadPendingRecords(actor: actor)
            
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
    private func downloadCloudDataAndRegister(actor: SyncDataActor) async {
        do {
            // Download from cloud
            await MainActor.run { self.syncStatus = .syncing("Downloading from cloud...") }
            let downloadedCount = try await driveService.reconcileFromRemote(actor: actor)
            
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
        var registry = try await driveService.fetchDeviceRegistry()
        let identity = await MainActor.run { DeviceIdentity.shared }
        registry.registerDevice(identity: identity)
        try await driveService.updateDeviceRegistry(registry)
        AppLogger.sync.info("✅ Device registered: \(identity.shortDescription)")
    }
    
    /// Proceeds with normal sync after conflict check passes
    private func proceedWithSync(actor: SyncDataActor) async {
        do {
            // Phase 1: Pull remote changes
            await MainActor.run { self.syncStatus = .syncing("Downloading...") }
            let downloadedCount = try await driveService.reconcileFromRemote(actor: actor)
            
            // Phase 2: Push local changes
            await MainActor.run { self.syncStatus = .syncing("Uploading...") }
            let uploadedCount = try await driveService.uploadPendingRecords(actor: actor)
            
            // Update device registry
            try await registerCurrentDevice()
            
            await finishSync(downloaded: downloadedCount, uploaded: uploadedCount)
            
        } catch {
            let errorMessage = error.localizedDescription
            let errorCode = (error as? DriveError)?.code ?? "UNKNOWN"
            AppLogger.sync.error("❌ Sync failed: \(errorMessage)")
            
            // Record failure in history
            let duration = await MainActor.run { Date().timeIntervalSince(self.syncStartTime ?? Date()) }
            await MainActor.run {
                SyncHistoryManager.shared.recordSync(
                    action: .fullSync,
                    status: .failed,
                    duration: duration,
                    errorCode: errorCode,
                    errorMessage: errorMessage
                )
                self.syncStatus = .failed("Sync failed")
            }
        }
    }
    
    /// Finishes sync with success status
    private func finishSync(downloaded: Int, uploaded: Int) async {
        let now = Date()
        let duration = await MainActor.run { Date().timeIntervalSince(self.syncStartTime ?? Date()) }
        
        await MainActor.run {
            self.lastSyncDate = now
            UserDefaults.standard.set(now, forKey: self.lastSyncKey)
            
            // Record success in history
            SyncHistoryManager.shared.recordSync(
                action: .fullSync,
                status: .success,
                uploaded: uploaded,
                downloaded: downloaded,
                duration: duration
            )
            
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
    func performFullSync(container: ModelContainer) async {
        performFullSyncSafely(container: container)
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

