//
//  NotificationManager.swift
//  Protocol
//
//  Created on 2025-12-29.
//  Updated: Smart Notification System with Multi-Alerts
//

import Foundation
import UserNotifications
import SwiftData

/// Manages local notifications for MoleculeInstances
/// Supports multiple alerts per instance and 3-day rolling window to stay under iOS 64-notification limit
@MainActor
final class NotificationManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    // MARK: - Constants
    
    static let completeActionIdentifier = "COMPLETE_ACTION"
    static let snoozeActionIdentifier = "SNOOZE_ACTION"
    static let categoryIdentifier = "HABIT_ACTION"
    
    /// Maximum days to schedule notifications in advance (3-day rolling window)
    static let rollingWindowDays = 3
    
    /// Maximum notifications iOS allows
    static let maxNotifications = 64
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await checkAuthorization()
            setupNotificationCategories()
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = granted ? .authorized : .denied
            }
            
            return granted
        } catch {
            AppLogger.notifications.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        let completeAction = UNNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "✓ Complete",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze 15m",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    // MARK: - Identifier Helpers
    
    /// Creates notification identifier: "{instanceID}-alert-{offset}"
    private func makeIdentifier(for instanceId: UUID, offset: Int) -> String {
        return "\(instanceId.uuidString)-alert-\(offset)"
    }
    
    /// Extracts instance ID prefix from identifier for batch cancellation
    private func identifierPrefix(for instanceId: UUID) -> String {
        return "\(instanceId.uuidString)-alert-"
    }
    
    // MARK: - Schedule Single Instance (Multi-Alert)
    
    /// Schedules ALL notifications for a single instance based on its alertOffsets
    /// First cancels any existing notifications for this instance
    func scheduleNotifications(for instance: MoleculeInstance) async {
        // Always cancel existing first
        await cancelNotifications(for: instance)
        
        guard isAuthorized else {
            AppLogger.notifications.warning("Notifications not authorized")
            return
        }
        
        // Don't schedule for completed instances
        guard !instance.isCompleted else { return }
        
        let center = UNUserNotificationCenter.current()
        
        for offset in instance.alertOffsets {
            // Calculate trigger time: scheduledDate - offset minutes
            let triggerDate = instance.scheduledDate.addingTimeInterval(TimeInterval(-offset * 60))
            
            // Skip if trigger time is in the past
            guard triggerDate > Date() else { continue }
            
            let content = UNMutableNotificationContent()
            content.title = instance.displayTitle
            content.body = createNotificationBody(for: instance, offset: offset)
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [
                "instanceId": instance.id.uuidString,
                "offset": offset
            ]
            
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: triggerDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let identifier = makeIdentifier(for: instance.id, offset: offset)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            
            do {
                try await center.add(request)
                AppLogger.notifications.debug("Scheduled notification: \(instance.displayTitle) at \(triggerDate) (offset: \(offset)m)")
            } catch {
                AppLogger.notifications.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Schedules notifications for multiple instances
    func scheduleNotifications(for instances: [MoleculeInstance]) async {
        for instance in instances {
            await scheduleNotifications(for: instance)
        }
    }
    
    // MARK: - Cancel Notifications
    
    /// Cancels ALL notifications for a specific instance (all offsets)
    func cancelNotifications(for instance: MoleculeInstance) async {
        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let prefix = identifierPrefix(for: instance.id)
        
        let identifiersToRemove = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix(prefix) }
        
        if !identifiersToRemove.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            AppLogger.notifications.debug("Cancelled \(identifiersToRemove.count) notifications for instance \(instance.displayTitle)")
        }
    }
    
    /// Legacy sync version for compatibility
    func cancelNotification(for instance: MoleculeInstance) {
        Task {
            await cancelNotifications(for: instance)
        }
    }
    
    /// Cancels all notifications for a template's instances
    func cancelNotifications(for template: MoleculeTemplate) {
        let identifiers = template.instances.flatMap { instance in
            instance.alertOffsets.map { offset in
                makeIdentifier(for: instance.id, offset: offset)
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    /// Cancels all pending notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        AppLogger.notifications.info("Cancelled ALL pending notifications")
    }
    
    // MARK: - Rolling Window Scheduler (3-Day Batch)
    
    /// Refreshes notifications for the next 3 days only (solves 64-notification limit)
    /// Call this on app launch, backgroundAppRefresh, and after any instance changes
    func refreshUpcomingNotifications(context: ModelContext) async {
        guard isAuthorized else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let windowEnd = calendar.date(byAdding: .day, value: Self.rollingWindowDays, to: now)!
        
        // Fetch incomplete instances within the 3-day window
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate<MoleculeInstance> {
                !$0.isCompleted &&
                $0.scheduledDate > now &&
                $0.scheduledDate <= windowEnd
            },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        
        guard let instances = try? context.fetch(descriptor) else {
            AppLogger.notifications.warning("Failed to fetch instances for notification refresh")
            return
        }
        
        // Clear all existing notifications
        cancelAllNotifications()
        
        // Schedule only for the 3-day window
        for instance in instances {
            await scheduleNotifications(for: instance)
        }
        
        let count = await getPendingNotificationCount()
        AppLogger.notifications.info("Refreshed notifications: \(count) scheduled (\(instances.count) instances in next \(Self.rollingWindowDays) days)")
    }
    
    // MARK: - Snooze
    
    /// Reschedules notifications for a snoozed instance (+15 min)
    func snoozeNotification(for instance: MoleculeInstance, minutes: Int = 15) async {
        await cancelNotifications(for: instance)
        instance.snooze(by: minutes)
        await scheduleNotifications(for: instance)
    }
    
    // MARK: - Helper Methods
    
    private func createNotificationBody(for instance: MoleculeInstance, offset: Int) -> String {
        let timeString: String
        switch offset {
        case 0:
            timeString = "It's time!"
        case 1...59:
            timeString = "Starting in \(offset) min"
        case 60:
            timeString = "Starting in 1 hour"
        case 61...1439:
            let hours = offset / 60
            timeString = "Starting in \(hours) hour\(hours > 1 ? "s" : "")"
        default:
            let days = offset / 1440
            timeString = "Starting in \(days) day\(days > 1 ? "s" : "")"
        }
        
        let atomCount = instance.atomInstances.count
        if atomCount > 0 {
            return "\(timeString) • \(atomCount) tasks"
        }
        return timeString
    }
    
    // MARK: - Debug/Stats
    
    func getPendingNotificationCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.count
    }
    
    func getPendingNotificationIds() async -> [String] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.map { $0.identifier }
    }
    
    /// Debug: Print all pending notifications
    func debugPrintPendingNotifications() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        AppLogger.notifications.debug("Pending Notifications (\(requests.count)):")
        for request in requests.prefix(10) {
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                AppLogger.notifications.debug("  - \(request.identifier): \(trigger.nextTriggerDate() ?? Date())")
            }
        }
        if requests.count > 10 {
            AppLogger.notifications.debug("  ... and \(requests.count - 10) more")
        }
    }
}

// MARK: - Notification Handler

/// Handles notification responses (Complete/Snooze actions)
class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    
    var onComplete: ((UUID) -> Void)?
    var onSnooze: ((UUID) -> Void)?
    var onTap: ((UUID) -> Void)?
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        guard let idString = userInfo["instanceId"] as? String,
              let instanceId = UUID(uuidString: idString) else {
            completionHandler()
            return
        }
        
        switch response.actionIdentifier {
        case NotificationManager.completeActionIdentifier:
            onComplete?(instanceId)
            
        case NotificationManager.snoozeActionIdentifier:
            onSnooze?(instanceId)
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped notification - deep link to instance
            onTap?(instanceId)
            
        default:
            break
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
