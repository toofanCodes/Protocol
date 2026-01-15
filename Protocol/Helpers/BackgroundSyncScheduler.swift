//
//  BackgroundSyncScheduler.swift
//  Protocol
//
//  Manages true background cloud sync via BGProcessingTask.
//  Schedules daily sync at user-configurable time (default: 3 AM).
//

import Foundation
import BackgroundTasks
import SwiftData

/// Background task manager for scheduled cloud sync
@MainActor
final class BackgroundSyncScheduler {
    
    // MARK: - Singleton
    
    static let shared = BackgroundSyncScheduler()
    
    // MARK: - Task Identifier
    
    /// Background task identifier - must match Info.plist entry
    static let taskIdentifier = "com.protocol.cloud.sync"
    
    // MARK: - Configuration Keys
    
    private let syncHourKey = "com.protocol.sync.scheduledHour"
    private let syncEnabledKey = "com.protocol.sync.backgroundEnabled"
    
    // MARK: - Public Configuration
    
    /// User-configurable sync hour (0-23), default 3 AM
    var scheduledHour: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: syncHourKey)
            return stored == 0 && !UserDefaults.standard.bool(forKey: "hasSetSyncHour") ? 3 : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: syncHourKey)
            UserDefaults.standard.set(true, forKey: "hasSetSyncHour")
        }
    }
    
    /// Whether background sync is enabled
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Default to enabled
        if !UserDefaults.standard.bool(forKey: "hasSetBackgroundSync") {
            UserDefaults.standard.set(true, forKey: syncEnabledKey)
            UserDefaults.standard.set(true, forKey: "hasSetBackgroundSync")
        }
    }
    
    // MARK: - Registration
    
    /// Register background task handler
    /// Call this in ProtocolApp.init()
    func registerTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let processingTask = task as? BGProcessingTask else {
                    AppLogger.background.error("Received unexpected task type for cloud sync")
                    task.setTaskCompleted(success: false)
                    return
                }
                await self.handleBackgroundSync(task: processingTask)
            }
        }
        AppLogger.background.info("Registered background sync task: \(Self.taskIdentifier)")
    }
    
    // MARK: - Scheduling
    
    /// Schedule the next background sync
    /// Call this when entering background or after config changes
    func scheduleNextSync() {
        guard isEnabled else {
            AppLogger.background.debug("Background sync disabled, not scheduling")
            return
        }
        
        // Cancel existing scheduled task
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false  // Allow on battery for daily habit apps
        
        // Calculate next occurrence of scheduledHour
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = scheduledHour
        components.minute = 0
        components.second = 0
        
        var nextSync = calendar.date(from: components)!
        
        // If the scheduled time today has passed, schedule for tomorrow
        if nextSync <= Date() {
            nextSync = calendar.date(byAdding: .day, value: 1, to: nextSync)!
        }
        
        request.earliestBeginDate = nextSync
        
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.background.info("Scheduled background sync for \(nextSync)")
        } catch {
            AppLogger.background.error("Failed to schedule background sync: \(error.localizedDescription)")
        }
    }
    
    /// Cancel scheduled background sync
    func cancelScheduledSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        AppLogger.background.info("Cancelled background sync")
    }
    
    // MARK: - Task Handling
    
    /// Handle the background sync task
    private func handleBackgroundSync(task: BGProcessingTask) async {
        let startTime = Date()
        
        // Schedule next sync first (before doing any work)
        scheduleNextSync()
        
        // Set expiration handler
        task.expirationHandler = {
            AppLogger.background.warning("Background sync expired before completion")
            SyncHistoryManager.shared.recordSync(
                action: .backgroundSync,
                status: .cancelled,
                duration: Date().timeIntervalSince(startTime),
                details: "Task expired"
            )
            task.setTaskCompleted(success: false)
        }
        
        // Check if user is signed in
        guard GoogleAuthManager.shared.isSignedIn else {
            AppLogger.background.debug("Background sync skipped: Not signed in")
            SyncHistoryManager.shared.recordSync(
                action: .backgroundSync,
                status: .skipped,
                details: "Not signed in"
            )
            task.setTaskCompleted(success: true)
            return
        }
        
        // Restore token for background context
        await GoogleAuthManager.shared.restorePreviousSignIn()
        
        // Perform sync
        let context = DataController.shared.container.mainContext
        
        do {
            // Download remote changes
            let downloaded = try await DriveService.shared.reconcileFromRemote(context: context)
            
            // Upload local changes
            let uploaded = try await DriveService.shared.uploadPendingRecords(context: context)
            
            // Record success
            SyncHistoryManager.shared.recordSync(
                action: .backgroundSync,
                status: .success,
                uploaded: uploaded,
                downloaded: downloaded,
                duration: Date().timeIntervalSince(startTime)
            )
            
            AppLogger.background.info("✅ Background sync complete: \(downloaded)↓ \(uploaded)↑")
            task.setTaskCompleted(success: true)
            
        } catch {
            let driveError = error as? DriveError
            SyncHistoryManager.shared.recordSync(
                action: .backgroundSync,
                status: .failed,
                duration: Date().timeIntervalSince(startTime),
                errorCode: driveError?.code ?? "UNKNOWN",
                errorMessage: error.localizedDescription
            )
            
            AppLogger.background.error("❌ Background sync failed: \(error.localizedDescription)")
            task.setTaskCompleted(success: false)
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Formats hour for display (e.g., "3 AM", "11 PM")
    func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
}
