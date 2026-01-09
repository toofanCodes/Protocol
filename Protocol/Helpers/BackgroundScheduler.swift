//
//  BackgroundScheduler.swift
//  Protocol
//
//  Manages background notification refresh using BGTaskScheduler
//  Ensures notifications stay within iOS 64-limit using rolling 3-day window
//

import Foundation
import BackgroundTasks
import SwiftData

/// Background task manager for refreshing notifications
@MainActor
final class BackgroundScheduler {
    
    // MARK: - Singleton
    
    static let shared = BackgroundScheduler()
    
    // MARK: - Task Identifier
    
    /// Background task identifier - must match Info.plist entry
    static let taskIdentifier = "com.protocol.notification.refresh"
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register background task handler
    /// Call this in ProtocolApp.init() or AppDelegate didFinishLaunching
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                if let refreshTask = task as? BGAppRefreshTask {
                    await self.handleAppRefresh(task: refreshTask)
                } else {
                    AppLogger.background.error("Received unexpected task type: \(type(of: task))")
                    task.setTaskCompleted(success: false)
                }
            }
        }
        AppLogger.background.info("Registered background task: \(Self.taskIdentifier)")
    }
    
    // MARK: - Task Scheduling
    
    /// Schedule the next background refresh
    /// Call this after any notification changes and on app entering background
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        
        // Schedule for early next morning (best time for daily habit apps)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day! += 1
        components.hour = 5  // 5 AM next day
        components.minute = 0
        
        if let nextRefresh = calendar.date(from: components) {
            request.earliestBeginDate = nextRefresh
        } else {
            // Fallback: 6 hours from now
            request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        }
        
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.background.info("Scheduled background refresh for \(request.earliestBeginDate!)")
        } catch {
            AppLogger.background.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Task Handling
    
    /// Handle the background refresh task
    private func handleAppRefresh(task: BGAppRefreshTask) async {
        // Schedule next refresh first
        scheduleAppRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Refresh notifications using shared container
        let context = DataController.shared.container.mainContext
        await NotificationManager.shared.refreshUpcomingNotifications(context: context)
        
        task.setTaskCompleted(success: true)
        AppLogger.background.info("Background notification refresh completed")
    }
    
    // MARK: - Manual Refresh
    
    /// Manually refresh notifications (call on app launch and scene activation)
    func refreshNotifications() async {
        let context = DataController.shared.container.mainContext
        await NotificationManager.shared.refreshUpcomingNotifications(context: context)
    }
}

// MARK: - Info.plist Requirement
/*
 Add to Info.plist under "Permitted background task scheduler identifiers" array:
 
 <key>BGTaskSchedulerPermittedIdentifiers</key>
 <array>
     <string>com.protocol.notification.refresh</string>
 </array>
 
 Also add:
 
 <key>UIBackgroundModes</key>
 <array>
     <string>fetch</string>
 </array>
*/
