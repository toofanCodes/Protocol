//
//  MoleculeTemplate.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData
import SwiftUI

/// The "Rule" model - defines the repeating pattern for molecules.
/// A MoleculeTemplate generates one or more MoleculeInstances based on its recurrence settings.
@Model
final class MoleculeTemplate {
    // MARK: - Properties
    
    /// Unique identifier for the template
    var id: UUID
    
    /// Display title for the molecule
    var title: String
    
    /// Base time for scheduling (time component is key for notifications)
    var baseTime: Date
    
    /// How often this molecule repeats
    var recurrenceFreq: RecurrenceFrequency
    
    /// For custom recurrence: specific days of the week (0=Sunday, 1=Monday, etc.)
    /// Only used when recurrenceFreq == .custom
    var recurrenceDays: [Int]
    
    /// End rule type (never, onDate, afterOccurrences)
    var endRuleType: RecurrenceEndRuleType
    
    /// End date (used when endRuleType == .onDate)
    var endRuleDate: Date?
    
    /// End count (used when endRuleType == .afterOccurrences)
    var endRuleCount: Int?
    
    /// Creation timestamp
    var createdAt: Date
    
    /// Last modification timestamp
    var updatedAt: Date
    
    /// Optional notes/description for the molecule (e.g., "Zone 3 Heart Rate")
    var notes: String?
    
    /// Category/Compound categorization (e.g. "Health", "Workout")
    var compound: String?
    
    /// Alert offsets in minutes before scheduled time
    /// Default: [15] (15 minutes before)
    /// Example: [0, 15, 60] = at time, 15 min before, 1 hour before
    var alertOffsets: [Int] = [15]
    
    /// Whether this molecule is an all-day event (no specific time)
    /// All-day molecules appear in a separate dock above the timeline
    var isAllDay: Bool = false
    
    /// Whether this template is archived (soft deleted)
    /// Archived templates are hidden from the list but preserved for history
    var isArchived: Bool = false
    
    // MARK: - Retirement Properties
    
    /// Status of the retirement process: nil (Active), "pending", or "retired"
    var retirementStatus: String?
    
    /// Date when the user initiated retirement
    var retirementDate: Date?
    
    /// The reason for retirement (e.g., "Changed routine", "Goal reached")
    var retirementReason: String?
    
    /// Deadline for undoing the retirement (Initial action date + 24 hours)
    var undoDeadline: Date?
    
    /// Action to take for future instances: "deleteAll", "keepAsOrphans", "deleteAfterDate"
    var futureAction: String?
    
    /// Specific cutoff date if futureAction is "deleteAfterDate"
    var deleteAfterDate: Date?
    
    // MARK: - Icon Properties
    
    /// Custom icon symbol (1-2 chars/emoji). Nil = use first letter of title
    var iconSymbol: String?
    
    /// Icon frame shape (stored as raw value for SwiftData compatibility)
    var iconFrameRaw: String = "circle"
    
    /// Computed accessor for iconFrame enum (not persisted)
    @Transient var iconFrame: IconFrameStyle {
        get { IconFrameStyle(rawValue: iconFrameRaw) ?? .circle }
        set { iconFrameRaw = newValue.rawValue }
    }
    
    /// Theme color stored as hex string (e.g., "#007AFF")
    var themeColorHex: String = "#007AFF"
    
    /// Computed accessor for theme color (not persisted)
    @Transient var themeColor: Color {
        get { Color(hex: themeColorHex) }
        set { themeColorHex = newValue.toHex() }
    }
    
    // MARK: - Organization Properties
    
    /// Whether this molecule is pinned to the top of the list (max 3 pinned)
    var isPinned: Bool = false
    
    /// Manual sort order (lower = higher in list)
    var sortOrder: Int = 0
    
    // MARK: - Relationships
    
    /// One-to-Many relationship with MoleculeInstance
    /// When a template is deleted, all instances are deleted to prevent orphans
    /// NOTE: Users should rely on Backups to preserve history if needed
    @Relationship(deleteRule: .cascade, inverse: \MoleculeInstance.parentTemplate)
    var instances: [MoleculeInstance] = []
    
