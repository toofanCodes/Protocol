//
//  RetirementService.swift
//  Protocol
//
//  Created on 2026-01-12.
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Background Helpers

@globalActor
actor BackgroundDataActor {
    static let shared = BackgroundDataActor()
}

final class BackgroundContextManager {
    private let container: ModelContainer
    
    init(container: ModelContainer) {
        self.container = container
    }
    
    @BackgroundDataActor
    func createBackgroundContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}

/// Service to manage the retirement lifecycle of molecules
@MainActor
final class RetirementService: ObservableObject {
    static let shared = RetirementService()
    
    // Progress Tracking
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    
    var container: ModelContainer?
    private var backgroundManager: BackgroundContextManager?
    private var processingTask: Task<Void, Never>?
    
    private init() {}
    
    func configure(with container: ModelContainer) {
        self.container = container
        self.backgroundManager = BackgroundContextManager(container: container)
    }
    
    // MARK: - Recovery
    
    func resumeInterruptedRetirements() async {
        guard let container = container else { return }
        let context = ModelContext(container)
        
        // Find templates stuck in "pending_processing"
        let descriptor = FetchDescriptor<MoleculeTemplate>(
            predicate: #Predicate<MoleculeTemplate> { $0.retirementStatus == "pending_processing" }
        )
        
        guard let stuckTemplates = try? context.fetch(descriptor) else { return }
        
        for template in stuckTemplates {
             let templateID = template.persistentModelID
             // Reconstruct config (best effort)
             // We stored retirementReason, futureAction, deleteAfterDate in initiateRetirement before processing.
             let config = RetirementConfiguration(
                 reason: template.retirementReason ?? "Unknown",
                 futureAction: template.futureAction ?? "deleteAll", // Default fallback
                 deleteAfterDate: template.deleteAfterDate
             )
             
             // Resume!
             Task {
                 await processRetirementInBackground(templateID: templateID, config: config, container: container)
             }
        }
    }
    
    // MARK: - Constants
    
    // 24-hour undo window
    private let undoWindow: TimeInterval = 24 * 60 * 60
    
    // Notification offset (12 hours after initiation, so 12 hours before deadline)
    private let notificationOffset: TimeInterval = 12 * 60 * 60
    
    // MARK: - Public API
    
    /// Initiates the retirement process for a molecule template
    /// Returns immediately after setting pending state, with background processing continuing.
    func initiateRetirement(
        template: MoleculeTemplate,
        reason: String,
        futureAction: String,
        deleteAfterDate: Date?,
        context: ModelContext
    ) {
        let now = Date()
        let deadline = now.addingTimeInterval(undoWindow)
        
        // 1. Optimistic UI update (Fast)
        template.retirementStatus = "pending_processing"
        template.retirementDate = now
        template.retirementReason = reason
        template.undoDeadline = deadline
        template.futureAction = futureAction
        template.deleteAfterDate = deleteAfterDate
        
        // Save initial state
        try? context.save()
        
        // Schedule notification
        scheduleRetirementNotification(for: template, deadline: deadline)
        
        // 2. Offload heavy lifting to background
        guard let container = container else {
             print("❌ RetirementService not configured with container!")
             return
        }
        
        let templateID = template.persistentModelID
        let config = RetirementConfiguration(
             reason: reason,
             futureAction: futureAction,
             deleteAfterDate: deleteAfterDate
        )
        
        processingTask = Task {
             await processRetirementInBackground(templateID: templateID, config: config, container: container)
        }
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        isProcessing = false
    }
    
    /// Reverts the retirement process
    func undoRetirement(template: MoleculeTemplate, context: ModelContext) {
        template.retirementStatus = nil // Back to active
        template.retirementDate = nil
        template.retirementReason = nil
        template.undoDeadline = nil
        template.futureAction = nil
        template.deleteAfterDate = nil
        template.isArchived = false
        
        // Undo instance actions
        for instance in template.instances {
            if instance.isOrphan {
                instance.isOrphan = false
                instance.originalMoleculeTitle = nil
            }
            if instance.isArchived {
                if instance.scheduledDate > Date() {
                    instance.isArchived = false
                }
            }
        }
        
        try? context.save()
        cancelRetirementNotification(for: template)
    }
    
