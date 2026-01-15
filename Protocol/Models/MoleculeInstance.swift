//
//  MoleculeInstance.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData
import WidgetKit

/// The "Actual Event" model - represents a specific occurrence of a molecule.
/// Each MoleculeInstance belongs to a MoleculeTemplate (or can be standalone).
@Model
final class MoleculeInstance {
    // MARK: - Properties
    
    /// Unique identifier for the instance
    var id: UUID
    
    /// The specific date and time for this occurrence
    var scheduledDate: Date
    
    /// Whether this instance has been completed
    var isCompleted: Bool
    
    /// Completion timestamp (when the user marked it complete)
    var completedAt: Date?
    
    /// True if the user modified this specific instance away from the template's standard rule
    /// When true, changes to the parent template won't affect this instance
    var isException: Bool
    
    /// Override title (used when isException is true)
    /// If nil, uses the parent template's title
    var exceptionTitle: String?
    
    /// Override time (used when isException is true)
    /// If nil, uses the parent template's baseTime
    var exceptionTime: Date?
    
    /// Creation timestamp
    var createdAt: Date
    
    /// Last modification timestamp
    var updatedAt: Date
    
    /// Notes specific to this instance
    var notes: String?
    
    /// The original scheduled date before any drag-and-drop modifications
    /// Used for "Planned vs. Actual" analysis
    var originalScheduledDate: Date?
    
    /// Alert offsets in minutes before scheduled time
    /// Copied from parent template when instance is created
    /// Can be overridden per-instance
    var alertOffsets: [Int] = [15]
    
    /// Whether this is an all-day event (no specific time)
    /// Inherited from parent template when created
    var isAllDay: Bool = false
    
    /// Whether this instance has been soft-deleted (archived)
    var isArchived: Bool = false
    
    // MARK: - Orphan Properties
    
    /// Whether this instance is an orphan (detached from a retired parent)
    var isOrphan: Bool = false
    
    /// The title of the original parent molecule (preserved for context)
    var originalMoleculeTitle: String?
    
    // MARK: - Relationships
    
    /// Many-to-One relationship with MoleculeTemplate
    /// Can be nil for standalone (non-recurring) instances
    var parentTemplate: MoleculeTemplate?
    
    /// One-to-Many relationship with AtomInstance
    /// When an instance is deleted, all its atom instances are also deleted
    @Relationship(deleteRule: .cascade, inverse: \AtomInstance.parentMoleculeInstance)
    var atomInstances: [AtomInstance] = []
    
    // MARK: - Initialization
    