    /// One-to-Many relationship with AtomTemplate
    /// When a template is deleted, all its atom templates are also deleted
    @Relationship(deleteRule: .cascade, inverse: \AtomTemplate.parentMoleculeTemplate)
    var atomTemplates: [AtomTemplate] = []
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        title: String,
        baseTime: Date,
        recurrenceFreq: RecurrenceFrequency = .daily,
        recurrenceDays: [Int] = [],
        endRuleType: RecurrenceEndRuleType = .never,
        endRuleDate: Date? = nil,
        endRuleCount: Int? = nil,
        notes: String? = nil,
        compound: String? = nil,
        alertOffsets: [Int] = [15],
        isAllDay: Bool = false,
        iconSymbol: String? = nil,
        iconFrame: IconFrameStyle = .circle,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        // Retirement params
        retirementStatus: String? = nil,
        retirementDate: Date? = nil,
        retirementReason: String? = nil,
        undoDeadline: Date? = nil,
        futureAction: String? = nil,
        deleteAfterDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.baseTime = baseTime
        self.recurrenceFreq = recurrenceFreq
        self.recurrenceDays = recurrenceDays
        self.endRuleType = endRuleType
        self.endRuleDate = endRuleDate
        self.endRuleCount = endRuleCount
        self.notes = notes
        self.compound = compound
        self.alertOffsets = alertOffsets
        self.isAllDay = isAllDay
        self.iconSymbol = iconSymbol
        self.iconFrameRaw = iconFrame.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        
        self.retirementStatus = retirementStatus
        self.retirementDate = retirementDate
        self.retirementReason = retirementReason
        self.undoDeadline = undoDeadline
        self.futureAction = futureAction
        self.deleteAfterDate = deleteAfterDate
    }
    
    // MARK: - Computed Properties
    
    /// Human-readable description of the recurrence pattern
    var recurrenceDescription: String {
        var description = recurrenceFreq.displayName
        
        if recurrenceFreq == .custom && !recurrenceDays.isEmpty {
            description = "Every \(recurrenceDays.daysDescription)"
        }
        
        switch endRuleType {
        case .never:
            break // No suffix needed
        case .onDate:
            if let date = endRuleDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                description += " until \(formatter.string(from: date))"
            }
        case .afterOccurrences:
            if let count = endRuleCount {
                description += " (\(count)x)"
            }
        }
        
        return description
    }
    
    /// Returns the time component formatted for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: baseTime)
    }
    
    /// Checks if this template has any future uncompleted instances
    var hasPendingInstances: Bool {
        let now = Date()
        return instances.contains { !$0.isCompleted && $0.scheduledDate > now }
    }
    
    /// Returns all future instances (not yet past their scheduled date)
    var futureInstances: [MoleculeInstance] {
        let now = Date()
        return instances
            .filter { $0.scheduledDate > now }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }
    
    /// Returns the next scheduled instance, if any
    var nextInstance: MoleculeInstance? {
        futureInstances.first
    }
    
    // MARK: - Validation
    
    /// Checks if a template with the given title already exists
    /// - Parameters:
    ///   - title: The title to check
    ///   - context: The ModelContext to query
    ///   - excludingId: Optional ID to exclude (for editing existing template)
    /// - Returns: true if a template with this title exists
    static func titleExists(_ title: String, in context: ModelContext, excludingId: UUID? = nil) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptor = FetchDescriptor<MoleculeTemplate>()
        
        do {
            let allTemplates = try context.fetch(descriptor)
            return allTemplates.contains { template in
                let existingTitle = template.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let isSameTitle = existingTitle == normalizedTitle
                let isNotExcluded = excludingId == nil || template.id != excludingId
                return isSameTitle && isNotExcluded
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Instance Generation
    
    /// Generates instances for this template from a start date until a target date
    /// Also clones all AtomTemplates into AtomInstances for each generated instance
    /// - Parameters:
    ///   - start: The start date to generate instances from (default: Today)
    ///   - targetDate: The end date to generate instances until (inclusive)
    ///   - context: ModelContext for idempotency check (prevents duplicates)
    /// - Returns: Array of NEW MoleculeInstance objects (skips existing dates)
    /// Generates instances for this template from a start date until a target date
    /// Also clones all AtomTemplates into AtomInstances for each generated instance
    /// - Parameters:
    ///   - start: The start date to generate instances from (default: Today)
    ///   - targetDate: The end date to generate instances until (inclusive)
    ///   - context: ModelContext for idempotency check (prevents duplicates)
    /// - Returns: Array of NEW MoleculeInstance objects (skips existing dates)
    func generateInstances(from start: Date = Date(), until targetDate: Date, in context: ModelContext) -> [MoleculeInstance] {
        var generatedInstances: [MoleculeInstance] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: start)
        let endDate = calendar.startOfDay(for: targetDate)
        
        // Optimize: Batch fetch existing dates to avoid N+1 queries
        let existingDates = fetchExistingDates(from: currentDate, to: endDate, in: context)
        
        // Sort atom templates by order for consistent cloning
        let sortedAtomTemplates = atomTemplates.sorted { $0.order < $1.order }
        
        // Get the time components from baseTime
        let timeComponents = calendar.dateComponents([.hour, .minute], from: baseTime)
        
        while currentDate <= endDate {
            // Check end rule
            switch endRuleType {
            case .never:
                break
            case .onDate:
                if let ruleEndDate = endRuleDate, currentDate > ruleEndDate {
                    return generatedInstances
                }
            case .afterOccurrences:
                if let maxCount = endRuleCount, instances.count + generatedInstances.count >= maxCount {
                    return generatedInstances
                }
            }
            
            // Check if this date matches the recurrence pattern
            if shouldGenerateInstance(for: currentDate, calendar: calendar) {
                // Idempotency check: Use pre-fetched Set
                guard !existingDates.contains(currentDate) else {
                    // Already exists, skip to next day
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
                    continue
                }
                
                // Combine current date with base time
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                
                if let scheduledDate = calendar.date(from: dateComponents) {
                    let instance = MoleculeInstance(
                        scheduledDate: scheduledDate,
                        parentTemplate: self,
                        isAllDay: self.isAllDay
                    )
                    
                    // Clone all AtomTemplates into AtomInstances
                    for atomTemplate in sortedAtomTemplates {
                        let atomInstance = atomTemplate.createInstance(for: instance)
                        instance.atomInstances.append(atomInstance)
                    }
                    
                    generatedInstances.append(instance)
                }
            }
            
            // Move to next day
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        return generatedInstances
    }
    
    /// Batch fetches existing instance dates for a range
    private func fetchExistingDates(from start: Date, to end: Date, in context: ModelContext) -> Set<Date> {
        let templateId = self.id
        // Add 1 day to end for exclusive upper bound if needed, but <= covers it.
        // Actually, let's be safe and go to end of day.
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        
        // We only need the date component (start of day) for comparison
        // But instances are stored with exact times.
        // However, our logic compares `startOfDay` dates.
        // Wait, `instanceExists` logic was checking:
        // instance.scheduledDate >= startOfDay && instance.scheduledDate < endOfDay
        
        let descriptor = FetchDescriptor<MoleculeInstance>(
            predicate: #Predicate { instance in
                instance.parentTemplate?.id == templateId &&
                instance.scheduledDate >= start &&
                instance.scheduledDate < endOfDay
            }
        )
        // We only need the dates.
        // SwiftData doesn't support `.propertiesToFetch` nicely in FetchDescriptor Generic init easily until iOS 18?
        // But we can just fetch and map.
        
        do {
            let instances = try context.fetch(descriptor)
            // Normalize to start of day for comparison
            return Set(instances.map { calendar.startOfDay(for: $0.scheduledDate) })
        } catch {
            print("Failed to batch fetch existing dates: \(error)")
            // Fallback: Return empty set so we might double create? 
            // Better to match old behavior: check in-memory relationship?
            // If fetch fails, we probably have bigger issues. 
            // Let's use the in-memory `instances` array as fallback source of truth.
            return Set(self.instances.map { calendar.startOfDay(for: $0.scheduledDate) })
        }
    }
    
    /// Legacy method for backwards compatibility - generates a specific count of instances
    /// DEPRECATED: Use generateInstances(until:in:) instead
    func generateInstances(from startDate: Date = Date(), count: Int = 30) -> [MoleculeInstance] {
        var generatedInstances: [MoleculeInstance] = []
        let calendar = Calendar.current
        var currentDate = startDate
        var generatedCount = 0
        
        let sortedAtomTemplates = atomTemplates.sorted { $0.order < $1.order }
        let timeComponents = calendar.dateComponents([.hour, .minute], from: baseTime)
        
        while generatedCount < count {
            switch endRuleType {
            case .never:
                break
            case .onDate:
                if let endDate = endRuleDate, currentDate > endDate {
                    return generatedInstances
                }
            case .afterOccurrences:
                if let maxCount = endRuleCount, generatedCount >= maxCount {
                    return generatedInstances
                }
            }
            
            if shouldGenerateInstance(for: currentDate, calendar: calendar) {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                
                if let scheduledDate = calendar.date(from: dateComponents) {
                    let instance = MoleculeInstance(
                        scheduledDate: scheduledDate,
                        parentTemplate: self,
                        isAllDay: self.isAllDay
                    )
                    
                    for atomTemplate in sortedAtomTemplates {
                        let atomInstance = atomTemplate.createInstance(for: instance)
                        instance.atomInstances.append(atomInstance)
                    }
                    
                    generatedInstances.append(instance)
                    generatedCount += 1
                }
            }
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
            
            if calendar.dateComponents([.day], from: startDate, to: currentDate).day ?? 0 > 365 {
                break
            }
        }
        
        return generatedInstances
    }
    
    /// Checks if an instance should be generated for a specific date
    private func shouldGenerateInstance(for date: Date, calendar: Calendar) -> Bool {
        switch recurrenceFreq {
        case .daily:
            return true
            
        case .weekly:
            // Check if it's the same day of week as baseTime
            let baseDayOfWeek = calendar.component(.weekday, from: baseTime) - 1 // Convert to 0-indexed
            let currentDayOfWeek = calendar.component(.weekday, from: date) - 1
            return baseDayOfWeek == currentDayOfWeek
            
        case .monthly:
            // Check if it's the same day of month as baseTime
            let baseDayOfMonth = calendar.component(.day, from: baseTime)
            let currentDayOfMonth = calendar.component(.day, from: date)
            return baseDayOfMonth == currentDayOfMonth
            
        case .custom:
            // Check if current day is in the selected days
            let currentDayOfWeek = calendar.component(.weekday, from: date) - 1 // Convert to 0-indexed
            return recurrenceDays.contains(currentDayOfWeek)
        }
    }
    
    // MARK: - Instance Management
    
    /// Regenerates future instances from a specific date
    /// Removes old future uncompleted instances and creates new ones
    /// - Parameter fromDate: The date from which to regenerate
    func regenerateFutureInstances(from fromDate: Date = Date()) {
        // Remove future uncompleted instances that are not exceptions
        let instancesToRemove = instances.filter { instance in
            !instance.isCompleted &&
            !instance.isException &&
            instance.scheduledDate >= fromDate
        }
        
        for instance in instancesToRemove {
            if let index = instances.firstIndex(where: { $0.id == instance.id }) {
                instances.remove(at: index)
            }
        }
        
        // Generate new instances
        let newInstances = generateInstances(from: fromDate)
        instances.append(contentsOf: newInstances)
        
        // Update timestamp
        updatedAt = Date()
    }
}

