//
//  TemplateListViewModel.swift
//  Protocol
//
//  Created on 2026-01-08.
//

import SwiftUI
import SwiftData
import Combine

enum TemplateSortOption: String, CaseIterable {
    case manual = "Manual"
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
}

@MainActor
final class TemplateListViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private var modelContext: ModelContext?
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Published State
    
    // Navigation
    @Published var navigationPath = NavigationPath()
    
    // List Config
    @Published var sortOption: TemplateSortOption = .manual
    @Published var isSelecting = false
    @Published var selectedMoleculeIDs: Set<PersistentIdentifier> = []
    
    // Action Sheets & Alerts
    @Published var showingBulkActionSheet = false
    @Published var showingGenerateSheet = false
    @Published var showingDeleteConfirmation = false
    @Published var showingCustomDurationAlert = false
    @Published var customDurationInput: String = ""
    @Published var showingSingleDeleteAlert = false
    @Published var templateToDelete: MoleculeTemplate?
    
    // Bulk Backfill
    @Published var showingBulkBackfillSheet = false
    @Published var backfillStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @Published var backfillEndDate = Date()
    @Published var showingBulkBackfillSuccess = false
    @Published var bulkBackfillMessage = ""
    
    // Creation Flow
    @Published var newlyCreatedTemplate: MoleculeTemplate?
    @Published var highlightedMoleculeID: PersistentIdentifier?
    @Published var showingCreationOptions = false
    @Published var showingCreationSuccess = false
    @Published var creationCustomDays: String = ""
    @Published var showingCreationCustomAlert = false
    
    // Undo State
    @Published var showingUndoToast = false
    @Published var undoTemplateId: UUID?
    @Published var undoTemplateName: String = ""
    @Published var undoBulkTemplateIds: [UUID] = []
    
    // MARK: - Computed Logic
    
    func sortedTemplates(from templates: [MoleculeTemplate]) -> [MoleculeTemplate] {
        let pinned = templates.filter { $0.isPinned }.sorted { $0.sortOrder < $1.sortOrder }
        let unpinned = templates.filter { !$0.isPinned }
        
        let sortedUnpinned: [MoleculeTemplate]
        switch sortOption {
        case .manual:
            sortedUnpinned = unpinned.sorted { $0.sortOrder < $1.sortOrder }
        case .nameAsc:
            sortedUnpinned = unpinned.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            sortedUnpinned = unpinned.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
        
        return pinned + sortedUnpinned
    }
    
    var creationSuccessMessage: String {
        if let template = newlyCreatedTemplate {
            let instanceCount = template.instances.count
            if instanceCount > 0 {
                return "'\(template.title)' is ready. \(instanceCount) instances generated."
            } else {
                return "'\(template.title)' is ready."
            }
        }
        return "Your molecule is ready."
    }
    
    // MARK: - Actions
    
    func toggleSelection(for template: MoleculeTemplate) {
        if selectedMoleculeIDs.contains(template.persistentModelID) {
            selectedMoleculeIDs.remove(template.persistentModelID)
        } else {
            selectedMoleculeIDs.insert(template.persistentModelID)
        }
    }
    
    func togglePin(for template: MoleculeTemplate, currentPinnedCount: Int) {
        guard let context = modelContext else { return }
        
        if template.isPinned {
            template.isPinned = false
        } else if currentPinnedCount < 3 {
            template.isPinned = true
            template.sortOrder = currentPinnedCount
        }
        try? context.save()
    }
    
    func addTemplate(allTemplates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        
        let maxOrder = allTemplates.map(\.sortOrder).max() ?? 0
        let newTemplate = MoleculeTemplate(
            title: "New Molecule",
            baseTime: Date(),
            recurrenceFreq: .daily
        )
        newTemplate.sortOrder = maxOrder + 1
        context.insert(newTemplate)
        try? context.save()
        
        Task {
            await AuditLogger.shared.logCreate(
                entityType: .moleculeTemplate,
                entityId: newTemplate.id.uuidString,
                entityName: newTemplate.title
            )
        }
        
        newlyCreatedTemplate = newTemplate
        navigationPath.append(newTemplate)
    }
    
    func deleteTemplate(_ template: MoleculeTemplate) {
        guard let context = modelContext else { return }
        
        let entityId = template.id.uuidString
        let entityName = template.title
        
        Task {
            await AuditLogger.shared.logDelete(
                entityType: .moleculeTemplate,
                entityId: entityId,
                entityName: entityName
            )
        }
        
        context.delete(template)
        try? context.save()
        AppLogger.data.info("DELETE COMPLETED")
    }
    
    func duplicateMolecule(_ sourceMolecule: MoleculeTemplate, allTemplates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        
        withAnimation {
            let maxOrder = allTemplates.map(\.sortOrder).max() ?? 0
            
            let newMolecule = MoleculeTemplate(
                title: "\(sourceMolecule.title) (Copy)",
                baseTime: sourceMolecule.baseTime,
                recurrenceFreq: sourceMolecule.recurrenceFreq
            )
            
            newMolecule.sortOrder = maxOrder + 1
            newMolecule.isAllDay = sourceMolecule.isAllDay
            newMolecule.recurrenceDays = sourceMolecule.recurrenceDays
            newMolecule.endRuleType = sourceMolecule.endRuleType
            newMolecule.endRuleDate = sourceMolecule.endRuleDate
            newMolecule.endRuleCount = sourceMolecule.endRuleCount
            newMolecule.notes = sourceMolecule.notes
            newMolecule.compound = sourceMolecule.compound
            newMolecule.iconSymbol = sourceMolecule.iconSymbol
            newMolecule.iconFrame = sourceMolecule.iconFrame
            newMolecule.themeColorHex = sourceMolecule.themeColorHex
            
            context.insert(newMolecule)
            
            for (index, sourceAtom) in sourceMolecule.atomTemplates.sorted(by: { $0.order < $1.order }).enumerated() {
                let newAtom = AtomTemplate(
                    id: UUID(),
                    title: sourceAtom.title,
                    inputType: sourceAtom.inputType,
                    targetValue: sourceAtom.targetValue,
                    unit: sourceAtom.unit,
                    order: index,
                    targetSets: sourceAtom.targetSets,
                    targetReps: sourceAtom.targetReps,
                    defaultRestTime: sourceAtom.defaultRestTime,
                    videoURL: sourceAtom.videoURL,
                    parentMoleculeTemplate: newMolecule
                )
                context.insert(newAtom)
            }
            
            try? context.save()
            
            Task {
                await AuditLogger.shared.logCreate(
                    entityType: .moleculeTemplate,
                    entityId: newMolecule.id.uuidString,
                    entityName: newMolecule.title,
                    additionalInfo: "Duplicated from '\(sourceMolecule.title)'"
                )
            }
            
            highlightedMoleculeID = newMolecule.persistentModelID
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    if self.highlightedMoleculeID == newMolecule.persistentModelID {
                        self.highlightedMoleculeID = nil
                    }
                }
            }
        }
    }
    
    func generateForNewTemplate(days: Int) {
        guard let context = modelContext, let template = newlyCreatedTemplate else { return }
        
        highlightedMoleculeID = template.persistentModelID
        
        let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let newInstances = template.generateInstances(until: targetDate, in: context)
        for instance in newInstances {
            context.insert(instance)
        }
        try? context.save()
        
        Task {
            await NotificationManager.shared.scheduleNotifications(for: newInstances)
        }
        
        navigationPath = NavigationPath()
        showingCreationOptions = false
        showingCreationSuccess = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.highlightedMoleculeID = nil
            }
        }
    }
    
    func onSkipCreation() {
        if let template = newlyCreatedTemplate {
            highlightedMoleculeID = template.persistentModelID
        }
        showingCreationOptions = false
        newlyCreatedTemplate = nil
        navigationPath = NavigationPath()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.highlightedMoleculeID = nil
            }
        }
    }
    
    // MARK: - Bulk Actions
    
    func bulkGenerate(days: Int, templates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        
        let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        var allNewInstances: [MoleculeInstance] = []
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                let newInstances = template.generateInstances(until: targetDate, in: context)
                for instance in newInstances {
                    context.insert(instance)
                }
                allNewInstances.append(contentsOf: newInstances)
            }
        }
        
        try? context.save()
        
        Task {
            await NotificationManager.shared.scheduleNotifications(for: allNewInstances)
        }
        
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    func bulkDelete(templates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        
        var archivedTemplates: [(id: UUID, idString: String, name: String)] = []
        
        withAnimation {
            for id in selectedMoleculeIDs {
                if let template = templates.first(where: { $0.persistentModelID == id }) {
                    archivedTemplates.append((template.id, template.id.uuidString, template.title))
                    template.isArchived = true
                }
            }
            try? context.save()
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
        
        Task {
            for item in archivedTemplates {
                await AuditLogger.shared.logDelete(
                    entityType: .moleculeTemplate,
                    entityId: item.idString,
                    entityName: item.name
                )
            }
        }
        
        undoBulkTemplateIds = archivedTemplates.map { $0.id }
        undoTemplateName = "\(archivedTemplates.count) molecules"
        withAnimation {
            showingUndoToast = true
        }
    }
    
    func bulkPin(templates: [MoleculeTemplate], pinnedCount: Int) {
        guard let context = modelContext else { return }
        var currentPinned = pinnedCount
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }), !template.isPinned {
                if currentPinned < 3 {
                    template.isPinned = true
                    template.sortOrder = currentPinned
                    currentPinned += 1
                }
            }
        }
        try? context.save()
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    func bulkUnpin(templates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                template.isPinned = false
            }
        }
        try? context.save()
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    func bulkBackfill(templates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        let service = MoleculeService(modelContext: context)
        
        var count = 0
        
        for id in selectedMoleculeIDs {
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                service.backfillInstances(for: template, from: backfillStartDate, to: backfillEndDate)
                count += 1
            }
        }
        
        bulkBackfillMessage = "Backfilled \(count) molecules."
        showingBulkBackfillSuccess = true
        showingBulkBackfillSheet = false
        
        withAnimation {
            selectedMoleculeIDs.removeAll()
            isSelecting = false
        }
    }
    
    // MARK: - Undo Actions
    
    func undoArchive() {
        guard let context = modelContext, let templateId = undoTemplateId else { return }
        
        let descriptor = FetchDescriptor<MoleculeTemplate>(
            predicate: #Predicate<MoleculeTemplate> { $0.id == templateId }
        )
        
        if let template = try? context.fetch(descriptor).first {
            template.isArchived = false
            try? context.save()
            
            Task {
                await AuditLogger.shared.logUpdate(
                    entityType: .moleculeTemplate,
                    entityId: template.id.uuidString,
                    entityName: template.title,
                    changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                    additionalInfo: "Unarchived via Undo"
                )
            }
        }
        
        withAnimation {
            showingUndoToast = false
            undoTemplateId = nil
        }
    }
    
    func undoBulkArchive() {
        guard let context = modelContext, !undoBulkTemplateIds.isEmpty else { return }
        
        for templateId in undoBulkTemplateIds {
            let descriptor = FetchDescriptor<MoleculeTemplate>(
                predicate: #Predicate<MoleculeTemplate> { $0.id == templateId }
            )
            
            if let template = try? context.fetch(descriptor).first {
                template.isArchived = false
                
                Task {
                    await AuditLogger.shared.logUpdate(
                        entityType: .moleculeTemplate,
                        entityId: template.id.uuidString,
                        entityName: template.title,
                        changes: [AuditLogger.fieldChange("isArchived", old: "true", new: "false")].compactMap { $0 },
                        additionalInfo: "Unarchived via Bulk Undo"
                    )
                }
            }
        }
        
        try? context.save()
        
        withAnimation {
            showingUndoToast = false
            undoBulkTemplateIds.removeAll()
            undoTemplateId = nil
        }
    }
    
    // MARK: - List Reordering
    
    func movePinnedTemplates(from source: IndexSet, to destination: Int, in sortedTemplates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        var pinned = sortedTemplates.filter { $0.isPinned }
        pinned.move(fromOffsets: source, toOffset: destination)
        for (index, template) in pinned.enumerated() {
            template.sortOrder = index
        }
        try? context.save()
    }
    
    func moveUnpinnedTemplates(from source: IndexSet, to destination: Int, in sortedTemplates: [MoleculeTemplate]) {
        guard let context = modelContext else { return }
        var unpinned = sortedTemplates.filter { !$0.isPinned }
        unpinned.move(fromOffsets: source, toOffset: destination)
        let pinnedCount = sortedTemplates.filter { $0.isPinned }.count
        for (index, template) in unpinned.enumerated() {
            template.sortOrder = pinnedCount + index
        }
        try? context.save()
    }
}