    /// Finalizes the retirement (Permanent)
    func finalizeRetirement(template: MoleculeTemplate, context: ModelContext) {
        // ... (existing finalize logic, runs on main actor or could also be backgrounded if heavy, 
        // usually fewer templates finalize at once so maybe okay for now, or TODO optimization)
        guard template.retirementStatus == "pending" || template.retirementStatus == "pending_undo" || template.retirementStatus == "pending_processing" else { return }
        
        template.retirementStatus = "retired"
        template.isArchived = true
        
        // Execute final destructive actions if needed (most handled in background, but orphan disconnect is here?)
        // Spec: "Nullify relationship... at Finalization"
        // Wait, did we move orphan disconnect to background? 
        // The PRD says "keepAsOrphans: instance.orphanStatus = 'orphan'...". 
        // It does NOT say disconnect in Part 2.
        // But my previous analysis said "Disconnect at Finalization".
        // Let's stick to Disconnect at Finalization for safety/undo.
        
        if let action = template.futureAction {
            if action == "keepAsOrphans" {
                disconnectOrphans(template: template, context: context)
            } else if action == "deleteAll" {
                deleteFutureInstances(template: template, context: context)
            } else if action == "deleteAfterDate", let date = template.deleteAfterDate {
                deleteInstancesAfterDate(template: template, after: date, context: context)
            }
        }
        
        template.undoDeadline = nil
        try? context.save()
    }
    
    func checkPendingRetirements(context: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<MoleculeTemplate>(
            predicate: #Predicate<MoleculeTemplate> { template in
                // distinct status check
                (template.retirementStatus == "pending" || template.retirementStatus == "pending_undo") && template.undoDeadline != nil
            }
        )
        