// MARK: - Hashable Conformance
extension MoleculeTemplate: Hashable {
    static func == (lhs: MoleculeTemplate, rhs: MoleculeTemplate) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SyncableRecord Conformance
extension MoleculeTemplate: SyncableRecord {
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
            "title": title,
            "baseTime": formatter.string(from: baseTime),
            "recurrenceFreq": recurrenceFreq.rawValue,
            "recurrenceDays": recurrenceDays,
            "endRuleType": endRuleType.rawValue,
            "alertOffsets": alertOffsets,
            "isAllDay": isAllDay,
            "isPinned": isPinned,
            "sortOrder": sortOrder,
            "createdAt": formatter.string(from: createdAt),
            "iconFrameRaw": iconFrameRaw,
            "themeColorHex": themeColorHex
        ]
        
        // Optional properties
        if let endRuleDate = endRuleDate {
            json["endRuleDate"] = formatter.string(from: endRuleDate)
        }
        if let endRuleCount = endRuleCount {
            json["endRuleCount"] = endRuleCount
        }
        if let notes = notes {
            json["notes"] = notes
        }
        if let compound = compound {
            json["compound"] = compound
        }
        if let iconSymbol = iconSymbol {
            json["iconSymbol"] = iconSymbol
        }
        
        // Relationship UUIDs (not nested objects)
        json["atomTemplateIDs"] = atomTemplates.map { $0.id.uuidString }
        json["instanceIDs"] = instances.map { $0.id.uuidString }
        
        return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
