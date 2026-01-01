//
//  MoleculeEditorViewModel.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import Foundation
import SwiftData
import Observation

/// ViewModel for MoleculeEditorView handling the "Series vs. Instance" decision tree
@Observable
@MainActor
final class MoleculeEditorViewModel {
    
    // MARK: - Published Properties
    
    var editedTitle: String = ""
    var editedTime: Date = Date()
    var editedNotes: String = ""
    var hasChanges: Bool = false
    
    // MARK: - Private Properties
    
    private let instance: MoleculeInstance
    private let modelContext: ModelContext
    private let service: MoleculeService
    
    private var originalTitle: String = ""
    private var originalTime: Date = Date()
    private var originalNotes: String = ""
    
    // MARK: - Computed Properties
    
    var isPartOfSeries: Bool {
        instance.parentTemplate != nil
    }
    
    var isCompleted: Bool {
        get { instance.isCompleted }
        set {
            if newValue {
                instance.markComplete()
            } else {
                instance.markIncomplete()
            }
            try? modelContext.save()
        }
    }
    
    var isException: Bool {
        instance.isException
    }
    
    var parentTemplate: MoleculeTemplate? {
        instance.parentTemplate
    }
    
    var scheduledDate: Date {
        instance.scheduledDate
    }
    
    // MARK: - Initialization
    
    init(instance: MoleculeInstance, modelContext: ModelContext) {
        self.instance = instance
        self.modelContext = modelContext
        self.service = MoleculeService(modelContext: modelContext)
        
        loadCurrentValues()
    }
    
    // MARK: - Public Methods
    
    /// Loads initial values from the instance
    func loadCurrentValues() {
        editedTitle = instance.displayTitle
        editedTime = instance.effectiveTime
        editedNotes = instance.notes ?? ""
        
        // Store originals for comparison
        originalTitle = editedTitle
        originalTime = editedTime
        originalNotes = editedNotes
        
        hasChanges = false
    }
    
    /// Checks if any values have changed
    func checkForChanges() {
        let titleChanged = editedTitle != originalTitle
        let timeChanged = !Calendar.current.isDate(editedTime, equalTo: originalTime, toGranularity: .minute)
        let notesChanged = editedNotes != originalNotes
        
        hasChanges = titleChanged || timeChanged || notesChanged
    }
    
    /// Saves changes for this event only (marks as exception)
    func saveThisEventOnly() {
        let changes = MoleculeService.InstanceChanges(
            title: editedTitle != originalTitle ? editedTitle : nil,
            scheduledTime: !Calendar.current.isDate(editedTime, equalTo: originalTime, toGranularity: .minute) ? editedTime : nil,
            notes: editedNotes != originalNotes ? editedNotes : nil
        )
        
        service.updateThisEventOnly(instance, with: changes)
    }
    
    /// Saves changes for all future events (updates template)
    func saveAllFutureEvents() {
        let changes = MoleculeService.InstanceChanges(
            title: editedTitle != originalTitle ? editedTitle : nil,
            scheduledTime: !Calendar.current.isDate(editedTime, equalTo: originalTime, toGranularity: .minute) ? editedTime : nil,
            notes: nil // Notes are instance-specific
        )
        
        service.updateAllFutureEvents(from: instance, with: changes)
    }
    
    /// Deletes this event only
    func deleteThisEventOnly() {
        service.deleteEvents(instance, scope: .thisEventOnly)
    }
    
    /// Deletes all future events
    func deleteAllFutureEvents() {
        service.deleteEvents(instance, scope: .allFutureEvents)
    }
    
    /// Deletes all events in the series
    func deleteAllEvents() {
        service.deleteEvents(instance, scope: .allEvents)
    }
    
    /// Deletes a standalone instance
    func deleteInstance() {
        modelContext.delete(instance)
        try? modelContext.save()
    }
    
    /// Snoozes the instance
    func snooze(byMinutes minutes: Int) {
        service.snooze(instance, byMinutes: minutes)
    }
}