        if let pendingTemplates = try? context.fetch(descriptor) {
            for template in pendingTemplates {
                if let deadline = template.undoDeadline, now > deadline {
                    finalizeRetirement(template: template, context: context)
                }
            }
        }
    }

    func duplicateMolecule(template: MoleculeTemplate, context: ModelContext) -> MoleculeTemplate {
        // (Existing implementation unchanged)
        let newTemplate = MoleculeTemplate(
            title: "\(template.title) Copy",
            baseTime: template.baseTime,
            recurrenceFreq: template.recurrenceFreq,
            recurrenceDays: template.recurrenceDays,
            endRuleType: template.endRuleType,
            endRuleDate: template.endRuleDate,
            endRuleCount: template.endRuleCount,
            notes: template.notes,
            compound: template.compound,
            alertOffsets: template.alertOffsets,
            isAllDay: template.isAllDay,
            iconSymbol: template.iconSymbol,
            createdAt: Date(),
            updatedAt: Date()
        )
        newTemplate.iconFrameRaw = template.iconFrameRaw
        newTemplate.themeColorHex = template.themeColorHex
        
        for atom in template.atomTemplates {
            let newAtom = AtomTemplate(
                title: atom.title,
                inputType: atom.inputType,
                targetValue: atom.targetValue,
                unit: atom.unit,
                order: atom.order,
                targetSets: atom.targetSets,
                targetReps: atom.targetReps,
                defaultRestTime: atom.defaultRestTime,
                videoURL: atom.videoURL,
                parentMoleculeTemplate: newTemplate,
                iconSymbol: atom.iconSymbol,
                iconFrame: atom.iconFrame
            )
            newTemplate.atomTemplates.append(newAtom)
        }
        
        context.insert(newTemplate)
        try? context.save()
        return newTemplate
    }

    // MARK: - Background Processing
    
    @BackgroundDataActor
    private func processRetirementInBackground(
        templateID: PersistentIdentifier, 
        config: RetirementConfiguration,
        container: ModelContainer
    ) async {
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0
            self.processingStatus = "Preparing..."
        }
        
        let context = ModelContext(container)
        context.autosaveEnabled = false
        
        do {
            // Fetch template by ID
            guard let template = context.model(for: templateID) as? MoleculeTemplate else {
                throw RetirementError.templateNotFound
            }
            
            let now = Date()
            let futureInstances = template.instances.filter { $0.scheduledDate > now } // Faulting happens here in bg
            let totalCount = futureInstances.count
            
            await MainActor.run {
                self.processingStatus = "Processing \(totalCount) instances..."
            }
            
            // Limit batch size
            let batchSize = 50
            var processedCount = 0
            
            let chunks = stride(from: 0, to: totalCount, by: batchSize).map {
                Array(futureInstances[$0..<min($0 + batchSize, totalCount)])
            }
            
            for batch in chunks {
                if Task.isCancelled { throw RetirementError.cancelled }
                
                for instance in batch {
                    processInstance(instance, config: config, context: context)
                }
                
                try context.save()
                
                processedCount += batch.count
                let progress = Double(processedCount) / Double(totalCount)
                
                await MainActor.run {
                    self.processingProgress = progress
                }
            }
            
            // Finalize status
            template.retirementStatus = "pending" // Ready for undo
            // Don't need to set reason/deadline again, but ensures consistency
            
            try context.save()
            
            await MainActor.run {
                self.isProcessing = false
                self.processingStatus = "Complete"
            }
            
        } catch {
             print("Background retirement error: \(error)")
             await MainActor.run {
                 self.isProcessing = false
                 self.processingStatus = "Error"
             }
        }
    }
    
    nonisolated private func processInstance(_ instance: MoleculeInstance, config: RetirementConfiguration, context: ModelContext) {
        switch config.futureAction {
        case "keepAsOrphans":
            instance.isOrphan = true
            // We use originalMoleculeTitle from template title, but we don't have template reference easily here? 
            // Ah, instance.parentTemplate is available.
            instance.originalMoleculeTitle = instance.parentTemplate?.title 
        case "deleteAll":
            instance.isArchived = true // Soft delete first? Or context.delete(instance) if rigorous?
            // PRD said "delete". But existing logic was archive. 
            // Let's archive for safety until finalization.
            instance.isArchived = true
        case "deleteAfterDate":
            if let date = config.deleteAfterDate, instance.scheduledDate > date {
                instance.isArchived = true
            }
        default: break
        }
    }

    // Helpers
    
    private func disconnectOrphans(template: MoleculeTemplate, context: ModelContext) {
        let orphans = template.instances.filter { $0.isOrphan }
        for instance in orphans {
            instance.parentTemplate = nil
        }
    }
    
    private func deleteFutureInstances(template: MoleculeTemplate, context: ModelContext) {
        let now = Date()
        let futureInstances = template.instances.filter { $0.scheduledDate > now }
        for instance in futureInstances {
            context.delete(instance)
        }
    }
    
    private func deleteInstancesAfterDate(template: MoleculeTemplate, after date: Date, context: ModelContext) {
        let instancesToDelete = template.instances.filter { $0.scheduledDate > date }
        for instance in instancesToDelete {
            context.delete(instance)
        }
    }
    
    private func scheduleRetirementNotification(for template: MoleculeTemplate, deadline: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Retirement Pending"
        content.body = "\"\(template.title)\" will be permanently retired in 12 hours."
        content.sound = .default
        let fireDate = deadline.addingTimeInterval(-notificationOffset)
        let timeInterval = fireDate.timeIntervalSinceNow
        if timeInterval > 0 {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: "retirement-\(template.id.uuidString)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    private func cancelRetirementNotification(for template: MoleculeTemplate) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["retirement-\(template.id.uuidString)"])
    }
}

// Config Struct
struct RetirementConfiguration {
    let reason: String
    let futureAction: String
    let deleteAfterDate: Date?
}

enum RetirementError: Error {
    case templateNotFound
    case cancelled
}