    /// Creates a new MoleculeInstance
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - scheduledDate: The date and time for this occurrence
    ///   - isCompleted: Whether the instance is completed (default: false)
    ///   - isException: Whether this instance differs from its template (default: false)
    ///   - parentTemplate: The parent template, if this is a recurring instance
    init(
        id: UUID = UUID(),
        scheduledDate: Date,
        isCompleted: Bool = false,
        isException: Bool = false,
        exceptionTitle: String? = nil,
        exceptionTime: Date? = nil,
        parentTemplate: MoleculeTemplate? = nil,
        alertOffsets: [Int]? = nil,
        isAllDay: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String? = nil,
        isOrphan: Bool = false,
        originalMoleculeTitle: String? = nil
    ) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.isCompleted = isCompleted
        self.isException = isException
        self.exceptionTitle = exceptionTitle
        self.exceptionTime = exceptionTime
        self.parentTemplate = parentTemplate
        // Use provided offsets, or inherit from template, or default to [15]
        self.alertOffsets = alertOffsets ?? parentTemplate?.alertOffsets ?? [15]
        // Inherit isAllDay from template if not explicitly set
        self.isAllDay = isAllDay || (parentTemplate?.isAllDay ?? false)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.isOrphan = isOrphan
        self.originalMoleculeTitle = originalMoleculeTitle
        self.originalScheduledDate = nil
    }
    
    // MARK: - Computed Properties
    
    /// The display title for this instance
    /// Returns the exception title if set, otherwise the parent template's title
    var displayTitle: String {
        if let exceptionTitle = exceptionTitle, isException {
            return exceptionTitle
        }
        return parentTemplate?.title ?? "Untitled"
    }
    
    /// The effective scheduled time for display
    /// Returns the exception time if set, otherwise the scheduled date
    var effectiveTime: Date {
        if let exceptionTime = exceptionTime, isException {
            return exceptionTime
        }
        return scheduledDate
    }
    
    /// Whether this instance is part of a recurring series
    var isPartOfSeries: Bool {
        parentTemplate != nil
    }
    
    /// Whether this instance is in the past
    var isPast: Bool {
        scheduledDate < Date()
    }
    
    /// Whether this instance is today
    var isToday: Bool {
        Calendar.current.isDateInToday(scheduledDate)
    }
    
    /// Whether this instance is upcoming (in the future)
    var isUpcoming: Bool {
        scheduledDate > Date()
    }
    
    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        if isToday {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInTomorrow(scheduledDate) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: scheduledDate)
    }
    
    /// Short time string for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: effectiveTime)
    }
    
    /// Completion progress (0.0 to 1.0) based on atom instances
    /// Returns 1.0 if completed or has no atoms, 0.0 if no atoms completed
    var progress: Double {
        if isCompleted { return 1.0 }
        guard !atomInstances.isEmpty else { return isCompleted ? 1.0 : 0.0 }
        
        let completedCount = atomInstances.filter { $0.isCompleted }.count
        return Double(completedCount) / Double(atomInstances.count)
    }
    
    // MARK: - Actions
    
    /// Marks this instance as completed and cascades to all atom children
    func markComplete() {
        isCompleted = true
        completedAt = Date()
        updatedAt = Date()
        
        // Cascade to all atom children
        for atom in atomInstances {
            if !atom.isCompleted {
                atom.isCompleted = true
                atom.completedAt = Date()
            }
        }
        
        // Queue for sync (not available in Widget extension)
        #if !WIDGET_EXTENSION
        SyncQueueManager.shared.addToQueue(self)
        #endif
        
        // NOTE: Caller should cancel notifications via NotificationManager.shared.cancelNotifications(for: self)
        
        // Refresh widget
        refreshWidget()
    }
    
    /// Marks this instance as incomplete and cascades to all atom children
    func markIncomplete() {
        isCompleted = false
        completedAt = nil
        updatedAt = Date()
        
        // Cascade to all atom children
        for atom in atomInstances {
            atom.isCompleted = false
            atom.completedAt = nil
        }
        
        // Queue for sync (not available in Widget extension)
        #if !WIDGET_EXTENSION
        SyncQueueManager.shared.addToQueue(self)
        #endif
        
        // Refresh widget
        refreshWidget()
    }
    
    /// Toggles the completion status
    func toggleComplete() {
        if isCompleted {
            markIncomplete()
        } else {
            markComplete()
        }
    }
    
    /// Checks if all atoms are complete and auto-completes this instance if so
    func checkAtomCompletionAndSync() {
        guard !atomInstances.isEmpty else { return }
        
        let allAtomsComplete = atomInstances.allSatisfy { $0.isCompleted }
        var changed = false
        
        if allAtomsComplete && !isCompleted {
            // All atoms done, auto-complete parent
            isCompleted = true
            completedAt = Date()
            updatedAt = Date()
            changed = true
            refreshWidget()
        } else if !allAtomsComplete && isCompleted {
            // An atom was unchecked, mark parent incomplete
            isCompleted = false
            completedAt = nil
            updatedAt = Date()
            changed = true
            refreshWidget()
        }
        
        if changed {
            #if !WIDGET_EXTENSION
            SyncQueueManager.shared.addToQueue(self)
            #endif
        }
    }
    
    /// Refreshes the widget to show updated completion status
    private func refreshWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    /// Converts this instance to an exception with custom values
    /// - Parameters:
    ///   - title: Custom title for this instance
    ///   - time: Custom time for this instance
    func makeException(title: String? = nil, time: Date? = nil) {
        isException = true
        
        if let title = title {
            exceptionTitle = title
        }
        
        if let time = time {
            exceptionTime = time
            // Update scheduled date to use the new time while keeping the same date
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            if let newDate = calendar.date(from: components) {
                scheduledDate = newDate
            }
        }
        
        updatedAt = Date()
        #if !WIDGET_EXTENSION
        SyncQueueManager.shared.addToQueue(self)
        #endif
    }
    
    /// Reverts this instance back to following the template
    func revertToTemplate() {
        guard let template = parentTemplate else { return }
        
        isException = false
        exceptionTitle = nil
        exceptionTime = nil
        
        // Reset scheduled date to use template's base time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: template.baseTime)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        
        if let newDate = calendar.date(from: components) {
            scheduledDate = newDate
        }
        
        updatedAt = Date()
        #if !WIDGET_EXTENSION
        SyncQueueManager.shared.addToQueue(self)
        #endif
    }
    
    /// Snoozes this instance by a specified number of minutes
    /// - Parameter minutes: Number of minutes to snooze
    func snooze(by minutes: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .minute, value: minutes, to: scheduledDate) {
            scheduledDate = newDate
            
            // Mark as exception since we've modified it
            if parentTemplate != nil {
                isException = true
                exceptionTime = newDate
            }
            
            updatedAt = Date()
            #if !WIDGET_EXTENSION
            SyncQueueManager.shared.addToQueue(self)
            #endif
        }
    }
}

