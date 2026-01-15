//
//  SyncDataActor.swift
//  Protocol
//
//  Created on 2026-01-12.
//

import Foundation
import SwiftData

/// A ModelActor that provides a safe concurrency domain for background data operations.
/// All SwiftData work (fetching, inserting, saving) happens on this actor's serial executor.
@available(iOS 17, *)
actor SyncDataActor: ModelActor {
    
    // MARK: - ModelActor Conformance
    
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: ModelExecutor
    
    // MARK: - Initialization
    
    init(container: ModelContainer) {
        self.modelContainer = container
        let context = ModelContext(container)
        context.autosaveEnabled = false // We handle saving explicitly
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }
    
    // MARK: - Public API
    
    /// Counts local records for conflict reporting
    func countLocalRecords() -> Int {
        let context = modelContext
        var count = 0
        
        if let templates = try? context.fetch(FetchDescriptor<MoleculeTemplate>()) {
            count += templates.count
        }
        if let instances = try? context.fetch(FetchDescriptor<MoleculeInstance>()) {
            count += instances.count
        }
        if let atoms = try? context.fetch(FetchDescriptor<AtomTemplate>()) {
            count += atoms.count
        }
        
        return count
    }
    
    /// Queues all local records for upload
    func queueAllRecords() async -> Int {
        let context = modelContext
        var pendingItems: [SyncQueueManager.PendingSyncItem] = []
        
        // 1. MoleculeTemplates and their atoms
        if let templates = try? context.fetch(FetchDescriptor<MoleculeTemplate>()) {
            for template in templates {
                pendingItems.append(SyncQueueManager.PendingSyncItem(
                    syncID: template.syncID,
                    modelType: "MoleculeTemplate",
                    itemCreatedAt: template.createdAt,
                    queuedAt: Date()
                ))
                
                // Atoms
                for atom in template.atomTemplates {
                    pendingItems.append(SyncQueueManager.PendingSyncItem(
                        syncID: atom.syncID,
                        modelType: "AtomTemplate",
                        itemCreatedAt: atom.createdAt,
                        queuedAt: Date()
                    ))
                }
            }
        }
        
        // 2. MoleculeInstances
        if let instances = try? context.fetch(FetchDescriptor<MoleculeInstance>()) {
            for instance in instances {
                pendingItems.append(SyncQueueManager.PendingSyncItem(
                    syncID: instance.syncID,
                    modelType: "MoleculeInstance",
                    itemCreatedAt: instance.createdAt,
                    queuedAt: Date()
                ))
            }
        }
        
        // Batch update on MainActor (single dispatch, not per-item)
        let count = pendingItems.count
        let itemsToQueue = pendingItems // Capture immutable copy for MainActor closure
        
        await MainActor.run {
            for item in itemsToQueue {
                SyncQueueManager.shared.insertOrUpdate(item)
            }
            SyncQueueManager.shared.saveQueue()
        }
        
        return count
    }
    
    /// Serializes a pending sync item to JSON
    func serializeItem(_ item: SyncQueueManager.PendingSyncItem) -> Data? {
        let context = modelContext
        let id = item.syncID
        
        do {
            switch item.modelType {
            case "MoleculeTemplate":
                let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            case "MoleculeInstance":
                let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            case "AtomTemplate":
                let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == id })
                guard let record = try context.fetch(descriptor).first else { return nil }
                return record.toSyncJSON()
                
            default:
                AppLogger.backup.warning("⚠️ Unknown model type: \(item.modelType)")
                return nil
            }
        } catch {
            AppLogger.backup.error("Failed to fetch/serialize item: \(error)")
            return nil
        }
    }
    
    /// Deletes a local record (tombstone received)
    func deleteLocalRecord(syncID: UUID, modelType: String) throws {
        let context = modelContext
        
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true
            }
            
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true
            }
            
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                record.isArchived = true
            }
            
        default:
            break
        }
        
        try context.save()
    }
    
    /// Gets the local modification date for a record
    func getLocalModifiedDate(syncID: UUID, modelType: String) -> Date? {
        let context = modelContext
        
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            return (try? context.fetch(descriptor).first)?.lastModified
            
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            return (try? context.fetch(descriptor).first)?.lastModified
            
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            return (try? context.fetch(descriptor).first)?.lastModified
            
        default:
            return nil
        }
    }
    
    /// Applies remote data (Create or Update)
    func applyRemoteData(data: Data, modelType: String, syncID: UUID, isCreate: Bool) throws {
        let context = modelContext // Actor-isolated context
        
        // Use the existing logic from DriveService, but ported here or accessing shared helper helpers?
        // Since DriveService had these as `private nonisolated`, we'll need to duplicate or move the parsing logic.
        // For safety/cleanliness, I'll adopt the specific parsing logic here directly or call out to a parser 
        // that takes the context.
        // However, DriveService's logic was robust. Let's reimplement the application logic here 
        // since it needs the Context.
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveError.invalidData
        }
        
        if isCreate {
             // Dispatch to create helpers...
             try createFromJSON(json, modelType: modelType)
        } else {
             // Dispatch to update helpers...
             try updateFromJSON(json, modelType: modelType, syncID: syncID)
        }
        
        try context.save()
    }
    
    // MARK: - Private Parsing Helpers
    
    private func createFromJSON(_ json: [String: Any], modelType: String) throws {
        let formatter = ISO8601DateFormatter()
        // context unused
        
        // IMPORTANT: Need to import/access the shared helpers from DriveService or replicate them.
        // Since they were private in DriveService, we must replicate or expose them.
        // For now, I will replicate the core creation logic here to fully isolate it in this actor.
        
        // (Re-implementing robust creation logic for 3 major types)
        // Note: This matches the logic found in DriveService.swift
        
        switch modelType {
        case "MoleculeTemplate":
            try createMoleculeTemplate(json, formatter: formatter)
        case "MoleculeInstance":
            try createMoleculeInstance(json, formatter: formatter)
        case "AtomTemplate":
            try createAtomTemplate(json, formatter: formatter)
        default:
            AppLogger.backup.warning("Unknown model type: \(modelType)")
        }
    }
    
    private func updateFromJSON(_ json: [String: Any], modelType: String, syncID: UUID) throws {
        let context = modelContext
        
        switch modelType {
        case "MoleculeTemplate":
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                applyJSONToMoleculeTemplate(json: json, record: record)
            }
        case "MoleculeInstance":
            let descriptor = FetchDescriptor<MoleculeInstance>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                applyJSONToMoleculeInstance(json: json, record: record)
            }
        case "AtomTemplate":
            let descriptor = FetchDescriptor<AtomTemplate>(predicate: #Predicate { $0.id == syncID })
            if let record = try context.fetch(descriptor).first {
                applyJSONToAtomTemplate(json: json, record: record)
            }
        default:
            break
        }
    }
    
    // --- Model Specific Creation/Update Logic (Ported from DriveService for Actor Safety) ---
    
    private func createMoleculeTemplate(_ json: [String: Any], formatter: ISO8601DateFormatter) throws {
        guard let syncIDStr = safeString(json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let title = safeString(json["title"]),
              let baseTimeStr = safeString(json["baseTime"]),
              let baseTime = formatter.date(from: baseTimeStr) else { return }
        
        let recurrenceFreq = RecurrenceFrequency(rawValue: safeString(json["recurrenceFreq"]) ?? "") ?? .daily
        let recurrenceDays = json["recurrenceDays"] as? [Int] ?? []
        let endRuleType = RecurrenceEndRuleType(rawValue: safeString(json["endRuleType"]) ?? "") ?? .never
        
        let template = MoleculeTemplate(
            id: syncID,
            title: title,
            baseTime: baseTime,
            recurrenceFreq: recurrenceFreq,
            recurrenceDays: recurrenceDays,
            endRuleType: endRuleType,
            endRuleDate: formatter.date(from: safeString(json["endRuleDate"]) ?? ""),
            endRuleCount: json["endRuleCount"] as? Int,
            notes: safeString(json["notes"]),
            compound: safeString(json["compound"]),
            alertOffsets: json["alertOffsets"] as? [Int] ?? [15],
            isAllDay: safeBool(json["isAllDay"]),
            iconSymbol: safeString(json["iconSymbol"]),
            createdAt: formatter.date(from: safeString(json["createdAt"]) ?? "") ?? Date()
        )
        
        template.isPinned = safeBool(json["isPinned"])
        template.sortOrder = json["sortOrder"] as? Int ?? 0
        if let frame = safeString(json["iconFrameRaw"]) { template.iconFrameRaw = frame }
        if let color = safeString(json["themeColorHex"]) { template.themeColorHex = color }
        
        modelContext.insert(template)
    }
    
    private func createMoleculeInstance(_ json: [String: Any], formatter: ISO8601DateFormatter) throws {
        guard let syncIDStr = safeString(json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let scheduledDateStr = safeString(json["scheduledDate"]),
              let scheduledDate = formatter.date(from: scheduledDateStr) else { return }
        
        var parentTemplate: MoleculeTemplate?
        if let parentIDStr = safeString(json["moleculeTemplateID"]), let parentID = UUID(uuidString: parentIDStr) {
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == parentID })
            parentTemplate = try? modelContext.fetch(descriptor).first
        }
        
        let instance = MoleculeInstance(
            id: syncID,
            scheduledDate: scheduledDate,
            isCompleted: safeBool(json["isCompleted"]),
            isException: safeBool(json["isException"]),
            exceptionTitle: safeString(json["exceptionTitle"]),
            exceptionTime: formatter.date(from: safeString(json["exceptionTime"]) ?? ""),
            parentTemplate: parentTemplate,
            alertOffsets: json["alertOffsets"] as? [Int],
            isAllDay: safeBool(json["isAllDay"]),
            createdAt: formatter.date(from: safeString(json["createdAt"]) ?? "") ?? Date(),
            notes: safeString(json["notes"])
        )
        instance.completedAt = formatter.date(from: safeString(json["completedAt"]) ?? "")
        if let origStr = safeString(json["originalScheduledDate"]), let orig = formatter.date(from: origStr) {
            instance.originalScheduledDate = orig
        }
        
        modelContext.insert(instance)
    }
    
    private func createAtomTemplate(_ json: [String: Any], formatter: ISO8601DateFormatter) throws {
        guard let syncIDStr = safeString(json["syncID"]),
              let syncID = UUID(uuidString: syncIDStr),
              let title = safeString(json["title"]) else { return }
        
        let inputType = AtomInputType(rawValue: safeString(json["inputType"]) ?? "") ?? .binary
        
        var parentTemplate: MoleculeTemplate?
        if let parentIDStr = safeString(json["moleculeTemplateID"]), let parentID = UUID(uuidString: parentIDStr) {
            let descriptor = FetchDescriptor<MoleculeTemplate>(predicate: #Predicate { $0.id == parentID })
            parentTemplate = try? modelContext.fetch(descriptor).first
        }
        
        let atom = AtomTemplate(
            id: syncID,
            title: title,
            inputType: inputType,
            targetValue: json["targetValue"] as? Double,
            unit: safeString(json["unit"]),
            order: json["order"] as? Int ?? 0,
            targetSets: json["targetSets"] as? Int,
            targetReps: json["targetReps"] as? Int,
            defaultRestTime: json["defaultRestTime"] as? TimeInterval,
            videoURL: safeString(json["videoURL"]),
            parentMoleculeTemplate: parentTemplate,
            createdAt: formatter.date(from: safeString(json["createdAt"]) ?? "") ?? Date(),
            iconSymbol: safeString(json["iconSymbol"])
        )
        
        if let frame = safeString(json["iconFrameRaw"]) { atom.iconFrameRaw = frame }
        if let color = safeString(json["themeColorHex"]) { atom.themeColorHex = color }
        
        modelContext.insert(atom)
    }
    
    // --- Update Helpers ---
    
    private func applyJSONToMoleculeTemplate(json: [String: Any], record: MoleculeTemplate) {
        let f = ISO8601DateFormatter()
        
        // Core fields
        if let v = safeString(json["title"]) { record.title = v }
        if let v = json["isDeleted"] { record.isArchived = safeBool(v) }
        if let v = safeString(json["baseTime"]), let d = f.date(from: v) { record.baseTime = d }
        
        // Recurrence
        if let v = safeString(json["recurrenceFreq"]), let freq = RecurrenceFrequency(rawValue: v) { record.recurrenceFreq = freq }
        if let days = json["recurrenceDays"] as? [Int] { record.recurrenceDays = days }
        if let v = safeString(json["endRuleType"]), let ruleType = RecurrenceEndRuleType(rawValue: v) { record.endRuleType = ruleType }
        if let v = safeString(json["endRuleDate"]), let d = f.date(from: v) { record.endRuleDate = d }
        if let v = json["endRuleCount"] as? Int { record.endRuleCount = v }
        
        // Optional fields
        if let v = safeString(json["notes"]) { record.notes = v }
        if let v = safeString(json["compound"]) { record.compound = v }
        if let v = json["alertOffsets"] as? [Int] { record.alertOffsets = v }
        if let v = json["isAllDay"] { record.isAllDay = safeBool(v) }
        if let v = json["isPinned"] { record.isPinned = safeBool(v) }
        if let v = json["sortOrder"] as? Int { record.sortOrder = v }
        
        // Appearance
        if let v = safeString(json["iconSymbol"]) { record.iconSymbol = v }
        if let v = safeString(json["iconFrameRaw"]) { record.iconFrameRaw = v }
        if let v = safeString(json["themeColorHex"]) { record.themeColorHex = v }
        
        // Timestamps
        if let v = safeString(json["updatedAt"]), let d = f.date(from: v) { record.updatedAt = d }
    }
    
    private func applyJSONToMoleculeInstance(json: [String: Any], record: MoleculeInstance) {
        let f = ISO8601DateFormatter()
        
        // Core fields
        if let v = json["isCompleted"] { record.isCompleted = safeBool(v) }
        if let v = json["isDeleted"] { record.isArchived = safeBool(v) }
        if let v = safeString(json["scheduledDate"]), let d = f.date(from: v) { record.scheduledDate = d }
        if let v = safeString(json["completedAt"]), let d = f.date(from: v) { record.completedAt = d }
        
        // Exception handling
        if let v = json["isException"] { record.isException = safeBool(v) }
        if let v = safeString(json["exceptionTitle"]) { record.exceptionTitle = v }
        if let v = safeString(json["exceptionTime"]), let d = f.date(from: v) { record.exceptionTime = d }
        if let v = safeString(json["originalScheduledDate"]), let d = f.date(from: v) { record.originalScheduledDate = d }
        
        // Optional fields
        if let v = safeString(json["notes"]) { record.notes = v }
        if let v = json["alertOffsets"] as? [Int] { record.alertOffsets = v }
        if let v = json["isAllDay"] { record.isAllDay = safeBool(v) }
        
        // Timestamps
        if let v = safeString(json["updatedAt"]), let d = f.date(from: v) { record.updatedAt = d }
    }
    
    private func applyJSONToAtomTemplate(json: [String: Any], record: AtomTemplate) {
        let f = ISO8601DateFormatter()
        
        // Core fields
        if let v = safeString(json["title"]) { record.title = v }
        if let v = json["isDeleted"] { record.isArchived = safeBool(v) }
        if let v = safeString(json["inputType"]), let inputType = AtomInputType(rawValue: v) { record.inputType = inputType }
        
        // Target values
        if let v = json["targetValue"] as? Double { record.targetValue = v }
        if let v = safeString(json["unit"]) { record.unit = v }
        if let v = json["order"] as? Int { record.order = v }
        
        // Workout fields
        if let v = json["targetSets"] as? Int { record.targetSets = v }
        if let v = json["targetReps"] as? Int { record.targetReps = v }
        if let v = json["defaultRestTime"] as? TimeInterval { record.defaultRestTime = v }
        
        // Media
        if let v = safeString(json["videoURL"]) { record.videoURL = v }
        
        // Appearance
        if let v = safeString(json["iconSymbol"]) { record.iconSymbol = v }
        if let v = safeString(json["iconFrameRaw"]) { record.iconFrameRaw = v }
        if let v = safeString(json["themeColorHex"]) { record.themeColorHex = v }
        
        // Timestamps
        if let v = safeString(json["updatedAt"]), let d = f.date(from: v) { record.updatedAt = d }
    }
    
    // --- Safe Extraction Helpers ---
    
    private func safeString(_ val: Any?) -> String? {
        return val as? String
    }
    
    private func safeBool(_ val: Any?) -> Bool {
        if let boolVal = val as? Bool { return boolVal }
        if let strVal = val as? String { return strVal.lowercased() == "true" }
        if let intVal = val as? Int { return intVal != 0 }
        return false
    }
}
