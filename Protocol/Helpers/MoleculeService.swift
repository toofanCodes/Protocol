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
        
        // Schedule notifications
        Task {
            await NotificationManager.shared.scheduleNotifications(for: instances)
        }
        
        return instances
    }
    
    /// Deletes a template and all its instances
    func deleteTemplate(_ template: MoleculeTemplate) {
        // Cancel notifications
        NotificationManager.shared.cancelNotifications(for: template)
        
        modelContext.delete(template)
        try? modelContext.save()
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
        instance.markComplete()
        try? modelContext.save()
    }
    
    /// Marks an instance as incomplete
    func markIncomplete(_ instance: MoleculeInstance) {
        instance.markIncomplete()
        try? modelContext.save()
    }
    
    /// Snoozes an instance by specified minutes
    func snooze(_ instance: MoleculeInstance, byMinutes minutes: Int) {
        instance.snooze(by: minutes)
        try? modelContext.save()
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
    }
    
    /// Regenerates future instances for a template
    /// - Parameters:
    ///   - template: The template to regenerate instances for
    ///   - startDate: The date to start regenerating from
    func regenerateFutureInstances(for template: MoleculeTemplate, startingFrom startDate: Date) {
        // Remove future uncompleted instances that are not exceptions
        let instancesToRemove = template.instances.filter { instance in
            !instance.isCompleted &&
            !instance.isException &&
            instance.scheduledDate >= startDate
        }
        
        for instance in instancesToRemove {
            modelContext.delete(instance)
        }
        
        // Generate new instances (30 days by default)
        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: startDate)!
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
            modelContext.delete(instance)
            
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
            modelContext.delete(template)
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
            atomTemplate.targetValue = current
            try? modelContext.save()
            print("💪 Progressive Overload: Updated baseline to \(current) \(atomTemplate.unit ?? "")")
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
