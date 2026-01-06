//
//  MoleculeService.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData

/// Service class for managing Molecule CRUD operations and the "Series vs. Instance" logic.
@MainActor
final class MoleculeService: ObservableObject {
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Template Operations
    
    /// Creates a new template and its initial instances
    /// - Parameter template: The template to create
    /// - Returns: The generated instances
    @discardableResult
    func createTemplate(_ template: MoleculeTemplate) -> [MoleculeInstance] {
        modelContext.insert(template)
        
        // Generate initial instances (30 days by default)
        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let instances = template.generateInstances(until: targetDate, in: modelContext)
        for instance in instances {
            modelContext.insert(instance)
        }
        
        try? modelContext.save()
        
        // Audit log
        Task {
            await AuditLogger.shared.logCreate(
                entityType: .moleculeTemplate,
                entityId: template.id.uuidString,
                entityName: template.title,
                additionalInfo: "Generated \(instances.count) instances"
            )
        }
        
        // Schedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: instances)
        }
        
        return instances
    }
    
    /// Backfills instances for a template for a past date range
    /// - Parameters:
    ///   - template: The template to backfill
    ///   - startDate: The start date (inclusive)
    ///   - endDate: The end date (inclusive)
    /// - Returns: The newly generated instances
    @discardableResult
    func backfillInstances(for template: MoleculeTemplate, from startDate: Date, to endDate: Date) -> [MoleculeInstance] {
        // Generate instances for the specified range
        let newInstances = template.generateInstances(from: startDate, until: endDate, in: modelContext)
        
        for instance in newInstances {
            modelContext.insert(instance)
        }
        
        try? modelContext.save()
        
        // Audit log
        Task {
            await AuditLogger.shared.logCreate(
                entityType: .moleculeInstance,
                entityId: template.id.uuidString, // Using template ID as reference
                entityName: "Backfill: \(template.title)",
                additionalInfo: "Backfilled \(newInstances.count) instances from \(startDate.formatted(date: .numeric, time: .omitted))"
            )
        }
        
        return newInstances
    }
    
    /// Deletes a template and all its instances
    /// Deletes a template (Soft Delete/Archive)
    /// Marks as archived and removes future instances. Preserves history.
    /// Deletes a template (Soft Delete/Archive)
    /// Marks as archived and removes future instances. Preserves history.
    /// Uses Atomic Transaction for durability.
    func deleteTemplate(_ template: MoleculeTemplate) async throws {
        let templateName = template.title
        let templateId = template.id.uuidString
        
        print("🔴 DELETION STARTED for \(templateName)")
        
        // 0. Pre-calculate values (Read-only, no UI side effects)
        let now = Date()
        let instancesToDelete = template.instances.filter { $0.scheduledDate > now }
        let deleteCount = instancesToDelete.count
        
        // 1. Insert Audit Log FIRST (Before reactive changes)
        // This transaction step is prepared but not committed.
        let logEntry = PersistentAuditLog(
            operation: .delete,
            entityType: .moleculeTemplate,
            entityId: templateId,
            entityName: templateName,
            callSite: "MoleculeService.swift",
            additionalInfo: "Soft deleted (Archived). Removed \(deleteCount) future instances."
        )
        modelContext.insert(logEntry)
        print("🟡 AUDIT LOG PREPARED (Template not archived yet)")
        
        // 2. Archive Template & Delete Instances (Trigger SwiftUI Updates)
        // Note: SwiftUI reacts immediately to this part!
        template.isArchived = true
        
        for instance in instancesToDelete {
            NotificationManager.shared.cancelNotification(for: instance)
            modelContext.delete(instance)
        }
        
        // Cancel notifications
        NotificationManager.shared.cancelNotifications(for: template)
        
        print("🟠 ARCHIVE FLAG SET (SwiftUI Reaction Window Open)")
        
        // 3. Atomic Save (Commit Log + Archive together)
        do {
            try modelContext.save()
            print("🟢 SAVE COMPLETED - Persistence Secured")
            print("🔵 AUDIT LOG COMMITTED")
        } catch {
            print("❌ SAVE FAILED: \(error)")
            AppLogger.data.error("Failed to archive template: \(error)")
            modelContext.rollback() // Revert UI state on failure
            throw error
        }
    }
    
    // MARK: - Instance Operations
    
    /// Deletes only a specific instance (not the whole series)
    func deleteInstanceOnly(_ instance: MoleculeInstance) {
        // Mark as exception so it won't be regenerated
        if instance.parentTemplate != nil {
            instance.isException = true
            instance.exceptionTitle = "[Deleted]"
        }
        
        modelContext.delete(instance)
        try? modelContext.save()
    }
    
    /// Marks an instance as complete
    func markComplete(_ instance: MoleculeInstance) {
        let wasCompleted = instance.isCompleted
        instance.markComplete()
        try? modelContext.save()
        
        // Audit log
        Task {
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeInstance,
                entityId: instance.id.uuidString,
                entityName: instance.displayTitle,
                changes: [AuditLogger.fieldChange("isCompleted", old: "\(wasCompleted)", new: "true")].compactMap { $0 }
            )
        }
    }
    
    /// Marks an instance as incomplete
    func markIncomplete(_ instance: MoleculeInstance) {
        let wasCompleted = instance.isCompleted
        instance.markIncomplete()
        try? modelContext.save()
        
        // Audit log
        Task {
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeInstance,
                entityId: instance.id.uuidString,
                entityName: instance.displayTitle,
                changes: [AuditLogger.fieldChange("isCompleted", old: "\(wasCompleted)", new: "false")].compactMap { $0 }
            )
        }
    }
    
    /// Snoozes an instance by specified minutes
    func snooze(_ instance: MoleculeInstance, byMinutes minutes: Int) {
        let oldDate = instance.scheduledDate
        instance.snooze(by: minutes)
        try? modelContext.save()
        
        // Audit log
        Task {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeInstance,
                entityId: instance.id.uuidString,
                entityName: instance.displayTitle,
                changes: [
                    AuditLogger.fieldChange("scheduledDate", old: formatter.string(from: oldDate), new: formatter.string(from: instance.scheduledDate))
                ].compactMap { $0 },
                additionalInfo: "Snoozed by \(minutes)m"
            )
        }
    }
    
    // MARK: - Edit Operations (The "Apple Calendar" Standard)
    
    /// Represents changes to be applied to an instance or template
    struct InstanceChanges {
        var title: String?
        var scheduledTime: Date?
        var notes: String?
    }
    
    /// Updates only this specific instance (marks as exception)
    /// - Parameters:
    ///   - instance: The instance to update
    ///   - changes: The changes to apply
    func updateThisEventOnly(_ instance: MoleculeInstance, with changes: InstanceChanges) {
        // Capture old state for audit
        let oldTitle = instance.exceptionTitle
        let oldTime = instance.scheduledDate
        let oldNotes = instance.notes
        
        // Mark as exception
        instance.isException = true
        
        // Apply title change
        if let newTitle = changes.title {
            instance.exceptionTitle = newTitle
        }
        
        // Apply time change
        if let newTime = changes.scheduledTime {
            instance.makeException(time: newTime)
        }
        
        // Apply notes
        if let notes = changes.notes {
            instance.notes = notes
        }
        
        instance.updatedAt = Date()
        try? modelContext.save()
        
        // Audit log
        Task {
            var fieldChanges: [FieldChange] = []
            
            // Title Check
            if let newTitle = changes.title {
                if let change = AuditLogger.fieldChange("title", old: oldTitle ?? instance.parentTemplate?.title, new: newTitle) {
                    fieldChanges.append(change)
                }
            }
            
            // Time Check
            if let newTime = changes.scheduledTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let oldTimeStr = formatter.string(from: oldTime)
                let newTimeStr = formatter.string(from: newTime)
                if let change = AuditLogger.fieldChange("scheduledDate", old: oldTimeStr, new: newTimeStr) {
                    fieldChanges.append(change)
                }
            }
            
            // Notes Check
            if let newNotes = changes.notes {
                if let change = AuditLogger.fieldChange("notes", old: oldNotes, new: newNotes) {
                    fieldChanges.append(change)
                }
            }
            
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeInstance,
                entityId: instance.id.uuidString,
                entityName: instance.displayTitle,
                changes: fieldChanges,
                additionalInfo: "Edit Scope: This Event Only"
            )
        }
    }
    
    /// Updates the template and regenerates all future instances
    /// - Parameters:
    ///   - instance: The instance that triggered the edit
    ///   - changes: The changes to apply to the template
    func updateAllFutureEvents(from instance: MoleculeInstance, with changes: InstanceChanges) {
        guard let template = instance.parentTemplate else {
            // No template, just update this instance
            updateThisEventOnly(instance, with: changes)
            return
        }
        
        // Capture old state
        let oldTitle = template.title
        let oldTime = template.baseTime
        
        // Apply changes to template
        if let newTitle = changes.title {
            template.title = newTitle
        }
        
        if let newTime = changes.scheduledTime {
            template.baseTime = newTime
        }
        
        template.updatedAt = Date()
        
        // Regenerate future instances from the current instance's date
        regenerateFutureInstances(for: template, startingFrom: instance.scheduledDate)
        
        try? modelContext.save()
        
        // Audit log
        Task {
            var fieldChanges: [FieldChange] = []
            
            // Title Check
            if let newTitle = changes.title {
                if let change = AuditLogger.fieldChange("title", old: oldTitle, new: newTitle) {
                    fieldChanges.append(change)
                }
            }
            
            // Time Check
            if let newTime = changes.scheduledTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let oldTimeStr = formatter.string(from: oldTime)
                let newTimeStr = formatter.string(from: newTime)
                if let change = AuditLogger.fieldChange("baseTime", old: oldTimeStr, new: newTimeStr) {
                    fieldChanges.append(change)
                }
            }
            
            await AuditLogger.shared.logUpdate(
                entityType: .moleculeTemplate,
                entityId: template.id.uuidString,
                entityName: template.title,
                changes: fieldChanges,
                additionalInfo: "Edit Scope: All Future Events"
            )
        }
    }
    
    /// Regenerates future instances for a template
    /// - Parameters:
    ///   - template: The template to regenerate instances for
    ///   - startDate: The date to start regenerating from
    func regenerateFutureInstances(for template: MoleculeTemplate, startingFrom startDate: Date) {
        // Ensure we start from today at minimum to avoid regenerating past instances
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let effectiveStartDate = max(calendar.startOfDay(for: startDate), today)
        
        // Remove future uncompleted instances that are not exceptions
        let instancesToRemove = template.instances.filter { instance in
            !instance.isCompleted &&
            !instance.isException &&
            instance.scheduledDate >= effectiveStartDate
        }
        
        for instance in instancesToRemove {
            modelContext.delete(instance)
        }
        
        // Generate new instances (30 days by default)
        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: effectiveStartDate)!
        let newInstances = template.generateInstances(until: targetDate, in: modelContext)
        for instance in newInstances {
            modelContext.insert(instance)
        }
        
        try? modelContext.save()
        
        // Schedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: newInstances)
        }
    }
    
    // MARK: - Deletion Operations
    
    /// Represents deletion scope choices
    enum DeletionScope {
        case thisEventOnly
        case allFutureEvents
        case allEvents
    }
    
    /// Deletes instance(s) based on scope
    func deleteEvents(_ instance: MoleculeInstance, scope: DeletionScope) {
        guard let template = instance.parentTemplate else {
            // No template, just delete the instance
            modelContext.delete(instance)
            try? modelContext.save()
            return
        }
        
        switch scope {
        case .thisEventOnly:
            NotificationManager.shared.cancelNotification(for: instance)
            
            // Capture info
            let id = instance.id.uuidString
            let name = instance.displayTitle
            
            modelContext.delete(instance)
            
            // Audit log
            Task {
                await AuditLogger.shared.logDelete(
                    entityType: .moleculeInstance,
                    entityId: id,
                    entityName: name,
                    additionalInfo: "Deleted via 'This Event Only' scope"
                )
            }
            
        case .allFutureEvents:
            let futureInstances = template.instances.filter { $0.scheduledDate >= instance.scheduledDate }
            for inst in futureInstances {
                NotificationManager.shared.cancelNotification(for: inst)
                modelContext.delete(inst)
            }
            // Update recurrence end rule to stop at this instance's date
            template.endRuleType = .onDate
            template.endRuleDate = instance.scheduledDate
            
        case .allEvents:
            // Delete the template (cascade will delete all instances)
            NotificationManager.shared.cancelNotifications(for: template)
            
            // Capture info before delete
            let templateId = template.id.uuidString
            let templateName = template.title
            
            modelContext.delete(template)
            
            // Audit log
            Task {
                await AuditLogger.shared.logDelete(
                    entityType: .moleculeTemplate,
                    entityId: templateId,
                    entityName: templateName,
                    additionalInfo: "Deleted via 'All Events' scope"
                )
            }
        }
        
        try? modelContext.save()
    }

    
    // MARK: - Smart Logic
    
    /// Checks for progressive overload and updates the template if the user exceeded the target
    func checkForProgression(atomInstance: AtomInstance) {
        // Only applies to 'Value' type inputs (e.g. weights, reps)
        guard atomInstance.inputType == .value,
              let current = atomInstance.currentValue,
              let target = atomInstance.targetValue,
              current > target, // User beat the target
              let sourceId = atomInstance.sourceTemplateId else { return }
        
        // Find the source template
        let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == sourceId })
        if let atomTemplate = try? modelContext.fetch(descriptor).first {
            // Update the baseline for future instances
            let oldTarget = atomTemplate.targetValue
            atomTemplate.targetValue = current
            try? modelContext.save()
            AppLogger.data.info("💪 Progressive Overload: Updated baseline to \(current) \(atomTemplate.unit ?? "")")
            
            // Audit log
            Task {
                await AuditLogger.shared.logUpdate(
                    entityType: .atomTemplate,
                    entityId: atomTemplate.id.uuidString,
                    entityName: atomTemplate.title,
                    changes: [
                        AuditLogger.fieldChange("targetValue", old: "\(oldTarget ?? 0)", new: "\(current)")
                    ].compactMap { $0 },
                    additionalInfo: "Progressive Overload Triggered"
                )
            }
        }
    }
}

// MARK: - Edit Scope Enum
/// Represents the scope of an edit operation
enum EditScope: String, CaseIterable, Identifiable {
    case thisEventOnly = "This Event Only"
    case allFutureEvents = "All Future Events"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .thisEventOnly:
            return "Changes will only apply to this occurrence"
        case .allFutureEvents:
            return "Changes will apply to this and all future occurrences"
        }
    }
}