// MARK: - Hashable Conformance
extension MoleculeInstance: Hashable {
    static func == (lhs: MoleculeInstance, rhs: MoleculeInstance) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Comparable Conformance (for sorting)
extension MoleculeInstance: Comparable {
    static func < (lhs: MoleculeInstance, rhs: MoleculeInstance) -> Bool {
        lhs.scheduledDate < rhs.scheduledDate
    }
}

// MARK: - SyncableRecord Conformance
extension MoleculeInstance: SyncableRecord {
    var syncID: UUID { id }
    
    var lastModified: Date {
        get { updatedAt }
        set { updatedAt = newValue }
    }
    
    var isDeleted: Bool {
        get { isArchived }
        set { isArchived = newValue }
    }
    
    func toSyncJSON() -> Data? {
        let formatter = Self.syncDateFormatter
        
        var json: [String: Any] = [
            "syncID": syncID.uuidString,
            "lastModified": formatter.string(from: lastModified),
            "isDeleted": isDeleted,
            "scheduledDate": formatter.string(from: scheduledDate),
            "isCompleted": isCompleted,
            "isException": isException,
            "isAllDay": isAllDay,
            "alertOffsets": alertOffsets,
            "createdAt": formatter.string(from: createdAt)
        ]
        
        // Optional properties
        if let completedAt = completedAt {
            json["completedAt"] = formatter.string(from: completedAt)
        }
        if let exceptionTitle = exceptionTitle {
            json["exceptionTitle"] = exceptionTitle
        }
        if let exceptionTime = exceptionTime {
            json["exceptionTime"] = formatter.string(from: exceptionTime)
        }
        if let notes = notes {
            json["notes"] = notes
        }
        if let originalScheduledDate = originalScheduledDate {
            json["originalScheduledDate"] = formatter.string(from: originalScheduledDate)
        }
        
        // Parent relationship UUID
        if let parentID = parentTemplate?.id {
            json["moleculeTemplateID"] = parentID.uuidString
        }
        
        // Child relationship UUIDs
        json["atomInstanceIDs"] = atomInstances.map { $0.id.uuidString }
        
        return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
